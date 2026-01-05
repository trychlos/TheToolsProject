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
# TheToolsProject - Tools System and Working Paradigm for IT Production
# Copyright (©) 1998-2023 Pierre Wieser (see AUTHORS)
# Copyright (©) 2023-2026 PWI Consulting
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
# - monitoredDir: the directory to be monitored for alerts files, defaulting to alertsDir
# - monitoredFile: a regular expression to match the alert files, defaulting to '^.*$'
# - workerInterval, the scan interval, defaulting to 10000 ms (10 sec.)

use utf8;
use strict;
use warnings;

use Data::Dumper;
use Encode qw( decode );
use File::Find;
use Getopt::Long;
use JSON;

use TTP;
use vars::global qw( $ep );

use TTP::Constants qw( :all );
use TTP::JSONable;
use TTP::Message qw( :all );
use TTP::RunnerDaemon;

my $daemon = TTP::RunnerDaemon->bootstrap();

use constant {
	MIN_WORKER_INTERVAL => 1000,
	DEFAULT_WORKER_INTERVAL => 10000
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
# Returns the configured 'actions': the list of actions

sub configActions {
	my $config = $daemon->jsonData();
	my $actions = $config->{actions} || [];
	return $actions;
}

# -------------------------------------------------------------------------------------------------
# Returns the configured 'monitoredDir' defaulting to alertsFileDropdir

sub configMonitoredDir {
	my $config = $daemon->jsonData();
	my $dir = $config->{monitoredDir};
	$dir = TTP::alertsFileDropdir() if !$dir;
	return $dir;
}

# -------------------------------------------------------------------------------------------------
# Returns the configured 'monitoredFiles' regulater expression, defaulting to all

sub configMonitoredFiles {
	my $config = $daemon->jsonData();
	my $re = $config->{monitoredFiles};
	$re = "^.*\$" if !$re;
	return $re;
}

# -------------------------------------------------------------------------------------------------
# Returns the configured 'workerInterval' (in sec.) defaulting to DEFAULT_WORKER_INTERVAL

sub configWorkerInterval {
	my $config = $daemon->jsonData();
	my $interval = $config->{workerInterval};
	$interval = DEFAULT_WORKER_INTERVAL if !defined $interval;
	if( $interval < MIN_WORKER_INTERVAL ){
		msgVerbose( "defined workerInterval=$interval less than minimum accepted ".MIN_WORKER_INTERVAL.", ignored" );
		$interval = DEFAULT_WORKER_INTERVAL;
	}

	return $interval;
}

# -------------------------------------------------------------------------------------------------
# new alert

sub doWithNew {
	my ( @newFiles ) = @_;
	my $actions = configActions();

	foreach my $file ( @newFiles ){
		msgVerbose( "considering $file" );
		my $data = TTP::jsonRead( $file );
		if( !$data ){
			next;
		}
		# incremente our stats
		$stats->{byLevel}{$data->{level}} = 0 if !defined $stats->{byLevel}{$data->{level}};
		$stats->{byLevel}{$data->{level}} += 1;
		$stats->{byEmitter}{$data->{emitter}} = 0 if !defined $stats->{byEmitter}{$data->{emitter}};
		$stats->{byEmitter}{$data->{emitter}} += 1;
		# tries to execute all defined actions
		foreach my $do ( @{$actions} ){
			my $jsonable = TTP::JSONable->new( $ep, $do );
			my $commands = TTP::commandByOS([], { jsonable => $jsonable });
			if( $commands && scalar( @{$commands} )){
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
					my $res = TTP::commandExec( $commands, {
						macros => {
							LEVEL => $data->{level},
							EMITTER => $data->{emitter},
							TITLE => $data->{title},
							MESSAGE => $data->{message},
							STAMP => $data->{stamp},
							JSON => encode_json( $data ),
							FILEPATH => $file
						}
					});
					#print "result: ".Dumper( $res );
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
	}, {
		topic => "$topic/monitoredFiles",
		payload => ''
	}, {
		topic => "$topic/workerInterval",
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
	}, {
		topic => "$topic/monitoredFiles",
		payload => configMonitoredFiles()
	}, {
		topic => "$topic/workerInterval",
		payload => configWorkerInterval()
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
# do its work, i.e. detects new files in monitoredDir
# Note that the find() function sends errors to stderr when directory doesn't exist
#
# According to https://perldoc.perl.org/File::Find
#   $File::Find::dir is the current directory name,
#   $_ is the current filename within that directory
#   $File::Find::name is the complete pathname to the file.

sub worker {
	@runningScan = ();
	my $dir = configMonitoredDir();
	my $re = configMonitoredFiles();

	find({
		# receive here all found files in the searched directories
		wanted => sub {
			# this is a design decision to NOT recurse into subdirectories.
			if( $File::Find::dir ne $dir ){
                $File::Find::prune = 1;  # skip this directory and its children
                return;
            }
			# only consider matching files
			my $fname = decode( 'UTF-8', $File::Find::name );
			if( $_ =~ m/$re/ ){
				msgVerbose( "$_ matches, pushing $fname" );
				push( @runningScan, $fname );
			} else {
				#msgVerbose( "$_ doesn't match" );
			}
		},
		# caution: according to ChatGPT, this option is expected to protect against some chdir side effects - but it has itself the side effect that $_ becomes a full path
		# so we prefer do not use it
        #no_chdir => true
	}, $dir );

	if( scalar @runningScan < scalar @previousScan ){
		varReset();
	} elsif( $first ){
		$first = false;
		@previousScan = sort @runningScan;
	} elsif( scalar @runningScan > scalar @previousScan ){
		my @sorted = sort @runningScan;
		my @newFiles = ();
		my $i = 0;
		my $j = 0;
		while( $i < scalar( @sorted ) && $j < scalar( @previousScan )){
			if( $sorted[$i] eq $previousScan[$j] ){
				$i += 1;
				$j += 1;
			} elsif( $sorted[$i] lt $previousScan[$j] ){
				push( @newFiles, $sorted[$i] );
				$i += 1;
			} else {
				# a file is present in prfeviousScan and not in runningScan: has disappeared
				$j += 1;
			}
		}
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
	$daemon->displayHelp( $defaults );
	TTP::exit();
}

msgVerbose( "got colored='".( $daemon->colored() ? 'true':'false' )."'" );
msgVerbose( "got dummy='".( $daemon->dummy() ? 'true':'false' )."'" );
msgVerbose( "got verbose='".( $daemon->verbose() ? 'true':'false' )."'" );
msgVerbose( "got json='$opt_json'" );
msgVerbose( "got ignoreInt='".( $opt_ignoreInt ? 'true':'false' )."'" );

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
