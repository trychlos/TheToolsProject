#!perl
#!/usr/bin/perl
# @(#) Monitor the json alert files dropped in the alerts directory.
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --json=<filename>       the name of the JSON configuration file of this daemon [${json}]
# @(-) --[no]ignoreInt         ignore the (Ctrl+C) INT signal [${ignoreInt}]
#
# @(@) This script is expected to be run as a daemon, started via a 'daemon.pl start -json <filename.json>' command.
#
# Copyright (©) 2023-2025 PWI Consulting for Inlingua
#
# This script is mostly written like a TTP verb but is not. This is an example of how to take advantage of TTP
# to write your own (rather pretty and efficient) daemon.
# Just to be sure: this makes use of Toops, but is not part itself of Toops (though a not so bad example of application).
#
# JSON configuration:
#
# - monitoredDir: the directory to be monitored for alerts files, defaulting to alertsDir
# - scanInterval, the scan interval, defaulting to 10000 ms (10 sec.)

use utf8;
use strict;
use warnings;

use Data::Dumper;
use File::Find;
use Getopt::Long;
use Time::Piece;

use TTP;
use TTP::Constants qw( :all );
use TTP::Daemon;
use TTP::Message qw( :all );
use vars::global qw( $ep );

my $daemon = TTP::Daemon->init();

use constant {
	MIN_SCAN_INTERVAL => 1000,
	DEFAULT_SCAN_INTERVAL => 10000
};

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	json => '',
	ignoreInt => 'no'
};

my $opt_json = $defaults->{json};
my $opt_ignoreInt = false;

my $commands = {
	#help => \&help,
};

# scanning for new elements
my $first = true;
my @previousScan = ();
my @runningScan = ();

# -------------------------------------------------------------------------------------------------
# Returns the configured 'monitoredDir' defaulting to alertsDir

sub configMonitoredDir {
	my $config = $daemon->jsonData();
	my $dir = $config->{monitoredDir};
	$dir = TTP::alertsDir() if !$dir;
	return $dir;
}

# -------------------------------------------------------------------------------------------------
# Returns the configured 'scanInterval' (in sec.) defaulting to DEFAULT_SCAN_INTERVAL

sub configScanInterval {
	my $config = $daemon->jsonData();
	my $interval = $config->{scanInterval};
	$interval = DEFAULT_SCAN_INTERVAL if !defined $interval;
	if( $interval < MIN_SCAN_INTERVAL ){
		msgVerbose( "defined scanInterval=$interval less than minimum accepted ".MIN_SCAN_INTERVAL.", ignored" );
		$interval = DEFAULT_SCAN_INTERVAL;
	}

	return $interval;
}

# -------------------------------------------------------------------------------------------------
# new alert
# should never arrive as all alerts should also be sent through MQTT bus which is the preferred way
# of dealing with these alerts

sub doWithNew {
	my ( @newFiles ) = @_;
	foreach my $file ( @newFiles ){
		msgVerbose( "new alert '$file'" );
		my $data = TTP::jsonRead( $file );
		# and what ?
	}
}

# -------------------------------------------------------------------------------------------------
# On disconnection, try to erase the published topics

sub mqttDisconnect {
	my ( $daemon ) = @_;
	my $topic = $daemon->topic();
	my $array = [];
	push( @{$array}, {
		topic => "$topic/monitoredDir",
		payload => ''
	},{
		topic => "$topic/scanInterval",
		payload => ''
	});
	return $array;
}

# -------------------------------------------------------------------------------------------------
# Let publish some topics on MQTT-based messaging system
# The Daemon expects an array ref, so returns it even if empty
# Daemon default is to only publish 'running since...'
# we are adding here all informations as displayed by STATUS command on stdout:
#   C:\Users\inlingua-user>daemon.pl status -name tom59-backup-monitor-daemon
#   [daemon.pl status] requesting the daemon for its status...
#   7868 running since 2024-05-09 05:31:13.92239
#   7868 json: C:\INLINGUA\Site\etc\daemons\tom59-backup-monitor-daemon.json
#   7868 listeningPort: 14394
#   7868 monitoredHost: NS3232346
#   7868 monitoredExecReportsDir: \\ns3232346.ovh.net\C\INLINGUA\dailyLogs\240509\execReports
#   7868 OK
#   [daemon.pl command] success
#   [daemon.pl status] done

sub mqttMessaging {
	my ( $daemon ) = @_;
	my $topic = $daemon->topic();
	my $array = [];
	push( @{$array}, {
		topic => "$topic/monitoredDir",
		payload => configMonitoredDir()
	},{
		topic => "$topic/scanInterval",
		payload => configScanInterval()
	});
	return $array;
}

# -------------------------------------------------------------------------------------------------
# we find less files in this iteration than in the previous - maybe some files have been purged, deleted
# moved, or we have a new directory, or another reason - just reset and restart over

sub varReset {
	msgVerbose( "varReset()" );
	@previousScan = ();
}

# -------------------------------------------------------------------------------------------------
# receive here all found files in the searched directories
# According to https://perldoc.perl.org/File::Find
#   $File::Find::dir is the current directory name,
#   $_ is the current filename within that directory
#   $File::Find::name is the complete pathname to the file.

sub wanted {
	return unless /\.json$/;
	push( @runningScan, $File::Find::name );
}

# -------------------------------------------------------------------------------------------------
# do its work, i.e. detects new files in monitoredDir
# Note that the find() function sends errors to stderr when directory doesn't exist

sub works {
	@runningScan = ();
	find( \&wanted, configMonitoredDir());
	if( scalar @runningScan < scalar @previousScan ){
		varReset();
	} elsif( $first ){
		$first = false;
		@previousScan = sort @runningScan;
	} elsif( scalar @runningScan > scalar @previousScan ){
		my @sorted = sort @runningScan;
		my @tmp = @sorted;
		my @newFiles = splice( @tmp, scalar @previousScan, scalar @runningScan - scalar @previousScan );
		doWithNew( @newFiles );
		@previousScan = @sorted;
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$ep->{run}{help},
	"colored!"			=> \$ep->{run}{colored},
	"dummy!"			=> \$ep->{run}{dummy},
	"verbose!"			=> \$ep->{run}{verbose},
	"json=s"			=> \$opt_json,
	"ignoreInt!"		=> \$opt_ignoreInt )){

		msgOut( "try '".$daemon->command()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $daemon->help()){
	$daemon->helpExtern( $defaults );
	TTP::exit();
}

msgVerbose( "found colored='".( $daemon->colored() ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $daemon->dummy() ? 'true':'false' )."'" );
msgVerbose( "found verbose='".( $daemon->verbose() ? 'true':'false' )."'" );
msgVerbose( "found json='$opt_json'" );
msgVerbose( "found ignoreInt='".( $opt_ignoreInt ? 'true':'false' )."'" );

msgErr( "'--json' option is mandatory, not specified" ) if !$opt_json;

if( !TTP::errs()){
	$daemon->setConfig({ json => $opt_json, ignoreInt => $opt_ignoreInt });
}
if( TTP::errs()){
	TTP::exit();
}

$daemon->messagingSub( \&mqttMessaging );
$daemon->disconnectSub( \&mqttDisconnect );

$daemon->declareSleepables( $commands );
$daemon->sleepableDeclareFn( sub => \&works, interval => configScanInterval() );
$daemon->sleepableStart();

$daemon->terminate();
