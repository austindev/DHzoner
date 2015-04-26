###############################################################################
##	bootLib.							     ##
## 	Functions for use in booting Superdome2 partitions to EFI	     ##
##									     ##
##  Author: Austin H. Bernard        austin.bernard@hp.com 		     ##	
##  Date Created: 04/02/2012						     ##
##  Last Modified: 05/01/2012 AHB					     ##
###############################################################################


##=================================oaCliLogin================================##
# PURPOSE: 	Login to cli on an OA.
# PRE: 		None
# POST: 	An open ssh session is left. The spawn_id is returned.
##=====================================|=====================================##
sub oaCliLogin {
    my($host, $user, $pass, $port) = @_;
    my $timeout = 30;
    my $spawn_id = new Expect ('ssh', $host, "-l", $user, "-p", $port)
    	or die "Cannot spawn ssh: $1\n";

    $spawn_id->expect($timeout,
		[qr/password: /i,
			sub {
			    $spawn_id->send("$pass\n");
			    # Need to find something to search for
			    # other than 'oa.' Possibly '>' twice
			    # Use reg. exp. to search for second '>'
			    $spawn_id->expect ($timeout, [qr/>/]);
			    $spawn_id->expect ($timeout, [qr/>/]);
			}],
		[qr/continue connecting/i,
			sub {
			    $spawn_id->send("yes\n");
			    exp_continue;
			}]
		    );
    $spawn_id;
}
## END oaCliLogin

##===========================commandeerTerminalCore==========================##
# PURPOSE: 	Perform bump on a viewer window
# PRE: 		spawn_id open to EFI viewer
# POST: 	None
##=====================================|=====================================##
sub commandeerTerminalCore {
    my ($spawn_id) = @_;
    my $timeout = 30;
    $spawn_id->send("\cE", "cf", "\r");
    $spawn_id->expect($timeout, [qr/Bumped|attached/i]);
}
## END commandeerTerminalCore

##===============================spawnidsAtEFI===============================##
# PURPOSE: 	Creates a list of separate connections to each partition
# 			being booted
# PRE: 		A list of partitions being booted
# POST: 	Return a list of connections
##=====================================|=====================================##
sub spawnidsAtEFI {
    my($host, $user, $pass, $port, @booting_pars) = @_;
    #my $num_pars = @booting_pars;
    my $timeout = undef;
    my @spawn_ids;

    for (my $n = 0; $n < scalar @booting_pars; $n++) {
        push (@spawn_ids, &oaCliLogin ($host, $user, $pass, $port));
        $spawn_ids[$n]->send("co $booting_pars[$n]\r");
        $spawn_ids[$n]->expect($timeout, [qr/Welcome to/i]);
        &commandeerTerminalCore($spawn_ids[$n]);
    }
    @spawn_ids;
}
## END spawnidsAtEFI

##==================================listPars=================================##
# PURPOSE: 	Get output of 'co' command from OA cli.
# PRE: 		None
# POST: 	Output of co to be parsed by find*Par subroutines.
##=====================================|=====================================##
sub listPars {
	my($host, $user, $pass, $port) = @_;
	my $timeout = 30;
	my $spawn_id = &oaCliLogin ($host, $user, $pass, $port);

	$spawn_id->send("co\r");
	$spawn_id->expect($timeout, [qr/number:/i]);

	my $pars_list = $spawn_id->before();

	$spawn_id->send("q\r");
	$spawn_id->expect($timeout, [qr/>/i]);

	$pars_list;
}
## END listPars

##==================================findnPars=================================##
# PURPOSE:	Lists only nPars
# PRE: 		Output from a 'co' command (listPars).
# POST: 	List of all nPars on a system.
##=====================================|=====================================##
sub findnPars {
#   my ($pars_list) = @_;
#   my @nPars = ($pars_list =~ m/\s(\d+)\s/g);
    my @nPars = ($_[0] =~ m/\s(\d+)\s/g);
}
## End findnPars

##==================================findvPars=================================##
# PURPOSE:	Lists only vPars
# PRE: 		Output from a 'co' command (listPars).
# POST: 	List of all vPars on a system.
##=====================================|=====================================##
sub findvPars {
    my ($pars_list) = @_;
    my @vPars = ($pars_list =~ m/\d+:\d+/g);
}
## END findvPars

##==============================findPartitonvPars============================##
# PURPOSE:	Find the vPars in a specific nPar.
# PRE: 		Output from a 'co' command (listPars).
# POST: 	List of vPars in a specific npar.
##=====================================|=====================================##
sub findPartitionvPars {
    my ($pars_list, $partition) = @_;
    my @vPars = ($pars_list =~ m/$partition:\d+/g);
}
## END findPartitionvPars

##=================================findNumPars===============================##
# PURPOSE:	Find the number of partitions on a system
# PRE: 		None
# POST: 	Scalar value of the number of partitions.
##=====================================|=====================================##
sub findNumPars {
	my($host, $user, $pass, $port) = @_;
	my $oa_sid = &oaCliLogin($host, $user, $pass, $port);
	my $pars_list = &listPars($host, $user, $pass, $port);
	my $num_pars = &findBootablePars($oa_sid, $pars_list);
}

##================================findBootMode===============================##
# PURPOSE: 	Find the Next boot mode for a single nPar.
# PRE: 		nPar number, connection to host.
# POST: 	Returns variable $boot_mode as either 'npars' or 'vpars'
##=====================================|=====================================##
sub findBootMode {
    my ($spawn_id, $partition) = @_;
    my $timeout = 30;
    
    $spawn_id->send("parstatus -p$partition -V\n");
    $spawn_id->expect($timeout, [qr/>/i]);

	# Terminal output from parstatus command up until expected '>'
    my $output = $spawn_id->before();

    if ($output =~ /Next boot mode[\s+]*:[\s+]+(.pars)/) {
        my $boot_mode = $1;
    }
}
## END findBootMode

##==============================findBootablePars=============================##
# PURPOSE:	Lists only nPars and vPars bootable to EFI/HP-UX based
# 			upon the nPar's Next boot mode.
# PRE: 		Output from a 'co' command (listPars), connection to host.
# POST: 	List of bootable vPars and nPars.
##=====================================|=====================================##
sub findBootablePars {
    my ($spawn_id, $pars_list) = @_;
    my @nPars = &findnPars($pars_list);
    my @bootable_pars;

    foreach my $partition (@nPars) {
        my $boot_mode = &findBootMode($spawn_id, $partition);

        if ($boot_mode eq "npars") {
            push(@bootable_pars, $partition);
        } elsif ($boot_mode eq "vpars") {
           push(@bootable_pars, &findPartitionvPars($pars_list, $partition));
        }
    }
    @bootable_pars;
}
## END findBootablepars

##=================================poweronPars===============================##
# PURPOSE: 	Sends 'poweron partition' command to each booting partition.
# PRE: 		List of booting partitions, connection to host.
# POST: 	None.
##=====================================|=====================================##
sub poweronPars {
    my ($spawn_id, @booting_pars) = @_;
    my $timeout = 30;

    foreach my $partition (@booting_pars) {
        $spawn_id->send("poweron partition $partition\n");
        $spawn_id->expect($timeout, [qr/>/]);
    }
}
## END poweronPars

##================================checkValidPars==============================##
# PURPOSE: 	Checks if the selected partitions are bootable.
# PRE: 		List of selected partitions, list of bootable partitions.
# POST: 	Returns 1 if all selected partitions are valid, 0 otherwise.
##=====================================|=====================================##
sub checkValidPars {
    my ($selected_pars, $bootable_pars) = @_;
    foreach my $i (@$selected_pars) {
	if (!grep $_ eq $i, @$bootable_pars) {
	    push(@invalid_pars, $i);
	} 
    }
    if (@invalid_pars) {
	print "\n\n\t\tError: \n\t\tThe following partition(s) are not valid/bootable:\n";
	foreach my $invalid  (@invalid_pars) {
	    print "\t\t$invalid\n";
	}
	return 0;
    } 
    return 1;
}
## END checkValidPars

##==================================uberBoot=================================##
# PURPOSE: 	Boots all (bootable|selected) partitions.
# PRE: 		None.
# POST: 	All partitions left at EFI.
##=====================================|=====================================##
sub uberBoot {
    my ($host, $user, $pass, $port, $select_boot) = @_;
    my $timeout = undef;
	my $num_pars;
	my @spawn_ids;
	my @booting_pars;
	
    my $spawn_id = &oaCliLogin($host, $user, $pass, $port);
    my $pars_list = &listPars($host, $user, $pass, $port);
    my @bootable_pars = &findBootablePars($spawn_id, $pars_list);

    # If specific partitions are selected  
    if (defined($select_boot)) {
        
	# Separates selected partitions -- by comma, space or both -- into an array
 	## Only separates by comma!! Needs further investigation
        @selected_pars = split(/[,\s]+/, $select_boot);
        
        exit if !&checkValidPars(\@selected_pars, \@bootable_pars);
	
	    &poweronPars($spawn_id, @selected_pars);

	    @spawn_ids = &spawnidsAtEFI($host, $user, $pass, $port, @selected_pars);

	    $num_pars = @selected_pars;
	    @booting_pars = @selected_pars;
		
	# If partitions are not specified	
	} else {
	    my @nPars = &findnPars($pars_list);

	    &poweronPars($spawn_id, @nPars);

	    @spawn_ids = &spawnidsAtEFI($host, $user, $pass, $port, @bootable_pars);

	    $num_pars = @bootable_pars;
	    @booting_pars = @bootable_pars;
	}

    # Print booting partitions	
    print "\n\n\t\tConnected to $host\n";
    print "\t\tWatching [$num_pars] partition(s):\n";
    print "\t\t$_\n" foreach (@booting_pars);

    # Expects on all connections to booting partitions (@spawn_ids).
    # Sends 's' to boot to shell, commandeers terminal if any other connection
    # attempts to take control.
    while ($num_pars > 0) {
		expect($timeout,
		    '-i', [@spawn_ids], 
		    	    [qr/spy mode|Not owner/i,
				sub {
				    my ($spawn_id) = @_;
				    &commandeerTerminalCore($spawn_id);
				    exp_continue;
				}],
		            [qr/provided \*\*\*/i,
				sub {
				    my ($spawn_id) = @_;
				    # Try 1 second pause, then send instead
				    #$spawn_id->send_slow(1, "s");
				    $spawn_id->send("s");
				    exp_continue;
				}],
		            [qr/ell>/i,
				sub {
				    $num_pars--;
				    print "\n\t\t\033\[31m###############                         ###############\033\[0m\n";
				    print "\t\t\033\[31m############### Partitions remaining: $num_pars ###############\033\[0m\n";
				    print "\t\t\033\[31m###############                         ###############\033\[0m\n";
				}]
		    );
    }

    foreach my $spawn_id (@spawn_ids) {
        $spawn_id->send("xchar off\r");
        $spawn_id->expect($timeout, [qr/ell>/i]);
    }

    print "\n\t\tALL PARTITIONS FOR $host HAVE BOOTED!\n\n";
}
## END uberBoot

1;
