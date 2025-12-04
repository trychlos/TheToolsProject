#!/usr/bin/perl
# @(#) Manage accesses to a websote for the sake of 'http.pl compare' verb.
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --json=<filename>       the name of the JSON configuration file [${json}]
# @(-) --[no]ignoreInt         ignore the (Ctrl+C) INT signal [${ignoreInt}]
# @(-) --role=<role>           the name of the role we deal with [${role}]
# @(-) --which=<which>         whether we deal with 'ref' or 'new' site [${which}]
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
# For each instance of this daemon, we have a chromedriver browser connection and the corresponding log-in data.

use utf8;
use strict;
use warnings;

use Data::Dumper;
use File::Spec;
use Getopt::Long;
use Path::Tiny qw( path );
use Time::Moment;

use TTP;
use vars::global qw( $ep );

use TTP::Constants qw( :all );
use TTP::HTTP::Compare::Browser;
use TTP::JSONable;
use TTP::Message qw( :all );
use TTP::RunnerDaemon;

my $daemon = TTP::RunnerDaemon->bootstrap();

# have our own datas
$daemon->{this} = {};
$daemon->{this}{stats} = {};

use constant {
};

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	json => '',
	ignoreInt => 'no',
	role => '',
	which => ''
};

my $opt_json = $defaults->{json};
my $opt_ignoreInt = false;
my $opt_role = $defaults->{role};
my $opt_which = $defaults->{which};

# the commands this daemon answers to
$daemon->{this}{commands} = {
	stats => \&answerStats,
	status => \&answerStatus,
};

# some constants
my $Const = {
};

# -------------------------------------------------------------------------------------------------
sub answerStats {
	my ( $req ) = @_;
	my $answer = "";
	foreach my $key ( sort keys %{$daemon->{this}{stats}} ){
	}
	return $answer;
}

# -------------------------------------------------------------------------------------------------
# add to the standard 'status' answer our own data

sub answerStatus {
	my ( $req ) = @_;
	my $answer = TTP::RunnerDaemon->commonCommands()->{status}( $req, $daemon->{this}{commands} );
	$answer .= "role: ".$opt_role.EOL;
	$answer .= "which: ".$opt_which.EOL;
	return $answer;
}

# -------------------------------------------------------------------------------------------------
# Returns the configured 'workerInterval' (in sec.) defaulting to DEFAULT_WORKER_INTERVAL

=pod
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
=cut

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
					my $commands = TTP::commandByOS([], { jsonable => $jsonable });
					if( $commands && scalar( @{$commands} )){
						my $res = TTP::commandExec( $commands, {
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
# connect to and start the chromedriver browser

sub startBrowser {

	$daemon->{this}{browser} = TTP::HTTP::Compare::Browser->new( $self->ep(), $self, $which, $self->{_args}{args} );

	if( !$browser ){
		msgErr( "unable to instanciate a browser driver on '$which' site" );
	} else {
		msgVerbose( "browser '$which' successfully instanciated" );
	}
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
	"ignoreInt!"		=> \$opt_ignoreInt,
	"role=s"			=> \$opt_role,
	"which=s"			=> \$opt_which )){

		msgOut( "try '".$daemon->command()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $daemon->help()){
	$daemon->displayHelp( $defaults );
	TTP::exit();
}

msgVerbose( "got colored='".( $daemon->colored() ? 'true':'false' )."'" );
msgVerbose( "got dummy='".( $daemon->dummy() ? 'true':'false' )."'" );
msgVerbose( "got verbose='".( $daemon->verbose() ? 'true':'false' )."'" );
msgVerbose( "got json='$opt_json'" );
msgVerbose( "got ignoreInt='".( $opt_ignoreInt ? 'true':'false' )."'" );
msgVerbose( "got role='$opt_role'" );
msgVerbose( "got which='$opt_which'" );

msgErr( "'--json' option is mandatory, not specified" ) if !$opt_json;

if( !TTP::errs()){
	$daemon->run({ jsonPath => $opt_json, ignoreInt => $opt_ignoreInt });
}

if( TTP::errs()){
	TTP::exit();
}

startBrowser();
if( TTP::errs()){
	$daemon->terminate();
	TTP::exit();
}

logIn();
if( TTP::errs()){
	$daemon->terminate();
	TTP::exit();
}

$daemon->declareSleepables( $daemon->{this}{commands} );
$daemon->sleepableStart();

$daemon->terminate();
