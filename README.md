# DHzoner

By default the script will add zones to the switch. Currently configured zones will be overridden if they match a zone that is being created.
Ex. You want to add zones for hawk900 blade 1. If there are any zones already in the zoning configuration that match this script's naming scheme, they will be removed. Once they are removed, new zones will be created for the WWNNs the script finds for each card in blade 1.

Zone configuration example. This zone is for hawk021, blade 2, mezz slot 2, port 1:

zone: h021b1m2p1	

		50:01:43:80:26:e8:d4:74		- WWNN for m2p1
		20:70:00:c0:ff:14:aa:ea		- WWNN for port on p2000
		24:70:00:c0:ff:14:aa:ea		- WWNN for port on p2000

The script also saves and enables any changes to the zoning configuration. This can be suppressed with the '-e' flag.

Options:
	
	-sh: Hostname for the SAN switch (Mandatory)
	
	-su: Username for the SAN switch (Default: admin)
	
	-sp: Password for the SAN switch
	
	-h: Hostname for Dragonhawk system (Mandatory)
		
	-u: Username for Dragonhawk system (Default: Administrator)
		
	-p: Password for the Dragonhawk system
		
	-P: ssh port (Default: 22)
	
	-c: Storage Configuration file
		The configuration file contains the WWNNs for the storage device ports. An alias will be created in
		the zoning configuration with the name of the configuration file that was given.
		The script looks for these with the 'Released' directory inside stg_cfgs/
		Example of storage configuration file:
			$ cat stg_cfgs/pod01p2k1a.cfg 
			  20:70:00:C0:FF:14:95:8C
			  24:70:00:C0:FF:14:95:8C
		
		Example in the zone configuration on the switch:
			alias:	pod01p2k1a	
					20:70:00:C0:FF:14:95:8C; 24:70:00:C0:FF:14:95:8C
		
	-i: Specify a specific I/O port to add (ex. f1p1)
		Requires '-s' flag (not implemented)
		The naming scheme for ports is as follows:
		Edinburg: f1p1 = BLOM slot 1, port 1
		Little River: m2p1 = mezz slot 2, port 1
	
	-s: Apply to only Selected blades
		If you have replaced cards in only one blade of a system you can use this option to update only
		the blade in which the cards were changed. Can also be used with '-r'.
		
	-n: New configuration on the SAN switch (flag)
		This is only to be used when initially setting up a SAN switch to be used with this script.
		It will clear the configuration and create a new zoning configuration with the name given with
		the '-f' flag.
		
	-l: Clear SAN configuration and save (flag)
		There is a prompt to continue anytime the script is about to clear the configuration.
	
	-f: Name of the Fabric configuration you want to use
		This is used with '-n' to create the name of the zone configuration. From there, the script will 
		pick up the zone configuration name. This is only required to be used with '-n' if you only have 
		one zone configuration. If you have multiple zone configurations, it is recommended this flag is 
		used to specify. The script currently uses the first one it finds, not necessarily the effective. 
			
	-r: Remove zoning for all blades of a host, or specific blades (used with '-s')(flag)
		This will remove currently configured zones for a specific dragonhawk system. This can be used
		with the '-s' flag to only remove zones from specific blades in a system.
	
	-e: Save configuration without Enabling the configuration. Default is to save and enable (flag)
		By default any changes to the zoning configuration are saved and enabled. This flag will add the 
		zones to the configuration, but will not enable.
		
Example commands:

# Used for initial configuration. 
DHzoner.pl -h hawk006 -p password -c pod01p2k1a.cfg -sh pod01sansw1 -sp password -n -e -f pod06_fabric		

# Basic command to add a system to a SAN switch without enabling
DHzoner.pl -h hawk007 -p password -c pod01p2k1a.cfg -sh pod01sansw1 -sp password -e

# Add only blades 2 and 3 to the zone configuration
DHzoner.pl -h hawk007 -p password -c pod02p2k1a.cfg -sh pod01sansw1 -sp password -s 2,3

# Remove blades 2 and 3 from the zone configuration
DHzoner.pl -h hawk007 -p password -c pod02p2k1a.cfg -sh pod01sansw1 -sp password -s 2,3 -r

# Remove hawk007 from the zone configuration
DHzoner.pl -h hawk007 -p password -sh pod01sansw1 -sp password -r

# Clear the SAN switch configuration
DHzoner.pl -sh pod01sansw1 -sp password -l
