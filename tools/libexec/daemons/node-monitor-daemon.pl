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
# The Tools Project - Tools System and Working Paradigm for IT Production
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
# - runInterval, the monitoring period, defaulting to 300000 ms (5 min.)
# - keys, the keys to be executed, defaulting to ( 'status', 'monitor' )

use utf8;
use strict;
use warnings;

use Data::Dumper;
use Getopt::Long;

use TTP;
use TTP::Constants qw( :all );
use TTP::Message qw( :all );
use TTP::RunnerDaemon;
use vars::global qw( $ep );

my $daemon = TTP::runDaemon();

use constant {
	MIN_RUN_INTERVAL => 60000,
	DEFAULT_RUN_INTERVAL => 300000,
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
	my $answer = TTP::Daemon->commonCommands()->{status}( $req, $commands );
	$answer .= "runInterval: ".configRunInterval().EOL;
	$answer .= "keys: [".join( ',', @{configKeys()} ).']'.EOL;
	return $answer;
}

# -------------------------------------------------------------------------------------------------
# Returns the configured 'keys' (in sec.) defaulting to DEFAULT_KEYS

sub configKeys {
	my $config = $daemon->jsonData();
	my $keys = $config->{keys};
	$keys = DEFAULT_KEYS if !defined $keys;

	return $keys;
}

# -------------------------------------------------------------------------------------------------
# Returns the configured 'runInterval' (in sec.) defaulting to DEFAULT_RUN_INTERVAL

sub configRunInterval {
	my $config = $daemon->jsonData();
	my $interval = $config->{runInterval};
	$interval = DEFAULT_RUN_INTERVAL if !defined $interval;
	if( $interval < MIN_RUN_INTERVAL ){
		msgVerbose( "defined runInterval=$interval less than minimum accepted ".MIN_RUN_INTERVAL.", ignored" );
		$interval = DEFAULT_RUN_INTERVAL;
	}

	return $interval;
}

# -------------------------------------------------------------------------------------------------
# Returns the list (an array) of the services hosted in this node

sub getServices {
	return $ep->node()->services();
}

# -------------------------------------------------------------------------------------------------
# Returns true if the given var has a non-empty 'commands' array
# (I):
# - a variable to be tested (should be a hash as returned by ->var() methods)

sub hasCommands {
	my ( $var ) = @_;
	my $res = false;
	if( $var and $var->{commands} ){
		my $ref = ref( $var->{commands} );
		if( $ref eq 'ARRAY' ){
			my $count = scalar( @{$var->{commands}} );
			$res = ( $count > 0 );
		}
	}
	return $res;
}

# -------------------------------------------------------------------------------------------------
# Replace the found macros
# (I):
# - the input string
# - a hash where keys are the macros to be replaced, and the values the replacement value
# (O):
# - the replaced string

sub macroReplace {
	my( $str, $hash ) = @_;
	
	foreach my $k ( keys( %{$hash} )){
		$str =~ s/$k/$hash->{$k}/g;
	}
	
	return $str;
}

# -------------------------------------------------------------------------------------------------
# On disconnection, try to erase the published topics

sub mqttDisconnect {
	my ( $daemon ) = @_;
	my $topic = $daemon->topic();
	my $array = [];
	push( @{$array}, {
		topic => "$topic/runInterval",
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
		topic => "$topic/runInterval",
		payload => configRunInterval()
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

sub works {
	# recompute at each loop all dynamic variables
	$daemon->{config} = $daemon->jsonData();
	# and run..
	# get commands at the node level
	my $null = TTP::nullByOS();
	msgVerbose( "got null=$null" );
	my $node = $ep->node();
	my $keys = configKeys();
	msgVerbose( "searching for monitoring commands at the node level" );
	#my $commands = $node->var( $keys );
	my $commands = TTP::commandByOs( $keys, { withCommand => false, withCommands => true, jsonable => $ep->node()->jsonData() });
	if( hasCommands( $commands )){
		foreach my $cmd ( @{$commands->{commands}} ){
			$cmd = macroReplace( $cmd, { '<NODE>' => $node->name() });
			$cmd = macroReplace( $cmd, { '<ENVIRONMENT>' => $node->environment() });
			msgVerbose( "running $cmd" );
			`$cmd <$null`;
		}
	} else {
		msgVerbose( "no commands found for node" );
	}
	# get the list of services hosted on this node
	msgVerbose( "searching for monitoring commands at the services level" );
	my $services = getServices();
	# and run the same for each services
	foreach my $service ( @{$services} ){
		msgVerbose( "examining service $service" );
		my $serviceKeys = [ 'Services', $service, @{$keys} ];
		my $commands = $node->var( $serviceKeys );
		if( hasCommands( $commands )){
			foreach my $cmd ( @{$commands->{commands}} ){
				$cmd = macroReplace( $cmd, { '<NODE>' => $node->name() });
				$cmd = macroReplace( $cmd, { '<ENVIRONMENT>' => $node->environment() });
				$cmd = macroReplace( $cmd, { '<SERVICE>' => $service });
				msgVerbose( "running $cmd" );
				`$cmd <$null`;
			}
		} else {
			msgVerbose( "no commands found for '$service'" );
		}
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
	$daemon->setConfig({ json => $opt_json, ignoreInt => $opt_ignoreInt });
}

# deeply check arguments
# - current host must have a json configuration file
# stop here if we do not have any configuration for this host 
if( !TTP::errs()){
	$daemon->{config} = $daemon->jsonData();
	#print Dumper( $daemon );
}

if( TTP::errs()){
	TTP::exit();
}

$daemon->messagingSub( \&mqttMessaging );
$daemon->disconnectSub( \&mqttDisconnect );

$daemon->declareSleepables( $commands );
$daemon->sleepableDeclareFn( sub => \&works, interval => configRunInterval());
$daemon->sleepableStart();

$daemon->terminate();
