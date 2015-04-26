#!/usr/bin/perl
#------------------------------------------------------------------------------
#
#  Author: Austin H. Bernard        austin.bernard@hp.com
#  Date Created: 06/20/2013
#  Last Modified: 12/09/2013  AHB
#
# Description: Creates zones for ESTL Dragonhawk pod infrastructure.
# Discovers WWNNs for QLogic 8gb/16gb mezzanine cards and Emulex FCoE BLOMs.
# 
#------------------------------------------------------------------------------

use strict;
use warnings;
use Expect;
use Switch;
use Getopt::Std;
use Getopt::Long;

require "includes/bootLib.pl";

##=============================BEGIN SUBROUTINES=============================##

##=================================printCmdMenu==============================##
# PURPOSE:	Prints the command option menu.      
# PRE:          None
# POST:         None
##=====================================|=====================================##
sub printCmdMenu {
    print "Options:\n";
    print "\t-sh: Hostname for the SAN switch (Mandatory)\n";
    print "\t-su: Username for the SAN switch (Default: admin)\n";
    print "\t-sp: Password for the SAN switch\n";
    print "\t-h: Hostname for Dragonhawk system (Mandatory)\n";
    print "\t-u: Username for Dragonhawk system (Default: Administrator)\n";
    print "\t-p: Password for Dragonhawk system\n";
    print "\t-P: ssh port (Default: 22)\n";
    print "\t-c: Storage Configuration file\n";
    print "\t-i: Specify a specific I/O port to add (ex. f1p1)\n";
    print "\t-s: Apply to only Selected blades\n";
    print "\t-n: New configuration on the SAN switch (flag)\n";
    print "\t-f: Name of the Fabric configuration you want to use\n";
    print "\t-l: Clear SAN configuration and save (flag)\n";
    print "\t-r: Remove zoning for all blades of a host, or specific blades (used with '-s')(flag)\n";
    print "\t-e: Save configuration without Enabling the configuration. Default is to save and enable (flag)\n";
}
## END printCmdMenu

##==================================isBlank==================================##
# PURPOSE:	Checks if array values are blank/empty.
# PRE:          None
# POST:         Returns 0 if no values are blank
##=====================================|=====================================##
sub isBlank {
    my @cmd_vars = @_;
    my @blank_vars;

    foreach my $var (@cmd_vars) {
	push (@blank_vars, $var) if ($var eq "");
    }

    if (@blank_vars) {
	print "\nError: Missing required parameter.\n";
	return 1;
    }

    return 0;
} 
## END printErrorMenu

##================================sanswCliLogin==============================##
# PURPOSE:      Login to cli on a Brocade SAN Switch
# PRE:          None
# POST:         An open SSH connection is left. The spawn_id is returned
##=====================================|=====================================##
sub sanswCliLogin {
    my ($host, $user, $pass, $port) = @_;
    my $timeout = 30; 
    my $spawn_id = new Expect ('ssh', $host, "-l", $user, "-p", $port)
        or die "Cannot spawn ssh: $1\n";
    
    $spawn_id->expect
    ($timeout, 
	[qr/word/i,
	    sub { 
		$spawn_id->send("$pass\r");
                $spawn_id->expect ($timeout, [qr/>/]);
	    }],
	[timeout =>
	    sub {
		die "Timeout occurred. No login.\n";
	    }]
    );
    $spawn_id;
}
## END sanswCliLogin

##==============================getCommandOutput=============================##
# PURPOSE:      Runs a command on the OA and returns the output. 
# PRE:          Connection to a host. 
# POST:         Output of the executed command. 
##=====================================|=====================================##
sub getCommandOutput {
    my ($spawn_id, $command, $prompt) = @_; 
    my $timeout = 30; 
    my $command_output= ""; 
    
    $spawn_id->send("$command\r");
    $spawn_id->expect($timeout, [qr/$prompt/i]);

    $command_output = $spawn_id->before();
}
## END getCommandOutput

##==============================getCommandOutput=============================##
# PURPOSE:      Runs a command on the OA and returns the output. 
# PRE:          Connection to a host. 
# POST:         Returns an array of the output of the executed command. 
##=====================================|=====================================##
sub getCommandOutputArray {
    my ($spawn_id, $command, $prompt) = @_; 
    return ( split (/\r\n/, &getCommandOutput ($spawn_id, $command, $prompt) ) );
}
## END getCommandOutput

##================================getBLOMWWNNs===============================##
# PURPOSE:      Find the WWNN of FCoE HBA LOM1:1-b, 1:2-b, and LOM2:1-b, 2:2-b
#		for a single blade. 
# PRE:          Connection to a host. 
# POST:		Hash of WWNNs for each FCoE BLOM. 
##=====================================|=====================================##
sub getBLOMWWNNs {
    my ($spawn_id, $blade_num) = @_;
    my $lom_port;
    my %lom_WWNNs;

    my $show_blade_info_output = &getCommandOutput($spawn_id, "show blade info $blade_num", ">");

    # Find WWNNs for FCoE BLOMs (Edinburg)
    for ($a = 1; $a <= 2; $a++) {
	for ($b = 1; $b <= 2; $b++) {
	    $lom_port = "f$a" . "p$b";
	    if ($show_blade_info_output =~ /FCoE HBA LOM$a:$b-b[\s]+([\w:]+)/) {
		$lom_WWNNs{"$lom_port"} = $1;	
	    }
	}
    }
    return %lom_WWNNs;
}
## END getBLOMWWNNs

##================================getMezzWWNNs===============================##
# PURPOSE:      Find the WWNN of Mezz cards for a single blade. 
# PRE:          Connection to a host. 
# POST:		Hash of WWNNs for each Mezz card. 
##=====================================|=====================================##
sub getMezzWWNNs {
    my ($spawn_id, $blade_num) = @_;
    my $mezz_port;
    my $mezz_slot;
    my %mezz_WWNNs;
    my $index = 1;
    my @show_blade_info_output = &getCommandOutputArray($spawn_id, "show blade info $blade_num", ">");

    foreach my $line (@show_blade_info_output) {
        # Might have to add 'Emulex' for future Mezz cards
        if ( $line =~ /Mezzanine ([\d]+)/) {
	    $mezz_slot = $1;
	}
	    
        if ( $line =~ /Mezzanine ([\d]+):[\s]+([\w\s]+)/ 
            && ($2 =~ /QMH2572/
            ||  $2 =~ /QMH2672/	) ) {
# Example   ||  $2 =~ /Emulex/	) {

	    for (my $i = 1; $i <= 2; $i++) {
		# Checks next two lines after finding 'Mezzanine' for WWNNs
		if ($show_blade_info_output[$index++] =~ /Port $i:[\s]+([\w:]+)/) {
		    $mezz_port = "m$mezz_slot" . "p$i";
		    $mezz_WWNNs{"$mezz_port"} = $1;	
		}
	    }
	}
	$index++;
    }
    return %mezz_WWNNs;
}
## END getMezzWWNNs

##==================================getBlades================================##
# PURPOSE:	Find which blades are in the system. 
# PRE:          Connection to a host. 
# POST:		Blades in the system.	
##=====================================|=====================================##
sub getBlades {
    my ($spawn_id) = @_;
    my @blades;
    my @output = &getCommandOutputArray($spawn_id, "parstatus -C -M", ">");

    # hawk010oa1> parstatus -C -M
    # blade:  1/1       :CB920s x1     :Active Base /I         :20/0/0/20  :64.0/0.0/0.0     :yes :1  :no
    # blade:  1/2       :CB920s x1     :Active Base /I         :20/0/0/20  :64.0/0.0/0.0     :yes :1  :no
    # blade:  1/3       :-             :Empty /Invalid         :-          :-                :-   :-  :-
    # blade:  1/4       :-             :Empty /Invalid         :-          :-                :-   :-  :-
    # [...]

    foreach my $line (@output) {
	my @f = split( /:/, $line );

	if ( defined ($f[3]) && $f[3] !~ /Empty/ ) {
	    if ( $f[1] =~ /[\d]+\/([\d]+)/ ) {
		push (@blades, $1);
	    }
	}
    }
    return @blades;
}
## END getBlades

##=================================sendZoneCmd===============================##
# PURPOSE:	Send a command to a Brocade SAN switch.	
# PRE:          Connection to host.
# POST:		None.
##=====================================|=====================================##
sub sendZoneCmd {
    my ($sansw_sid, $cmd) = @_;
    my $timeout = 30;

    $sansw_sid->send("$cmd\r");
    $sansw_sid->expect ($timeout, [qr/>/]);
}
## END sendZoneCmd

##===============================findBladeZones==============================##
# PURPOSE:	Find the existing zones on a SAN switch for a specific blade.	
# PRE:          Output from a current zoneshow on the SAN switch. 
# POST:		List of existing zones in an array.
##=====================================|=====================================##
sub findBladeZones {
    my ($hostname, $blade_num, @zoneshow_output) = @_;
    my @zones;

    foreach my $line (@zoneshow_output) {
	if ($line =~ /zone:[\s]+($hostname[b]$blade_num[\w]+)/) {
	    push(@zones, $1) unless ($1 ~~ @zones);
	}	
    }
    return @zones;
}
## END findBladeZones

##=================================removeZone================================##
# PURPOSE:	Delete a zone and remove it from the configuration.
# PRE:          A connection to the SAN switch.
# POST:		None.
##=====================================|=====================================##
sub removeZone {
    my ($sansw_sid, $cfg_name, $zone) = @_;

    &sendZoneCmd($sansw_sid, "zonedelete \"$zone\"");
    &sendZoneCmd($sansw_sid, "cfgremove \"$cfg_name\", \"$zone\"");
}	
## END removeZone

##=============================createZoneAddToCfg============================##
# PURPOSE:	Create zones for a blade and adds each zone to the zone
#		configuration.
# PRE:		A connection to the SAN switch.
# POST:		None.
##=====================================|=====================================##
sub createZoneAddToCfg {
    my ($sansw_sid, $zone_name, $wwnn, $stg_alias, $cfg_name) = @_;

    &sendZoneCmd($sansw_sid, "zonecreate \"$zone_name\", \"$wwnn" . "; $stg_alias\"");
    &sendZoneCmd($sansw_sid, "cfgadd \"$cfg_name\", \"$zone_name\"");
}


##=================================isStgAlias================================##
# PURPOSE:	Checks if a given storage alias already exists apart of a
#		zoning configuration.	
# PRE:          A connection to the SAN switch. Output of current 
#		zoning configuration.
# POST:		A '1' value or nothing.	
##=====================================|=====================================##
sub isStgAlias {
    my ($sansw_sid, $stg_alias, @zoneshow_output) = @_;

    foreach my $line (@zoneshow_output) {
	if ($line =~ /alias:[\s]+($stg_alias)/) {
	    return 1;
	}
    }
}
## END isStgAlias

##================================sendCfgCommand=============================##
# PURPOSE:	Send cfg(save|clear|disable|enable) to a Brocade SAN switch	
# PRE:          A connection to the SAN switch.
# POST:		None.
##=====================================|=====================================##
sub sendCfgCommand {
    my ($sansw_sid, $cmd, $cfg_name) = @_;
    my $timeout = 30;

    if ( !defined ($cfg_name) && $cmd eq "ENABLE") {
	print "\nError: Configuration name not defined. This is a user-created error in sendCfgCommand().\n";
	exit;
    } 
	
    switch ($cmd) {
	case "SAVE"	{ $sansw_sid->send("cfgsave\r")	    }
	case "CLEAR"	{ $sansw_sid->send("cfgclear\r")    }
	case "DISABLE"	{ $sansw_sid->send("cfgdisable\r")  }
	case "ENABLE"	{ $sansw_sid->send("cfgenable \"$cfg_name\"\r") }
    }

    $sansw_sid->expect
    ($timeout,
	[qr/(yes, y, no, n)/,
	    sub { 
		$sansw_sid->send("y\r"); 
		exp_continue;
	    }
	],
	[qr/>/]
    );
}
## END sendCfgCommand

##==================================clearCfg=================================##
# PURPOSE:	Run commands in order to clear Brocade SAN switch config and
#		save the config.	
# PRE:          A connection to the SAN switch.
# POST:		None.
##=====================================|=====================================##
sub clearCfg {
    my ($sansw_sid) = @_;

    &sendCfgCommand($sansw_sid, "DISABLE");
    &sendCfgCommand($sansw_sid, "CLEAR");
    &sendCfgCommand($sansw_sid, "SAVE");
}
## END clearCFG

##===================================saveCfg==================================##
# PURPOSE:	Run commands in order to save Brocade SAN switch config.
# PRE:          A connection to the SAN switch.
# POST:		None.
##=====================================|=====================================##
sub saveCfg {
    my ($sansw_sid, $cfg_name, $save_config_flag) = @_;

    &sendCfgCommand($sansw_sid, "DISABLE") unless ($save_config_flag);
    &sendCfgCommand($sansw_sid, "SAVE");
    &sendCfgCommand($sansw_sid, "ENABLE", $cfg_name) unless ($save_config_flag);
}
## END saveCFG

##==================================aliCreate================================##
# PURPOSE:	Creates an alias for a storage device in a specific pod
#		containing the WWNN of the storage device's port(s).	
# PRE:          A connection to the SAN switch. Storage device's WWNNs.
# POST:		None.	
##=====================================|=====================================##
sub aliCreate {
    my ($sansw_sid, $stg_alias, @stg_wwnns) = @_;
    my $timeout = 30;

    $sansw_sid->send ("alicreate \"$stg_alias\", \"");

    foreach my $i (0..$#stg_wwnns) {
	if ($i != $#stg_wwnns) {
	    $sansw_sid->send ("$stg_wwnns[$i]" . "; ");
	} else {
	    $sansw_sid->send ("$stg_wwnns[$i]\"");
	}
    }
    $sansw_sid->send ("\r"); 
    $sansw_sid->expect ($timeout, [qr/>/]);
}
## END aliCreate

##==============================END SUBROUTINES==============================## 

# ----------------------
# Variable declarations
# ----------------------
my %blom_wwnns;
my %mezz_wwnns;

# For ESTL systems
my %pod_systems;
$pod_systems{"pod01"} = [qw/ hawk006 hawk007 hawk008 hawk009 hawk010 /];
$pod_systems{"pod02"} = [qw/ hawk011 hawk012 hawk013 hawk014 hawk015 /];
$pod_systems{"pod04"} = [qw/ hawk021 hawk022 hawk023 hawk024 hawk025 
			     hawk026 hawk027 hawk028 hawk029 hawk030 /];
$pod_systems{"pod06"} = [qw/ hawk001 hawk002 hawk003 hawk004 hawk005 
			     hawk031 hawk032 hawk033 hawk034 hawk035 /];
$pod_systems{"pod08"} = [qw/ hawk036 hawk037 hawk038 hawk039 hawk040 /];

my @zones;
my @blades;
my @stg_wwnns;  
my @zone_cfgs;
my @invalid_blades;
my @selected_blades;
my @zoneshow_output;

my $oa_sid;
my $sansw_sid;
my $hostname;
my $zone_name;
my $pod_cfg;
my $stg_alias;
my $STG_CFG_PATH	= "stg_cfgs/";

# Command line variable declarations
my $host	= ""; 
my $user	= "Administrator";
my $pass	= ""; 
my $port	= 22; 
my $san_host	= "";
my $san_user	= "admin";
my $san_pass	= "";
my $stg_cfg_file = "";
my $cfg_name;
my $select_blade;
my $remove_blades_flag;
my $io_port;
my $new_config_flag;
my $clear_config_flag;
my $save_config_flag;

GetOptions( 
    'h=s'  => \$host, 
    'u=s'  => \$user,
    'p=s'  => \$pass,
    'P=s'  => \$port,
    'sh=s' => \$san_host,
    'su=s' => \$san_user,
    'sp=s' => \$san_pass,
    's=s'  => \$select_blade,
    'i=s'  => \$io_port,
    'c=s'  => \$stg_cfg_file,
    'f=s'  => \$cfg_name,
    'e'	   => \$save_config_flag,
    'r'    => \$remove_blades_flag,
    'l'    => \$clear_config_flag,
    'n'	   => \$new_config_flag
);

# ---------------------------------------
# Command-line option conflict handling
# ---------------------------------------
## TODO: '-i' flag should require '-s' flag.
##

if ( &isBlank($port, $san_host, $san_user, $san_pass) ) {
    print "SAN host, SAN user, SAN password or Port missing\n";
    &printCmdMenu;
    exit;
} elsif ($clear_config_flag and ($io_port or $remove_blades_flag or $new_config_flag or $stg_cfg_file) ) {
    print "Superfulous option. Clear configuration (-l) cannot be used in this way.\n";
    &printCmdMenu;
    exit;
} elsif ($io_port or $new_config_flag) {
    if ( &isBlank($host, $user, $pass, $stg_cfg_file) ) { 
        print "Host, User, Password or Storage config file missing.\n";
	&printCmdMenu;
        exit;
    }   
    if ($remove_blades_flag) {
        print "Remove blades (-r) cannot be used with ";
        print "io port (-i) option.\n" if ($io_port);
        print "new configuration (-n) option.\n" if ($new_config_flag);
	&printCmdMenu;
        exit;
    }   
} elsif ($remove_blades_flag) {
    if ( &isBlank($host) ) { 
        print "Host is missing.\n";
	&printCmdMenu;
        exit;
    }   
    $stg_cfg_file = "" if ($stg_cfg_file);
} else {
    if ( !$clear_config_flag and &isBlank($host, $user, $pass, $stg_cfg_file) ) {
        print "Host, User, Password or Storage config file missing.\n";
	&printCmdMenu;
	exit;
    }
}

if (-e $STG_CFG_PATH . $stg_cfg_file) {
    if ($stg_cfg_file =~ /(^[\w_]+)/) {
	$stg_alias = $1;
    }
} else {
    print "$stg_cfg_file does not exist within $STG_CFG_PATH\n";
    exit;
}
# ---------------------------------------

# Making spawn-id connections to the OA and SAN switch
unless ($remove_blades_flag or $clear_config_flag) {
    $oa_sid = &oaCliLogin($host, $user, $pass, $port) || die "$!\n";
    exit if $!;
}

$sansw_sid = &sanswCliLogin($san_host, $san_user, $san_pass, $port) || die "$!\n";
exit if $!;

# Find $host in %pod_systems for ESTL systems. 
foreach my $pod (keys %pod_systems) {
    if ($host ~~ @{$pod_systems{$pod}}) {
	$pod_cfg = $pod . "_fabric";
    }
}

# Set zoning configuration name for non-ESTL systems
if (!$pod_cfg) {
    @zoneshow_output = &getCommandOutputArray($sansw_sid, "zoneshow", ">");

    # Find all configurations currently available on SAN switch
    foreach my $line (@zoneshow_output) {
	if ($line =~ /cfg:[\s]+([\w]+)/) {
	    push (@zone_cfgs, $1) unless ($1 ~~ @zone_cfgs);
	}
    }

    # Check if cfg_name given with -f is a config on the switch
    # If no cfg_name is given with -f and there are more than 1 available
    # configs, exit with error. Otherwise, set cfg_name to effective cfg.
    if ($cfg_name and !$new_config_flag) {
	if ( !($cfg_name ~~ @zone_cfgs) ) {
	    print "\nError: Given fabric ($cfg_name) and switch fabric(s) [@zone_cfgs] do not match.\n";
	    print "'-f' is only required on initial configuration. Terminating script.\n";
	    #exit;
	} elsif (scalar @zone_cfgs > 1) {
	    print "\nError: Multiple configurations found on switch.\n";
	    print "Use '-f' option to specify a configuration.\n";
	    exit;
	} else {
	    #TODO: Find effective configuration
	    # Use first cfg name in @zone_cfgs for now
	    $cfg_name = $zone_cfgs[0];
	}
    }
} else {
    $cfg_name = $pod_cfg;
}

if (!$cfg_name and !$clear_config_flag) {
    print "\nError: Unable to determine fabric zoning configuration name. The '-f' option\n";
    print "is required on initial configuration.\n";
    exit;
}

# Assign WWNNs in *.cfg file to array
open (LIST1, $STG_CFG_PATH . $stg_cfg_file) || die "File not found\n";
    while (<LIST1>) {
	push( @stg_wwnns, split (/\n/, $_) );
    }
close (LIST1);

# Set hostname for the zone naming convention:
# Ex. hawk021 = h021, icarumba = icar
if ( $host =~ /([\d]+)/ ) {
    $hostname = "h$1";
} else {
    $hostname = substr($host, 0, 4);
}

# Warn and prompt before continuing to clear zoning configuration 
if ($new_config_flag || $clear_config_flag) {
    my $continue = 0;
    print "\n\n***WARNING***WARNING***WARNING***WARNING***WARNING***WARNING***\n";
    print "You are about to clear the zoning configuration for $san_host.\n";
    print "Are you sure you want to proceed? (y, yes/n, no): ";

    until ($continue) {
	chomp (my $input = <STDIN>);
	switch ($input) {
	    case qr/^y$|^yes$/i { $continue = 1; }
	    case qr/^n$|^no$/i  { print "\nScript terminated.\n"; exit; }
	    else		{ print "Invalid input. Please choose (y/yes, n/no): "; }
	}
    }

    # Clear SAN switch configuration
    &clearCfg($sansw_sid);

    exit if ($clear_config_flag); 

    # Creates a blank zone and then creates the Config by adding the 
    # "blank" zone.
    &sendZoneCmd($sansw_sid, "zonecreate \"blank\", \"00:00:00:00:00:00:00:00\"");
    &sendZoneCmd($sansw_sid, "cfgcreate \"$cfg_name\", \"blank\"");
}

# Output of the current zoning configuration; 
# used in checks throughout script.
@zoneshow_output = &getCommandOutputArray($sansw_sid, "zoneshow", ">");

if (!$new_config_flag) {
    foreach my $line (@zoneshow_output) {
	if ($line =~ /no configuration defined/) {
	    print "\nError: No configuration defined for the SAN switch.\n";
	    print "\"-n\" flag is required for initial configuration.\n";
	    exit;
	}
    }
}

if ($remove_blades_flag) {
    # Remove each zone from selected blades
    if ($select_blade) {
	@selected_blades = split(/[,\s]+/, $select_blade);

	foreach my $blade (@selected_blades) {
	    @zones = &findBladeZones($hostname, $blade, @zoneshow_output);
    
	    foreach my $zone (@zones) {
		&removeZone($sansw_sid, $cfg_name, $zone);
	    }
	}
    # Remove each zone from all blades in $host
    } else {
	foreach my $line (@zoneshow_output) {
	    if ($line =~ /zone:[\s]+($hostname[b][\w]+)/) {
		&removeZone($sansw_sid, $cfg_name, $1);
	    }
	}
    }
    
    &saveCfg($sansw_sid, $cfg_name, $save_config_flag);
    exit;
} 

# List of the blades in the system
@blades = &getBlades($oa_sid);

# Setting selected blades
if ($select_blade) {
    @selected_blades = split(/[,\s]+/, $select_blade);

    foreach my $blade (@selected_blades) {
	if (!($blade ~~ @blades)) {
	    push (@invalid_blades, $blade);
	}   
    }

    if (@invalid_blades) {
	print "\n\n\t\tError: The following blade(s) are not in the system:\n";
	print "\t\t$_\n" foreach (@invalid_blades);
	exit;
    }
    @blades = @selected_blades;
}

## NOTE: These two lines area the same thing as the following one line
## Both examples assign a hash reference to a scalar value, i.e.,
## a value to a hash key.
##
## %test = &getBLOMWWNNs($oa_sid, $blade_num); 
## $mezz_wwnns{"test"} = \%test;
##
## $mezz_wwnns{"$blade_num"} = {&getBLOMWWNNs($oa_sid, $blade_num)};
##

# Collecting mezz WWNNs
# Creates references to: %mezz_WWNNs = ($mezz_port => $WWNN)
foreach my $blade (@blades) {
    $mezz_wwnns{"$blade"} = {&getMezzWWNNs($oa_sid, $blade)};
}

# Collecting BLOM WWNNs
# Creates references to: %lom_WWNNs = ($lom_port => $WWNN)
foreach my $blade (@blades) {
    $blom_wwnns{"$blade"} = {&getBLOMWWNNs($oa_sid, $blade)};
}

if ($io_port) {
    foreach my $blade (@blades) {
	@zones = &findBladeZones($hostname, $blade, @zoneshow_output);

	$zone_name = $hostname . "b$blade" . "$io_port"; 
	&removeZone($sansw_sid, $cfg_name, $zone_name) if ($zone_name ~~ @zones);

	if ( exists $blom_wwnns{$blade}{$io_port} ) {
	    &sendZoneCmd($sansw_sid, "zonecreate \"$zone_name\", \"$blom_wwnns{$blade}{$io_port}" . "; $stg_alias\"");
	    &sendZoneCmd($sansw_sid, "cfgadd \"$cfg_name\", \"$zone_name\"");
	} elsif ( exists $mezz_wwnns{$blade}{$io_port} ) {
	    &sendZoneCmd($sansw_sid, "zonecreate \"$zone_name\", \"$mezz_wwnns{$blade}{$io_port}" . "; $stg_alias\"");
	    &sendZoneCmd($sansw_sid, "cfgadd \"$cfg_name\", \"$zone_name\"");
	} else {
	    print "\nPort $io_port not found for blade $blade. No changes made.\n";
	}
    }

    &saveCfg($sansw_sid, $cfg_name, $save_config_flag);

    exit;
}

# Creates an alias for the given storage confiuration file if 
# one does not already exist
&aliCreate($sansw_sid, $stg_alias, @stg_wwnns) if (!&isStgAlias($sansw_sid, $stg_alias, @zoneshow_output)); 

## NOTE: Extracting hash-in-hash data #####################################
## The 'key' would be the blade number
## The 'value' would be the reference to the hash 
## generated by &getBLOMWWNNs: %{$blom_wwnns{$blade}} 
##
##	while ( my ($blom_port, $blom_wwnn) = each %{$blom_wwnns{$blade}} ) {
##	    is the same as:
##	%lom_wwnns = %{$blom_wwnns{$blade}}
##	while ( my ($blom_port, $blom_wwnn) = each %lom_wwnns ) {
###########################################################################

# Meat and potatoes right here.
foreach my $blade (@blades) {
    # Find zones already created for the host and blade
    # and remove them.
    @zones = &findBladeZones($hostname, $blade, @zoneshow_output);
    foreach my $zone (@zones) {
	&removeZone($sansw_sid, $cfg_name, $zone);    
    }

    # There is an unlikely case where removing all zones from a config
    # renders the config empty and therefore non-existent. This line
    # (re)creates the config and simply moves on if it already exists.
    &sendZoneCmd($sansw_sid, "cfgcreate \"$cfg_name\", \"blank\"");

    # Creating the zones and adding them to the zoning conifguration
    # for all blom and mezz WWNNs.
    while ( my ($blom_port, $blom_wwnn) = each %{$blom_wwnns{$blade}} ) { 
        $zone_name = $hostname . "b$blade" . "$blom_port"; 
	&createZoneAddToCfg($sansw_sid, $zone_name, $blom_wwnn, $stg_alias, $cfg_name);
    }   

    while ( my ($mezz_port, $mezz_wwnn) = each %{$mezz_wwnns{$blade}} ) {
	$zone_name = $hostname . "b$blade" . "$mezz_port"; 
	&createZoneAddToCfg($sansw_sid, $zone_name, $mezz_wwnn, $stg_alias, $cfg_name);
    }
}

# Cleanup of "blank" zone
&removeZone($sansw_sid, $cfg_name, "blank");    

&saveCfg($sansw_sid, $cfg_name, $save_config_flag);
