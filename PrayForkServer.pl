#!/usr/bin/perl

use Socket;
use POSIX ":sys_wait_h";

no warnings qw( experimental::autoderef );
no warnings 'experimental::smartmatch';

# Initialisation du server avec les valeurs du fichier "comanche.conf"
init("comanche.conf");

while(<STDIN>) {
	lectureRequete($_);
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


# Traitement requête GET
sub lectureRequete {
	if ($_ =~ /(?-i)GET(?i)\s(\/(?:.*))\sHTTP\/1\.1/) {
		$chemin = verifProjection($1);
		
		if ($chemin) {
			verifChemin(substr($chemin,1));
		}
		else {
			error404();
		}
	}
	else {
		error400();
	}
}

# Verifie toute les projections
sub verifProjection {
		$path = shift();
		$chemin = undef;
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
	$chemin = shift();
	# Si la ressource n'existe pas
	if (! -e $chemin) {
		error404();
	}
	else {
		# Si fichier ou dossier
		if ($routeExec eq "route") {
			versFichiers($chemin);
		}
		# Si Exec
		else {
			versCGI($chemin);
		}
	}
}

sub versFichiers {
	$chemin = shift();
	# Si c'est un dossier
	if (-d $chemin) {
		# Et que l'index existe
		if (-e "$chemin/$confs{\"set\"}{\"index\"}") {
			$chemin = "$chemin/$confs{\"set\"}{index}";
			envoieOk($chemin, "text/html");
		}
		# Sinon on créer une page html pour lister son contenu
		else {
			$chemin = listerElements($chemin);
			envoieOk($chemin, "text/html");
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
			envoieOk($chemin, $mime);
		}
		else {
			error415();
		}
	}
}

sub versCGI {
	$chemin = shift();
	$reponse = `perl $chemin`;
	$mime = ".html";
	envoieReponse($reponse, $mime);
}

# Créer une réponse HTML qui liste tous les fichiers d'un dossier
sub listerElements {
	$chemin = shift();
	$liste = "$chemin/liste.html";
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

# Envoie Ok
sub envoieOk {
	$chemin = shift();
	$mime = shift();
	$reponse = readFile($chemin);
	print "HTTP/1.1 200 OK\r\n" .
			"Content-type : $mime\r\n" .
			"Content-Length : " . length($reponse) . "\r\n\r\n" .
			$reponse . "\r\n";
	exit 0;
}

# Envoie une reponse
sub envoieReponse {
	$reponse = shift();
	$mime = shift();
	print "HTTP/1.1 200 OK\r\n" .
			"Content-type : $mime\r\n" .
			"Content-Length : " . length($reponse) . "\r\n\r\n" .
			$reponse . "\r\n";
	exit 0;
}

# Envoie une erreur 404
sub error404 {
    # On considere que la page par default est celle qui reponds a une erreur de type 404
    $reponse = readFile(substr($confs{"set"}{"error"}, 1));
    # On envoie la réponse
    print "HTTP/1.1 404 Not Found\r\n" .
	      	"Content-Type : text/html\r\n" .
		  	"Content-Length : " . length($reponse) . "\r\n\r\n" .
		 	$reponse . "\r\n";
    exit 0;
}

# Envoie une erreur 400
sub error400 {
    $reponse = "<html><head><title>Bad request</title></head><body><h1>Bad Request</h1><hr><p>Comanche Server</p></body></html>";
    print "HTTP/1.1 400 Bad Request\r\n" .
	      	"Content-type : text/html\r\n" .
		  	"Content-Length: " . length($reponse) . "\r\n\r\n" .
		 	$reponse . "\r\n";
    exit 0;
}

sub error415 {
	$reponse = "<html><head><title>Unsupported Media Type</title></head><body><h1>Unsupported Media Type</h1><hr><p>Comanche Server</p></body></html>";
	print "HTTP/1.1 415 Unsupported Media Type\r\n" .
			"Content-type : text/html\r\n" .
			"Content-Length : " . length($reponse) . "\r\n\r\n" .
			$reponse . "\r\n";
	exit 0;
}