#!/usr/bin/perl

use Socket;
use POSIX ":sys_wait_h";

# Initialisation du server avec les valeurs du fichier "comanche.conf"
init("comanche.conf");

while(<STDIN>){
	lectureRequete($_);
}

#Initialisation des paramétres
sub init{
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
sub lectureRequete{
	if ($_ =~ /(?-i)GET(?i)\s(\/(?:.*))\sHTTP\/1\.1/){
		$chemin = verifProjection($1);
		
		if ($chemin){
			verifChemin($chemin);
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
sub verifProjection{
		$path = shift();
		$chemin = undef;
		foreach $route (@routes) {
			if ($path =~ $route){
				if(exists $confs{"route"}{$route})
				{
					$routeExec = "route";
				}
				elsif(exists $confs{"exec"}{$route})
				{
					$routeExec = "exec";
				}
				else
				{
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

# Verifie si ce que l'on demande existe, si oui, une réponse est créer en fonction du type MIME
sub verifChemin{
	$chemin = substr($_[0],1);
	print $chemin, "\n";
	if (! -e $chemin)
	{
		error404();
	}
	else {
		#TODO: tester si c'est un dossier, sinon tester son type MIME pour construire une réponse
		print "Le fichier existe, maintenant il faut tester son MIME \n";
	}
}

# Procedure permettant de lire le contenue d'un fichier avant de l'afficher
sub readFile
{
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

# Renvoie erreur 404
sub error404
{
    # On considere que la page par default est celle qui reponds a une erreur de type 404
    $reponse = readFile($confs{"set"}{"error"});
    $reponse .= "<hr><p>Comanche Version 1</p>";
    # On envoie la réponse
    print "HTTP/1.1 404 Not Found\r\n" .
	      "Content-Type: text/html\r\n" .
		  "Content-Length: " . length($reponse) . "\r\n\r\n" .
		 $reponse;
    exit 0;
}

# Renvoie erreur 400
sub error400
{
    $reponse = "<html><head><title>Bad request</title></head><body><h1>Bad Request</h1><hr><p>Comanche Version 1</p></body></html>";
    print "HTTP/1.1 400 Bad Request\r\n" .
	      "Content-type : text/html\r\n" .
		  "Content-Length: " . length($reponse) . "\r\n\r\n" .
		 $reponse;
    exit 0;

}