#!/usr/bin/perl
# @(#) Connect to a MQTT broker and monitor the published MQTT topics.
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
# - host: the MQTT broker
# - topics: a HASH whose each key is a regular expression which is matched against the topics
#   and whose values are the behavior to have.

use utf8;
use strict;
use warnings;

use Data::Dumper;
use File::Spec;
use Getopt::Long;
use Path::Tiny qw( path );
use Time::Moment;

use TTP;
use TTP::Constants qw( :all );
use TTP::JSONable;
use TTP::Message qw( :all );
use TTP::MQTT;
use TTP::RunnerDaemon;
use vars::global qw( $ep );

my $daemon = TTP::RunnerDaemon->bootstrap();

use constant {
	MIN_WORKER_INTERVAL => 60000,
	DEFAULT_WORKER_INTERVAL => 300000
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

# the MQTT connection handle (unique for this daemon)
my $mqtt = undef;
# our statistics
my $stats = {};

# -------------------------------------------------------------------------------------------------
sub answerStats {
	my ( $req ) = @_;
	my $answer = "";
	foreach my $key ( sort keys %{$stats} ){
		$answer .= "topic: '$key'".EOL;
		$answer .= "  seen: '$stats->{$key}{count}'".EOL;
		$answer .= "  toLog: '$stats->{$key}{toLog}'".EOL;
		$answer .= "  toStdout: '$stats->{$key}{toStdout}'".EOL;
		$answer .= "  toStderr: '$stats->{$key}{toStderr}'".EOL;
		$answer .= "  toFile: '$stats->{$key}{toFile}'".EOL;
		$answer .= "  actions:".EOL;
		$answer .= "    total: '$stats->{$key}{actions}{total}'".EOL;
		$answer .= "    enabled: '$stats->{$key}{actions}{enabled}'".EOL;
		$answer .= "    success: '$stats->{$key}{actions}{success}'".EOL;
		$answer .= "    failed: '$stats->{$key}{actions}{failed}'".EOL;
	}
	return $answer;
}

# -------------------------------------------------------------------------------------------------
# add to the standard 'status' answer our own data

sub answerStatus {
	my ( $req ) = @_;
	my $answer = TTP::RunnerDaemon->commonCommands()->{status}( $req, $commands );
	$answer .= "host: ".configHost().EOL;
	$answer .= "workerInterval: ".configWorkerInterval().EOL;
	$answer .= "topics: [ ".join( ', ', sort keys %{$daemon->config()->jsonData()->{topics}} )." ]".EOL;
	return $answer;
}

# -------------------------------------------------------------------------------------------------
# returns the configured MQTT broker host

sub configHost {
	my $host = $daemon->config()->jsonData()->{host};
	$host = $ep->var([ 'MQTTGateway', 'host' ]) if !$host;
	return $host;
}

# -------------------------------------------------------------------------------------------------
# connect to the target MQTT broker
# either it is configured in the daemon, or connect to the site default
# returns truethy value if OK

sub configMqtt {
	my $host = configHost();
	if( $host ){
		$mqtt = TTP::MQTT::connect({
			broker => $host
		});
		if( $mqtt ){
			my $listeningInterval = $daemon->config()->listeningInterval();
			$daemon->sleepableDeclareFn( sub => sub { $mqtt->tick( $listeningInterval ); }, interval => $listeningInterval );
			$mqtt->subscribe( '#' => \&worker, '$SYS/#' => \&worker );
		}
	} else {
		msgErr( "unable to found a host to connect to" ) if !$host;
	}
	return $mqtt;
}

# -------------------------------------------------------------------------------------------------
# interprets the defined topics
# simultaneously identifying the target MQTT broker and connecting to
# may send error messages in case of an error
# returns truethy value if OK

sub configTopics {
	my $topics = $daemon->config()->jsonData()->{topics};
	foreach my $key ( sort keys %{$topics} ){
		# initialize our stats for this topic
		$stats->{$key} = {
			count => 0,
			toLog => 0,
			toStdout => 0,
			toStderr => 0,
			toFile => 0,
			actions => {
				total => 0,
				enabled => 0,
				success => 0,
				failed => 0
			}
		};
	}
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
# the received topic match a daemon configuration item
# (I):
# - the received topic
# - the corresponding payload
# - the definition key (the matching topic regular expression)
# - the corresponding object which defines the actions to be done

sub doMatched {
	my ( $topic, $payload, $key, $config ) = @_;

	# increment the counter
	$stats->{$key}{count} += 1;

	# whether to log the message to an appended file
	my $toLog = false;
	$toLog = $config->{toLog}{enabled} if defined $config->{toLog} && defined $config->{toLog}{enabled};
	if( $toLog ){
		my $logFile = File::Spec->catfile( TTP::logsCommands(), $daemon->name().'.log' );
		$logFile = $config->{toLog}{filename} if defined $config->{toLog} && defined $config->{toLog}{filename};
		$logFile = replaceMacros( $logFile, {
			TOPIC => $topic,
			PAYLOAD => $payload
		});
		msgLog( "$topic [$payload]", { logFile => $logFile });
		$stats->{$key}{toLog} += 1;
	} else {
		msgVerbose( "$topic: toLog is not enabled" );
	}

	# whether to print to stdout
	my $toStdout = false;
	$toStdout = $config->{toStdout}{enabled} if defined $config->{toStdout} && defined $config->{toStdout}{enabled};
	if( $toStdout ){
		print STDOUT Time::Moment->now->strftime( '%Y-%m-%d %H:%M:%S.%6N %:z' )." $topic $payload".EOL;
		$stats->{$key}{toStdout} += 1;
	} else {
		msgVerbose( "$topic: toStdout is not enabled" );
	}

	# whether to print to stderr
	my $toStderr = false;
	$toStderr = $config->{toStderr}{enabled} if defined $config->{toStderr} && defined $config->{toStderr}{enabled};
	if( $toStderr ){
		print STDERR Time::Moment->now->strftime( '%Y-%m-%d %H:%M:%S.%6N %:z' )." $topic $payload".EOL;
		$stats->{$key}{toStderr} += 1;
	} else {
		msgVerbose( "$topic: toStderr is not enabled" );
	}

	# whether to create a new file
	my $toFile = false;
	$toFile = $config->{toFile}{enabled} if defined $config->{toFile} && defined $config->{toFile}{enabled};
	if( $toFile ){
		my $destFile = File::Spec->catfile( File::Spec->catdir( TTP::logsCommands(), $daemon->name()), '<TOPIC>'.Time::Moment->now->strftime( '%y%m%d%H%M%S%6N' ).'.log' );
		$destFile = $config->{toFile}{filename} if defined $config->{toFile} && defined $config->{toFile}{filename};
		$destFile = replaceMacros( $destFile, {
			TOPIC => $topic,
			PAYLOAD => $payload
		});
		path( $destFile )->spew_utf8( Time::Moment->now->strftime( '%Y-%m-%d %H:%M:%S.%6N %:z' )." $topic $payload".EOL );
		$stats->{$key}{toFile} += 1;
	} else {
		msgVerbose( "$topic: toFile is not enabled" );
	}

	# have other actions ?
	my $actions = $config->{actions};
	if( $actions ){
		if( ref( $actions ) eq 'ARRAY' ){
			# tries to execute all defined actions
			my $totalCount = 0;
			my $enabledCount = 0;
			my $successCount = 0;
			my $failedCount = 0;
			foreach my $do ( @{$actions} ){
				$totalCount += 1;
				my $enabled = false;
				$enabled = $do->{enabled} if defined $do->{enabled};
				if( $enabled ){
					$enabledCount += 1;
					my $jsonable = TTP::JSONable->new( $ep, $do );
					my $command = TTP::commandByOS([], { jsonable => $jsonable, withCommand => true });
					if( $command ){
						my $res = TTP::commandExec( $command, {
							macros => {
								TOPIC => $topic,
								PAYLOAD => $payload
							}
						});
						if( $res->{success} ){
							$successCount += 1;
						} else {
							$failedCount += 1;
						}
					} else {
						msgVerbose( "$topic: action n° $totalCount doesn't have a command" );
					}
				} else {
					msgVerbose( "$topic: action n° $totalCount is not enabled" );
				}
			}
			$stats->{$key}{actions}{total} = $totalCount;
			$stats->{$key}{actions}{enabled} = $enabledCount;
			$stats->{$key}{actions}{success} += $successCount;
			$stats->{$key}{actions}{failed} += $failedCount;
		} else {
			msgErr( "$topic: unexpected object found for 'actions', expected 'ARRAY', got '".ref( $actions )."'" );
		}
	} else {
		msgVerbose( "$topic: no actions found" );
	}
}

# -------------------------------------------------------------------------------------------------
# replace the macros

sub replaceMacros {
	my ( $input, $macros ) = @_;
	my $res = $input;
	foreach my $key ( sort keys %{$macros} ){
		$res =~ s/<$key>/$macros->{$key}/g;
	}
	return $res;
}

# -------------------------------------------------------------------------------------------------
# do its work, examining the MQTT queue
# (I):
# - the topic
# - the payload

sub worker {
	my ( $topic, $payload ) = @_;
	msgVerbose( "receiving $topic" );
	my $topics = $daemon->config()->jsonData()->{topics};
	foreach my $key ( sort keys %{$topics} ){
		if( $topic =~ m/$key/ ){
			msgVerbose( "$topic is matched" );
			doMatched( $topic, $payload, $key, $topics->{$key} );
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
	$daemon->run({ jsonPath => $opt_json, ignoreInt => $opt_ignoreInt });
}
if( !TTP::errs()){
	configMqtt();
}
if( !TTP::errs()){
	configTopics();
}

if( TTP::errs()){
	TTP::exit();
}

$daemon->declareSleepables( $commands );
$daemon->sleepableStart();

TTP::MQTT::disconnect( $mqtt );
$daemon->terminate();
