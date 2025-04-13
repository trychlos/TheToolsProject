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
# Just to be sure: this makes use of TTP, but is not part itself of TTP (though a not so bad example of application).
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
	# we do not have here any specific command
	#help => \&help,
};

# scanning for new elements
my $first = true;
my @previousScan = ();
my @runningScan = ();

# keep a count of found alerts per level and per emitter
my $stats = {
	byLevel => {},
	byEmitter => {}
};

# -------------------------------------------------------------------------------------------------
# Returns the configured 'do': the list of actions

sub configDo {
	my $config = $daemon->jsonData();
	my $do = $config->{do} || [];
	return $do;
}

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

sub doWithNew {
	my ( @newFiles ) = @_;
	my $actions = $daemon->configDo();

	foreach my $file ( @newFiles ){
		msgVerbose( "new alert '$file'" );
		my $data = TTP::jsonRead( $file );
		# incremente our stats
		$stats->{byLevel}{$data->{level}} = 0 if !defined $stats->{byLevel}{$data->{level}};
		$stats->{byLevel}{$data->{level}} += 1;
		$stats->{byEmitter}{$data->{emitter}} = 0 if !defined $stats->{byEmitter}{$data->{emitter}};
		$stats->{byEmitter}{$data->{emitter}} += 1;
		# tries to execute all defined actions
		foreach my $do ( @{$actions} ){
			my $command = TTP::commandByOs([], { json => $do });
			if( $command ){
				my $levelMatch = true;
				if( $do->{levelRe} ){
					$levelMatch = ( $data->{level} =~ m/$do->{levelRe}/ );
					msgVerbose( "level='$data->{level}' RE='$do->{levelRe}' match=".( $levelMatch ? 'true' : 'false' ));
				} else {
					msgVerbose( "no 'levelRe' regular expression");
				}
				my $emitterMatch = true;
				if( $do->{emitterRe} ){
					$emitterMatch = ( $data->{emitter} =~ m/$do->{emitterRe}/ );
					msgVerbose( "emitter='$data->{emitter}' RE='$do->{emitterRe}' match=".( $emitterMatch ? 'true' : 'false' ));
				} else {
					msgVerbose( "no 'emitterRe' regular expression");
				}
				my $titleMatch = true;
				if( $do->{titleRe} ){
					$titleMatch = ( $data->{title} =~ m/$do->{titleRe}/ );
					msgVerbose( "title='$data->{title}' RE='$do->{titleRe}' match=".( $titleMatch ? 'true' : 'false' ));
				} else {
					msgVerbose( "no 'titleRe' regular expression");
				}
				my $messageMatch = true;
				if( $do->{messageRe} ){
					$messageMatch = ( $data->{message} =~ m/$do->{messageRe}/ );
					msgVerbose( "message='$data->{message}' RE='$do->{messageRe}' match=".( $messageMatch ? 'true' : 'false' ));
				} else {
					msgVerbose( "no 'messageRe' regular expression");
				}
				if( $levelMatch && $emitterMatch && $titleMatch && $messageMatch ){
					my $res = TTP::commandExec({
						command => $command,
						macros => {
							LEVEL => $data->{level},
							EMITTER => $data->{emitter},
							TITLE => $data->{title},
							MESSAGE => $data->{message},
							STAMP => $data->{stamp},
							JSON => json_encode( $data )
						}
					});
				}
			}
		}
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
# we find less files in this iteration than in the previous - maybe some files have been purged,
# deleted, moved, or we have a new directory, or another reason - just reset and restart over

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
	"help!"				=> sub { $ep->runner()->help( @_ ); },
	"colored!"			=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"			=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"			=> sub { $ep->runner()->verbose( @_ ); },
	"json=s"			=> \$opt_json,
	"ignoreInt!"		=> \$opt_ignoreInt )){

		msgOut( "try '".$daemon->command()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $daemon->help()){
	$daemon->helpExtern( $defaults );
	TTP::exit();
}

msgVerbose( "got colored='".( $daemon->colored() ? 'true':'false' )."'" );
msgVerbose( "got dummy='".( $daemon->dummy() ? 'true':'false' )."'" );
msgVerbose( "got verbose='".( $daemon->verbose() ? 'true':'false' )."'" );
msgVerbose( "got json='$opt_json'" );
msgVerbose( "got ignoreInt='".( $opt_ignoreInt ? 'true':'false' )."'" );

msgErr( "'--json' option is mandatory, not specified" ) if !$opt_json;

if( !TTP::errs()){
	$daemon->setConfig({ json => $opt_json, ignoreInt => $opt_ignoreInt });
}
if( TTP::errs()){
	TTP::exit();
}

if( $daemon->messagingEnabled()){
	$daemon->messagingSub( \&mqttMessaging );
	$daemon->disconnectSub( \&mqttDisconnect );
}

$daemon->declareSleepables( $commands );
$daemon->sleepableDeclareFn( sub => \&works, interval => configScanInterval());
$daemon->sleepableStart();

$daemon->terminate();
