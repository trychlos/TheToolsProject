#!/usr/bin/perl
# @(#) Monitor the node through its 'status' keys
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --json=<filename>       the name of the JSON configuration file of this daemon [${json}]
# @(-) --[no]ignoreInt         ignore the (Ctrl+C) INT signal [${ignoreInt}]
#
# @(@) Rationale:
# @(@) We may miss of an enough advanced scheduler on a platform, so this daemon tries to monitor the status at periodic intervals.
# @(@) This script is expected to be run as a daemon, started via a 'daemon.pl start -json <filename.json>' command.
#
# TheToolsProject - Tools System and Working Paradigm for IT Production
# Copyright (©) 1998-2023 Pierre Wieser (see AUTHORS)
# Copyright (©) 2023-2025 PWI Consulting
#
# TheToolsProject is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version.
#
# TheToolsProject is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with TheToolsProject; see the file COPYING. If not,
# see <http://www.gnu.org/licenses/>.
#
# This script is mostly written like a TTP verb but is not.
# This is an example of how to take advantage of TTP to write your own (rather pretty and efficient) daemon.
#
# JSON specific configuration:
#
# - workerInterval, the monitoring period, defaulting to 300000 ms (5 min.)
# - keys, the keys to be executed, defaulting to ( 'status', 'monitor' )

use utf8;
use strict;
use warnings;

use Data::Dumper;
use Getopt::Long;

use TTP;
use vars::global qw( $ep );

use TTP::Constants qw( :all );
use TTP::Message qw( :all );
use TTP::RunnerDaemon;
use TTP::Service;

my $daemon = TTP::RunnerDaemon->bootstrap();

use constant {
	MIN_WORKER_INTERVAL => 60000,
	DEFAULT_WORKER_INTERVAL => 300000,
	DEFAULT_KEYS => [ 'status', 'monitor' ]
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
	stats => \&answerStats,
	status => \&answerStatus,
};

# try to have some statistics
my $stats = {
	count => 0,
	ignored => 0,
	restored => []
};

# -------------------------------------------------------------------------------------------------
# display some execution statistics on demand

sub answerStats {
	my ( $req ) = @_;
	my $answer = "total seen execution reports: $stats->{count}".EOL;
	$answer .= "ignored: $stats->{ignored}".EOL;
	my $executed = scalar @{$stats->{restored}};
	$answer .= "restore operations: $executed".EOL;
	if( $executed ){
		my $last = @{$stats->{restored}}[$executed-1];
		$answer .= "last was from $last->{reportSourceFileName} to $last->{localSynced} at $stats->{now}".EOL;
	}
	#$answer .= "last scan contained [".join( ',', @previousScan )."]".EOL;
	return $answer;
}

# -------------------------------------------------------------------------------------------------
# add to the standard 'status' answer our own data (remote host and dir)

sub answerStatus {
	my ( $req ) = @_;
	my $answer = TTP::RunnerDaemon->commonCommands()->{status}( $req, $commands );
	$answer .= "workerInterval: ".configWorkerInterval().EOL;
	$answer .= "keys: [".join( ',', @{configKeys()} ).']'.EOL;
	return $answer;
}

# -------------------------------------------------------------------------------------------------
# Returns the configured 'keys' (in sec.) defaulting to DEFAULT_KEYS

sub configKeys {
	my $config = $daemon->config()->jsonData();
	my $keys = $config->{keys};
	$keys = DEFAULT_KEYS if !defined $keys;

	return $keys;
}

# -------------------------------------------------------------------------------------------------
# Returns the configured 'workerInterval' (in sec.) defaulting to DEFAULT_WORKER_INTERVAL

sub configWorkerInterval {
	my $config = $daemon->config()->jsonData();
	my $interval = $config->{workerInterval};
	$interval = DEFAULT_WORKER_INTERVAL if !defined $interval;
	if( $interval < MIN_WORKER_INTERVAL ){
		msgVerbose( "defined workerInterval=$interval less than minimum accepted ".MIN_WORKER_INTERVAL.", ignored" );
		$interval = DEFAULT_WORKER_INTERVAL;
	}

	return $interval;
}

# -------------------------------------------------------------------------------------------------
# Returns true if the given var has a non-empty 'commands' array
# (I):
# - a variable to be tested (should be an array as returned by TTP::commandByOS()

sub hasCommands {
	my ( $var ) = @_;
	my $res = false;
	my $ref = ref( $var );
	if( $ref eq 'ARRAY' ){
		my $count = scalar( @{$var} );
		$res = ( $count > 0 );
	}
	return $res;
}

# -------------------------------------------------------------------------------------------------
# On disconnection, try to erase the published topics

sub mqttDisconnect {
	my ( $daemon ) = @_;
	my $topic = $daemon->topic();
	my $array = [];
	push( @{$array}, {
		topic => "$topic/workerInterval",
		payload => ''
	},{
		topic => "$topic/keys",
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
		topic => "$topic/workerInterval",
		payload => configWorkerInterval()
	},{
		topic => "$topic/keys",
		payload => '['.join( ',', @{configKeys()}).']'
	});
	return $array;
}

# -------------------------------------------------------------------------------------------------
# do its work:
# search for the specified monitoring keys at the node level, and then at the service level for each
# service on this node, and execute them

sub worker {
	# get commands at the node level
	my $node = $ep->node();
	my $keys = configKeys();
	msgVerbose( "searching for monitoring commands at the node level" );
	my $commands = TTP::commandByOS( $keys, { jsonable => $ep->node() });
	if( hasCommands( $commands )){
		TTP::commandExec( $commands, {
			macros => {
				NODE => $node->name(),
				ENVIRONMENT => $node->environment() || ''
			}
		});
	} else {
		msgVerbose( "no commands found for node" );
	}
	# get the list of (non-hidden) services hosted on this node
	msgVerbose( "searching for monitoring commands at the services level" );
	my $services = TTP::Service->list();
	# and run the same for each services
	if( scalar( @{$services} )){
		foreach my $serviceName ( @{$services} ){
			msgVerbose( "examining service $serviceName" );
			my $service = TTP::Service->new( $ep, { service => $serviceName });
			my $commands = $service->commands( $keys );
			if( hasCommands( $commands )){
				TTP::commandExec( $commands, {
					macros => {
						NODE => $node->name(),
						ENVIRONMENT => $node->environment() || '',
						SERVICE => $service->name()
					}
				});
			} else {
				msgVerbose( "no commands found for '$serviceName'" );
			}
		}
	} else {
		msgVerbose( "no service found on node" );
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
	$daemon->displayHelp( $defaults );
	TTP::exit();
}

msgVerbose( "found colored='".( $daemon->colored() ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $daemon->dummy() ? 'true':'false' )."'" );
msgVerbose( "found verbose='".( $daemon->verbose() ? 'true':'false' )."'" );
msgVerbose( "found json='$opt_json'" );
msgVerbose( "found ignoreInt='".( $opt_ignoreInt ? 'true':'false' )."'" );

msgErr( "'--json' option is mandatory, not specified" ) if !$opt_json;

if( !TTP::errs()){
	$daemon->run({ jsonPath => $opt_json, ignoreInt => $opt_ignoreInt });
}

if( TTP::errs()){
	TTP::exit();
}

if( $daemon->config()->messagingEnabled()){
	$daemon->messagingSub( \&mqttMessaging );
	$daemon->disconnectSub( \&mqttDisconnect );
}

$daemon->declareSleepables( $commands );
$daemon->sleepableDeclareFn( sub => \&worker, interval => configWorkerInterval());
$daemon->sleepableStart();

$daemon->terminate();
