#!/usr/bin/perl

use Socket;
use POSIX ":sys_wait_h";

#Initialisation du server avec les valeur du fichier "comanche.conf"
init;
socket (SERVEUR, PF_INET, SOCK_STREAM, getprotobyname('tcp'));
setsockopt (SERVEUR, SOL_SOCKET, SO_REUSEADDR, 1);
$mon_adresse = sockaddr_in ($confs{"set"}{"port"}, INADDR_ANY);
bind(SERVEUR, $mon_adresse) || die ("bind");
listen (SERVEUR, SOMAXCONN) || die ("listen");

#Tant que le serveur reçoie des requêtes 
while (true) {
    accept (CLIENT, SERVEUR) || die ("accept");

    if(fork() == 0) {
	CLIENT->autoflush(1);
	while (<CLIENT>){
	    print CLIENT "serveur : $_";
	}
	exit 0;
    }

    close (CLIENT);
    do{
	$wPid = waitpid(-1,WNOHANG);
    }while($wPid > 0);
}

close (SERVEUR);

sub init{
	sub order{
		if(s/^set ([\w]+)/$1/g) {
			@order = split / /;
			@variables = ("port", "error", "index", "logfile", "clients");
			#Verification de la variable
			grep(/^$order[0]/, @variables) or die "Invalid variable : $!";
			$confs{"set"}{$order[0]} = $order[1];
		}
		else {
			@order = split / /;
			if($order[0] eq "route") {
				#Regexp1 comme clef, Regexp2 comme valeur:
				$order[2] eq "to" or die "Invalid route : $!";
				$confs{"route"}{$order[1]} = $order[3];
			}
			else
			{	
				#Regexp1 comme clef, Regexp2 comme valeur:
				$order[2] eq "from" or die "Invalid route : $!";
				$confs{"exec"}{$order[1]} = $order[3];
			}
		}
	}

	#Hashmap des ordres:
	%confs;
	$confs{"set"}{$port} = 8080;
	$confs{"set"}{$error} = "";
	$confs{"set"}{$index} = "";
	$confs{"set"}{$logfile} = "";
	$confs{"set"}{$clients} = 1;

	#Ouverture du fichier de config
	open(CONFIG, "comanche.conf") or die "open: $!";

	#Fixation des variables
	while(<CONFIG>) {
		#Suppression des espaces
		s/^[ \t]+//g;
		#On ignore les commentaires
		if(!/^[#\t\n\ ]+/) {
			#Verification de l'ordre
			$order = /^set|^route|^exec/ or die "Invalid order: $!";
			#Ajout a la hashmap correspondante
			order $order;
		}
	}

	close(CONFIG);
} 

sub getVerif{

}