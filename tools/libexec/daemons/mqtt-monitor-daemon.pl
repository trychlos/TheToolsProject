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
# - workerInterval, the monitoring period, defaulting to 300000 ms (5 min.)
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
	#help => \&help,
};

# specific to this daemon
# keep a hash of mqtt connections to topics
my $mqtts = {};

# -------------------------------------------------------------------------------------------------
# interprets the defined topics
# simultaneously identifying the target MQTT broker and connecting to
# may send error messages in case of an error

sub configTopics {
	my $topics = $daemon->config()->jsonData()->{topics};
	foreach my $topicRe ( sort keys %{$topics} ){
		my $topic = $topics->{$topicRe};
		# identify the broker, may be undef
		my $host =  $topic->{host};
		my $name = $host || 'default';
		# initialize our structure
		$mqtts->{$name} = $mqtts->{$name} || {};
		$mqtts->{$name}{$topicRe} = {
			count => 0,
			toLog => 0,
			toStdout => 0,
			toStderr => 0,
			toFile => 0,
			actions => 0
		};
		# connect to it
		# reiter for each topic which wants subscribe to this broker if not done
		# on connection subscribe to all topics
		if( !$mqtts->{$name}{mqtt} ){
			$mqtts->{$name}{mqtt} = TTP::MQTT::connect({
				broker => $host
			});
			if( $mqtts->{$name}{mqtt} ){
				$daemon->sleepableDeclareFn( sub => sub { $mqtts->{$name}{mqtt}->tick( $daemon->config()->listeningInterval()); }, interval => $daemon->config()->listeningInterval());
				$mqtts->{$name}{mqtt}->subscribe( '#' => sub { worker( $name, @_ ); }, '$SYS/#' => sub { worker( $name, @_ ); });
			}
		}
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
# - the name of the broker
# - the received topic
# - the corresponding payload
# - the definition key (the matching topic regular expression)
# - the corresponding object which defines the actions to be done

sub doMatched {
	my ( $name, $topic, $payload, $key, $config ) = @_;

	# increment the counter
	$mqtts->{$name}{$key}{count} += 1;

	# whether to log the message to an appended file
	my $toLog = false;
	$toLog = $config->{toLog}{enabled} if exists $config->{toLog} && exists $config->{toLog}{enabled};
	if( $toLog ){
		my $logFile = File::Spec->catfile( TTP::logsCommands(), $daemon->name().'.log' );
		$logFile = $config->{toLog}{filename} if exists $config->{toLog} && exists $config->{toLog}{filename};
		$logFile = replaceMacros( $logFile, {
			TOPIC => $topic,
			PAYLOAD => $payload
		});
		msgLog( "$topic [$payload]", { logFile => $logFile });
		$mqtts->{$name}{$key}{toLog} += 1;
	} else {
		msgVerbose( "$topic: toLog is not enabled" );
	}

	# whether to print to stdout
	my $toStdout = false;
	$toStdout = $config->{toStdout}{enabled} if exists $config->{toStdout} && exists $config->{toStdout}{enabled};
	if( $toStdout ){
		print STDOUT Time::Moment->now->strftime( '%Y-%m-%d %H:%M:%S.%6N %:z' )." $topic $payload".EOL;
		$mqtts->{$name}{$key}{toStdout} += 1;
	} else {
		msgVerbose( "$topic: toStdout is not enabled" );
	}

	# whether to print to stderr
	my $toStderr = false;
	$toStderr = $config->{toStderr}{enabled} if exists $config->{toStderr} && exists $config->{toStderr}{enabled};
	if( $toStderr ){
		print STDERR Time::Moment->now->strftime( '%Y-%m-%d %H:%M:%S.%6N %:z' )." $topic $payload".EOL;
		$mqtts->{$name}{$key}{toStderr} += 1;
	} else {
		msgVerbose( "$topic: toStderr is not enabled" );
	}

	# whether to create a new file
	my $toFile = false;
	$toFile = $config->{toFile}{enabled} if exists $config->{toFile} && exists $config->{toFile}{enabled};
	if( $toFile ){
		my $destFile = File::Spec->catfile( File::Spec->catdir( TTP::logsCommands(), $daemon->name()), '<TOPIC>'.Time::Moment->now->strftime( '%y%m%d%H%M%S%6N' ).'.log' );
		$destFile = $config->{toFile}{filename} if exists $config->{toFile} && exists $config->{toFile}{filename};
		$destFile = replaceMacros( $destFile, {
			TOPIC => $topic,
			PAYLOAD => $payload
		});
		path( $destFile )->spew_utf8( Time::Moment->now->strftime( '%Y-%m-%d %H:%M:%S.%6N %:z' )." $topic $payload".EOL );
		$mqtts->{$name}{$key}{toFile} += 1;
	} else {
		msgVerbose( "$topic: toFile is not enabled" );
	}

	# have other actions ?
	my $actions = $config->{actions};
	if( $actions ){
		if( ref( $actions ) eq 'ARRAY' ){
			# tries to execute all defined actions
			my $count = 0;
			foreach my $do ( @{$actions} ){
				$count += 1;
				my $enabled = false;
				$enabled = $do->{enabled} if exists $do->{enabled};
				if( $enabled ){
					my $jsonable = TTP::JSONable->new( $ep, $do );
					my $command = TTP::commandByOS([], { jsonable => $jsonable, withCommand => true });
					if( $command ){
						my $res = TTP::commandExec( $command, {
							macros => {
								TOPIC => $topic,
								PAYLOAD => $payload
							}
						});
						#print "result: ".Dumper( $res );
					} else {
						msgVerbose( "$topic: action n° $count doesn't have a command" );
					}
				} else {
					msgVerbose( "$topic: action n° $count is not enabled" );
				}
			}
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
# do its work, examining the MQTT queues
# (I):
# - the broker name
# - the topic
# - the payload

sub worker {
	my ( $name, $topic, $payload ) = @_;
	# may get empty topic at initialization time
	if( $topic ){
		my $topics = $daemon->config()->jsonData()->{topics};
		foreach my $key ( sort keys %{$topics} ){
			if( $topic =~ m/$key/ ){
				doMatched( $name, $topic, $payload, $key, $topics->{$key} );
			}
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
	configTopics();
}

if( TTP::errs()){
	TTP::exit();
}

$daemon->declareSleepables( $commands );
$daemon->sleepableDeclareFn( sub => \&worker, interval => configWorkerInterval());
$daemon->sleepableStart();

#TTP::MQTT::disconnect( $mqtt );
$daemon->terminate();
