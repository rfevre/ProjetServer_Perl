#!/usr/bin/perl

use Socket;
use POSIX ":sys_wait_h";

no warnings qw( experimental::autoderef );
no warnings 'experimental::smartmatch';

# Fichier contenant le pid du processus principal
$pidServFile = ".pid";

#Signaux
$SIG{QUIT} = \&stopProcessus;

# Nombre de clients connecter
$nbrClients = 0;

checkParameter();

# On demarre le serveur
sub checkParameter
{
	die "Parametre : start/stop/status\n" if @ARGV != 1;

	if ($ARGV[0] eq "start")
	{
		start();
	}
	elsif ($ARGV[0] eq "stop")
	{
		stop();
	}
	elsif ($ARGV[0] eq "status")
	{
		status();
	}
	else
	{
		die "Incorrect parametre : start/stop/status\n";
	}
}

# Fonction pour démarrer le serveur
sub start
{
	#Si le serveur est déjà demarré on arrete le lancement
    if(-f $pidServFile){
		die("Comanche est déjà en cours d'executions\n");
    }
    else {
    	# Initialisation du server avec les valeurs du fichier "comanche.conf"
		init("comanche.conf");
   		demarrerServeur();
    }
}

# Fonction pour arréter le serveur
sub stop
{
	kill QUIT, getpid() || die("Le serveur n'est pas en cours d'execution\n");
    unlink($pidServFile);
    print "Serveur arrêté !","\n";
	ecrireDansLog("stop", "local", $confs{"set"}{"port"}, "", "");
}

sub stopProcessus {
	$start = 0;
	while (wait != -1) {}
}

# Fonction pour afficher le status du serveur
sub status
{

}

#Initialisation des paramétres
sub init {
	sub order{
		if(s/^set ([\w]+)/$1/g) {
			@order = split / /;
			@variables = ("port", "error", "index", "logfile", "clients");
			# Verification de la variable
			grep(/^$order[0]/, @variables) or die "Invalid variable : $!";
			$confs{"set"}{$order[0]} = $order[1];
		}
		else {
			@order = split / /;
			if($order[0] eq "route") {
				# Regexp1 comme clef, Regexp2 comme valeur:
				$order[2] eq "to" or die "Invalid route : $!";
				$confs{"route"}{$order[1]} = $order[3];
				push @routes, $order[1];
			}
			else
			{	
				# Regexp1 comme clef, Regexp2 comme valeur:
				$order[2] eq "from" or die "Invalid exec : $!";
				$confs{"exec"}{$order[1]} = $order[3];
				push @routes, $order[1];
			}
		}
	}

	# Hashmap des ordres:
	%confs;
	$confs{"set"}{"port"} = 8080;
	$confs{"set"}{"error"} = "";
	$confs{"set"}{"index"} = "";
	$confs{"set"}{"logfile"} = "";
	$confs{"set"}{"clients"} = 1;
	@routes = ();
	$routeExec = "route";

	# Ouverture du fichier de config
	open(CONFIG, shift() ) or die "open: $!";

	#Fixation des variables
	while(<CONFIG>) {
		#Suppression des espaces
		s/^[ \t]+//g;
		#Suppression des commentaires
		s/#*//g;
		#
		if(!/^[\s\n]+/) {
			chomp;
			#Verification de l'ordre
			$order = /^set|^route|^exec/ or die "Invalid order: $!";
			#Ajout a la hashmap correspondante
			order $order;
		}
	}

	close(CONFIG);
} 

# Démarrage du serveur
sub demarrerServeur
{
	my $pid = fork();
	# Le père se quitte, le fils va créer le listener et instancier un autre fils par requête à partir d'ici.
	if($pid == 0)
	{
		socket (SERVER, PF_INET, SOCK_STREAM, getprotobyname('tcp'));
		setsockopt (SERVER, SOL_SOCKET, SO_REUSEADDR, 1);
		my $addr = sockaddr_in ($confs{"set"}{"port"}, INADDR_ANY) || do { unlink($pidServFile); die ("sockaddr_in\n"); };
		bind(SERVER, $addr) || do { unlink($pidServFile); die ("Bind : $!"); };
		listen(SERVER, SOMAXCONN) || do { unlink($pidServFile); die "Listen : $!"; };

		#variable qui permet de gerer le start/stop du serveur
		$start = 1;

		while (accept(CLIENT,SERVER) or do { last if $start eq 0; die("Accept impossible : $!\n"); } ) {
			CLIENT->autoflush(1);

			# Si trop de client simultannée
		    if($nbrClients > $config{"set"}{"clients"}){
		    	print CLIENT error503();
		    	exit 0;
		    }
		    # Sinon on lance le fork pour que les clients puissent se connecter en simultannées
		    else{
				$pid = fork();

				if($pid == 0){
					#permet de recuperer l'addresse IP du client
				    $peer = getpeername(CLIENT);
				    ($port, $iaddr) = sockaddr_in($peer);
				    $ipClient = inet_ntoa($iaddr);

					$requete = <CLIENT>;
					chomp($requete);
					print CLIENT lectureRequete($requete);
					exit 0;
				}
			}
			close(CLIENT) or die ("Close Client : $!");
		}

		close(SERVER) or die ("Close Server : $!");
	}
	else
	{
		# On enregistre le pid du serveur
		open(PID, ">$pidServFile");
		print PID $pid;
		close(PID);
		print "Serveur lancé !\n";
		ecrireDansLog("start", "local", $confs{"set"}{"port"}, "", "");
		exit 0;
	}

}

# Traitement requête GET
sub lectureRequete {
	#Requete
	my $message;
	my $requete = shift();

	if ($requete =~ /(?-i)GET(?i)\s(\/(?:.*))\sHTTP\/1\.1/) {
		my $chemin = verifProjection($1);
		
		if ($chemin) {
			$message = verifChemin(substr($chemin,1));
		}
		else {
			$message = error404();
		}
	}
	else {
		$message = error400();
	}

	return $message;
}

# Verifie toute les projections
sub verifProjection {
		my $path = shift();
		my $chemin = undef;
		foreach $route (@routes) {
			if ($path =~ $route) {
				if(exists $confs{"route"}{$route}) {
					$routeExec = "route";
				}
				elsif(exists $confs{"exec"}{$route}) {
					$routeExec = "exec";
				}
				else {
					next;
				}
				$chemin = $confs{$routeExec}{$route};
				$chemin =~ s!\/+!\/!g;

				$routeTmp = qr/$route/;
				$_ = $path;

				@matches = m/$routeTmp/;

				for (@matches) {
					$m = $matches[$i++];
					$chemin =~ s{\\$i}{$m};
				}
				m/$chemin/;
				last;
			}
		}
		return $chemin;
}

# Verifie si la ressource demandé existe, si oui, une réponse est créée en fonction du type de la ressource
sub verifChemin {
	my $chemin = shift();
	my $message;
	# Si la ressource n'existe pas
	if (! -e $chemin) {
		$message = error404();
	}
	else {
		# Si fichier ou dossier
		if ($routeExec eq "route") {
			$message = versFichiers($chemin);
		}
		# Si Exec
		else {
			$message = versCGI($chemin);
		}
	}

	return $message;
}

# Créer la réponse si c'est un fichier ou dossier
sub versFichiers {
	my $chemin = shift();
	my $message;
	# Si c'est un dossier
	if (-d $chemin) {
		# Et que l'index existe
		if (-e "$chemin/$confs{\"set\"}{\"index\"}") {
			$chemin = "$chemin/$confs{\"set\"}{index}";
			$message = envoieReponseFichier($chemin, "text/html");
		}
		# Sinon on créer une page html pour lister son contenu
		else {
			$chemin = listerElements($chemin);
			$message = envoieReponseFichier($chemin, "text/html");
			}
		}
	# Si fichier
	else {
		# On vérifie son type et on le retourne si il est dans la liste des types supportés
		@ext = ("html", "png", "txt");
		if((split(/\./, "$chemin"))[-1] ~~ @ext) {
			if((split(/\./, "$chemin"))[-1] eq "html") {
				$mime = "text/html";
			}
			elsif((split(/\./, "$chemin"))[-1] eq "png") {
				$mime = "image/png";
			}
			elsif((split(/\./, "$chemin"))[-1] eq "txt") {
				$mime = "text/plain";
			}
			$message = envoieReponseFichier($chemin, $mime);
		}
		else {
			$message = error415();
		}
	}

	return $message;
}

# Créer la réponse si c'est un programme CGI
sub versCGI {
	my $chemin = shift();
	my $message;
	my $reponse = `perl $chemin`;
	my $mime = ".html";
	$message = envoieReponseCGI($reponse, $mime);

	return $message;
}

# Créer une réponse HTML qui liste tous les fichiers d'un dossier
sub listerElements {
	my $chemin = shift();
	my $liste = "$chemin/.liste.html";
	open(FIC, '>', $liste) or die "Open : $liste :  $!";

	print FIC "<html>\n\t<head>\n\t\t<title>Liste elements</title>\n\t</head>\n\t<body>\n\t\t<center>\n\t\t\t<h1>Liste elements</h1>\n\t\t\t<ul>";
	foreach $file (glob("$chemin/*")) {
		$file = (split(/\//, "$file"))[-1];
		print FIC "\n\t\t\t\t<li><a href=\"$file\">$file</a></li>";
	}
	print FIC "\n\t\t\t</ul>\n\t\t</center>\n\t</body>\n</head>";

	close(FIC);
	return $liste;
}
 
# Verifie si le fichier log existe, si il n'existe pas, il est créé
sub verifFichierLog {
    $logFile = $confs{"set"}{"logfile"};
    $logFile = "comanche.log" if(! -f $logFile);

    open(LOGFILE, ">>$logFile") or die "Open logFile : $!";

    close LOGFILE or die "Close logFile : $!";
}

# Ecrit dans le fichier de "log"
# Parametres : "Type" - "Machine" - "Requete" - "Projection" - "Reponse"
sub ecrireDansLog {
	verifFichierLog();
	
    my $date = time();
    my $type = shift;
    my $machine = shift;
    my $requete = shift;
    my $projection = shift;
    my $reponse = shift;

    open(LOGFILE, ">>$logFile") or die "Open logFile : $!";

    print LOGFILE "$date;$type;$machine;$requete;$projection;$reponse;\n";

    close LOGFILE or die "Close logFile : $!";
}


# Permet d'obtenir le pid stocker dans un fichier lors du demerage
sub getpid {
    open(PID, "$pidServFile");
    my $pid = <PID>;
    close(PID);

    return $pid;
}

# Procedure permettant de lire le contenue d'un fichier avant de l'afficher
sub readFile {
    #on protege la variable
    my $contenu;
    
    #on ouvre le fichier passer en parametre. vide sinon
    open(FICHIER, $_[0]) || return "";
    while (<FICHIER>) {
        $contenu .= $_;
    }
    close(FICHIER);
    #on retour le contenu du fichier
    return $contenu;
}

# Construit une reponse pour les fichiers et dossiers
sub envoieReponseFichier {
	my $message;
	my $chemin = shift();
	my $mime = shift();
	my $reponse = readFile($chemin);
	$message = "HTTP/1.1 200 OK\r\n" .
				"Content-type : $mime\r\n" .
				"Content-Length : " . length($reponse) . "\r\n\r\n" .
				$reponse . "\r\n";

	ecrireDansLog("get-s", $ipClient, "$requete", "$chemin", "200");

	return $message;
}

# Construit une reponse pour les programmes CGI
sub envoieReponseCGI {
	my $message;
	my $reponse = shift();
	my $mime = shift();
	$message = "HTTP/1.1 200 OK\r\n" .
				"Content-type : $mime\r\n" .
				"Content-Length : " . length($reponse) . "\r\n\r\n" .
				$reponse . "\r\n";

	ecrireDansLog("get-d", "$ipClient", "$requete", "$chemin", "200");
	
	return $message;
}

# Envoie une erreur 404
sub error404 {
	my $message;
    # On considere que la page par default est celle qui reponds a une erreur de type 404
    my $reponse = readFile(substr($confs{"set"}{"error"}, 1));
    # On envoie la réponse
    $message = "HTTP/1.1 404 Not Found\r\n" .
	      		"Content-Type : text/html\r\n" .
		  		"Content-Length : " . length($reponse) . "\r\n\r\n" .
		 		$reponse . "\r\n";
    return $message;
}

# Envoie une erreur 400
sub error400 {
	my $message;
    my $reponse = "<html><head><title>Bad request</title></head><body><h1>Bad Request</h1></body></html>";
    $message = "HTTP/1.1 400 Bad Request\r\n" .
	      		"Content-type : text/html\r\n" .
		  		"Content-Length: " . length($reponse) . "\r\n\r\n" .
		 		$reponse . "\r\n";
    return $message;
}

sub error415 {
	my $message;
	my $reponse = "<html><head><title>Unsupported Media Type</title></head><body><h1>Unsupported Media Type</h1></body></html>";
	$message = "HTTP/1.1 415 Unsupported Media Type\r\n" .
				"Content-type : text/html\r\n" .
				"Content-Length : " . length($reponse) . "\r\n\r\n" .
				$reponse . "\r\n";
	return $message;
}

sub error503 {
	my $message;
	my $reponse  = "<html><head><title>Service Unavailable<</title></head><body><h1>Service Unavailable</h1><h2>Trop de connexions simultanées, réessayez plus tard</h2></body></html>";		 
	$message = "HTTP/1.1 503 Service Unavailable\r\n" .
	        	"Content-Type: text/html; charset=utf-8\r\n" .
				"Content-Length: " . length($reponse) . "\r\n\r\n" .
				$reponse . "\r\n";
	return $message;
}