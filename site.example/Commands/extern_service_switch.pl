#!/usr/bin/perl
# @(#) Switch a service to a target host
# @(#) IMPORTANT: this script is to be run from an external (Linux) monitoring host.
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --service=<name>        the name of the service [${name}]
# @(-) --to=<name>             the name of the target machine [${to}]
# @(-) --[no]live              set the target host to 'live' status [${live}]
# @(-) --[no]backup            set the target host to 'backup' status [${backup}]
# @(-) --[no]force             check the initial conditions, but run even an error is detected [${force}]
#
# @(@) While it is OF THE FIRST IMPORTANCE that backup daemons do not run on a live production machine,
# @(@) we nonetheless may have several live production machines, or several backup production machines, or no live at all, or no backup at all.
# @(@) Obviously, all that stuff will work a bit less than optimal, but there will not be any loss of data.
# @(@) So fine from this script point of view.
#
# Copyright (©) 2023-2025 PWI Consulting for Inlingua
#
# This script is mostly written like a TTP verb but is not. This is an example of how to take advantage of TTP to write your own (rather pretty and efficient) code.
# Just to make it sure and obvious: this makes use of TTP, but is not part itself of TTP (though a not so bad example of application).

use utf8;
use strict;
use warnings;

use Data::Dumper;
use File::Basename;
use File::Spec;
use Getopt::Long;

use TTP;
use vars::global qw( $ep );

use TTP::Constants qw( :all );
use TTP::Message qw( :all );

# TTP initialization
my $extern = TTP::Extern->new();

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	service => '',
	to => '',
	live => 'no',
	backup => 'no',
	force => 'no'
};

my $opt_service = $defaults->{service};
my $opt_to = $defaults->{to};
my $opt_live = false;
my $opt_backup = false;
my $opt_force = false;

# -------------------------------------------------------------------------------------------------
# actually switching to 'live' or to 'backup' status only requires executing configured commands
sub doSwitch {
	msgOut( "switching '$opt_service' service to '$opt_to' machine for '".( $opt_live ? 'live' : 'backup' )."' prodution state..." );

	# get and execute the commands for this target state
	my $tokey = $opt_live ? 'to_live' : 'to_backup';
	my $dummy = $extern->dummy() ? "-dummy" : "-nodummy";
	my $verbose = $extern->verbose() ? "-verbose" : "-noverbose";
	my $command = "ssh inlingua-user\@$opt_to services.pl vars -service $opt_service -key switch,$tokey,commands -nocolored $dummy $verbose";
	my $stdout = TTP::filter( $command );
	my $count = 0;
	my $cOk = 0;
	foreach my $line ( @{$stdout} ){
		$line =~ s/^\s*//;
		my @words = split( /\s+/, $line, 2 );
		$command = $words[1];
		# have to re-double the backlashes to survive to ssh shell
		$command =~ s/\\/\\\\/g;
		msgOut( "executing $command" );
		my $res = TTP::commandExec( $command, {
			macros => {
				NODE => $opt_to,
				SERVICE => $opt_service
			}
		});
		$count += 1;
		$cOk += 1 if $res->{success};
	}
	
	msgOut( "$count executed command(s), $cOk/$count OK" );
}

# -------------------------------------------------------------------------------------------------
#
sub _obsoleteCode {
=pod
	# make sure the service is defined on the target host
	# [services.pl list] displaying services defined on WS12DEV1...
	#  Canal33
	#  Dom.2008
	# [services.pl list] 2 found defined service(s)
	my $command = "ssh inlingua-user\@$opt_to services.pl list -services";
	msgVerbose( $command );
	my $stdout = `$command`;
	my $rc = $?;
	my @check = grep( /$opt_service/, @lines );
	if( !scalar( @check )){
		msgErr( "service '$opt_service' is not defined on '$opt_to' host" );
	} else {
		msgOut( "service '$opt_service' exists" );
	}

		# get the list of hosts which hold the production of this service, and check that the target host is actually member of the group
		# [services.pl list] displaying machines which provide \'Canal33\' service in \'X\' environment...
		#    X: NS230134
		#    X: WS12PROD1
		# [services.pl list] 2 found machine(s)
		$command = "services.pl list -nocolored -service $opt_service -identifier X -machines";
		msgVerbose( $command );
		$stdout = `$command`;
		$rc = $?;
		msgVerbose( $stdout );
		msgVerbose( "rc=$rc" );
		@lines = grep( !/^\[|\(ERR|\(WAR|\(VER|\(DUM|^$/, split( /[\r\n]/, $stdout ));
		my @hosts = ();
		foreach my $it ( @lines ){
			my @words = split( /\s+/, $it );
			push( @hosts, $words[2] );
			msgVerbose( "got $words[2]" );
		}
		@check = grep( /$opt_to/, @hosts );
		if( !scalar( @check )){
			msgErr( "to='$opt_to' is not a valid target among [".join( ', ', @hosts )."] production hosts" );
		} else {
			msgOut( "host '$opt_to' is a valid target" );
		}

		# VERY IMPORTANT
		# first task is to stop the backup daemons on the target host
		msgOut( "stopping backup daemons..." );
		$command = "ssh inlingua-user\@$opt_to services.pl commands -service $opt_service -key monitor,switch";
		msgVerbose( $command );
		$stdout = `$command`;
		$rc = $?;
		msgVerbose( $stdout );
		msgVerbose( "rc=$rc" );

		# second is to disable the backup scheduled tasks on the target host
		msgOut( "disabling backup scheduled tasks..." );
		$command = "ssh inlingua-adm\@$opt_to services.pl commands -service $opt_service -key monitor,admin";
		msgVerbose( $command );
		$stdout = `$command`;
		$rc = $?;
		msgVerbose( $stdout );
		msgVerbose( "rc=$rc" );

		# and last switch the ip service itself
		# get the ip service
		msgOut( "switching the IP service..." );
		$command = "ssh inlingua-user\@$opt_to services.pl vars -service $opt_service -key monitor,ovh,ip";
		msgVerbose( $command );
		$stdout = `$command`;
		$rc = $?;
		msgVerbose( $stdout );
		msgVerbose( "rc=$rc" );
		@lines = grep( !/^\[|\(WAR\)|^$/, split( /[\r\n]/, $stdout ));
		my $ipService = undef;
		if( scalar( @lines )){
			my @words = split( /\s+/, $lines[0] );
			$ipService = $words[2];
		}
		msgVerbose( "got ipService='$ipService'" );
		if( !$ipService ){
			msgWarn( "No IP service found for '$opt_service' service" );

		} else {
			# get the target host service
			$command = "ssh inlingua-user\@$opt_to ttp.pl vars -key Environment,physical,ovh";
			msgVerbose( $command );
			$stdout = `$command`;
			$rc = $?;
			msgVerbose( $stdout );
			msgVerbose( "rc=$rc" );
			@lines = grep( !/^\[|\(ERR|\(WAR|\(VER|\(DUM|^$/, split( /[\r\n]/, $stdout ));
			my $physical = undef;
			if( scalar( @lines )){
				my @words = split( /\s+/, $lines[0] );
				$physical = $words[2];
			}
			msgVerbose( "got physical='$physical'" );
			if( !$physical ){
				msgErr( "An OVH IP Failover is defined but no OVH server service has been found for '$opt_service' service" );
			} else {
				# get the url to be tested
				$command = "ssh inlingua-user\@$opt_to services.pl vars -service $opt_service -key monitor,url";
				msgVerbose( $command );
				$stdout = `$command`;
				$rc = $?;
				msgVerbose( $stdout );
				msgVerbose( "rc=$rc" );
				@lines = grep( !/^\[|\(ERR|\(WAR|\(VER|\(DUM|^$/, split( /[\r\n]/, $stdout ));
				my $url = undef;
				if( scalar( @lines )){
					my @words = split( /\s+/, $lines[0] );
					$url = $words[2];
				}
				msgVerbose( "got url='$url'" );
				if( !$url ){
					msgWarn( "No URL is defined for '$opt_service' service" );
				}
				# running the switch requires ip service and target host, url is optional
				my $urlopt = $url ? "-url $url -sender $opt_to" : "";
				$urlopt = $url ? "-url $url -sender WS22DEV1" : "";
				$command = "ovh.pl ipswitch -ip $ipService -to $physical -wait $urlopt";
				msgVerbose( $command );
				$stdout = `$command`;
				$rc = $?;
				msgVerbose( $stdout );
				msgVerbose( "rc=$rc" );
			}
		}
=cut
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> sub { $ep->runner()->help( @_ ); },
	"colored!"			=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"			=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"			=> sub { $ep->runner()->verbose( @_ ); },
	"service=s"			=> \$opt_service,
	"to=s"				=> \$opt_to,
	"live!"				=> \$opt_live,
	"backup!"			=> \$opt_backup,
	"force!"			=> \$opt_force )){

		msgOut( "try '".$extern->command()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $extern->help()){
	$extern->helpExtern( $defaults );
	TTP::exit();
}

msgVerbose( "found colored='".( $extern->colored() ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $extern->dummy() ? 'true':'false' )."'" );
msgVerbose( "found verbose='".( $extern->verbose() ? 'true':'false' )."'" );
msgVerbose( "found service='$opt_service'" );
msgVerbose( "found to='$opt_to'" );
msgVerbose( "found live='".( $opt_live ? 'true':'false' )."'" );
msgVerbose( "found backup='".( $opt_backup ? 'true':'false' )."'" );
msgVerbose( "found force='".( $opt_force ? 'true':'false' )."'" );

msgErr( "'--service' service name is mandatory, but has not been found" ) if !$opt_service;
msgErr( "'--to' target host is mandatory, but has not been found" ) if !$opt_to;

# --live' and '--backup' options are mutually exclusive
if( $opt_live && $opt_backup ){
	msgErr( "'--live' and '--backup' options are mutually exclusive" );
}
if( !$opt_live && !$opt_backup ){
	msgWarn( "neither '--live' nor '--backup' options are specified, will not do anything" );
}

if( !TTP::errs()){
	doSwitch() if $opt_live or $opt_backup;
}

TTP::exit();
