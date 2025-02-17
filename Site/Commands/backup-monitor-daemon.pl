#!perl
#!/usr/bin/perl
# @(#) Monitor the backups done in the (remote) live production.
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --json=<filename>       the name of the JSON configuration file of this daemon [${json}]
# @(-) --[no]ignoreInt         ignore the (Ctrl+C) INT signal [${ignoreInt}]
# @(-) --remote=<host>         remote host to be monitored [${remote}]
#
# @(@) Rationale:
# @(@) - the production "live" machine does its backup periodically, and doesn't care of anything else (it is not cooperative)
# @(@) - it is to the production "backup" machine to monitor the backups, transfert the files througgh the network, and restore them on its dataserver;
# @(@)   as it is expected to be just in waiting state, and so without anything else to do, it has this job.
# @(@) Automatic restores, a full in the morning, and diff's every 2h during the day, let us be relatively sure that it will be easily made ready in case
# @(@) the live stops.
# @(@)
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
# - monitoredService: the monitored service, mandatory
# - localDir: the directory of the current node into which remote found backup files must be copied, mandatory
# - scanInterval, the scan interval, defaulting to 10000 ms (10 sec.)
#
# It is also suggested to set the 'messagingTimeout' value to a timeout large enough to handle the potential timeouts when
# publishing HTTP telemetries. Say, for example, something like 60 sec. tiemout per telemetry.
#
# Known macros here are:
# - REMOTEHOST
# - REMOTESHARE

use utf8;
use strict;
use warnings;

use Data::Dumper;
use File::Copy;
use File::Find;
use File::Spec;
use File::stat;
use Getopt::Long;
use Time::Piece;

use TTP;
use TTP::Constants qw( :all );
use TTP::Daemon;
use TTP::Message qw( :all );
use TTP::Reporter;
use TTP::Service;
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
	ignoreInt => 'no',
	remote => ''
};

my $opt_json = $defaults->{json};
my $opt_ignoreInt = false;
my $opt_remote = $defaults->{remote};

my $commands = {
	stats => \&answerStats,
	status => \&answerStatus,
};

# scanning for new elements
my $first = true;
my @previousScan = ();
my @runningScan = ();

# store here the last found full database backup
my $full = {};

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
	$answer .= "last scan contained [".join( ',', @previousScan )."]".EOL;
	return $answer;
}

# -------------------------------------------------------------------------------------------------
# add to the standard 'status' answer our own data (remote host and dir)
sub answerStatus {

	my ( $req ) = @_;
	my $answer = TTP::Daemon->commonCommands()->{status}( $req, $commands );
	$answer .= "monitoredHost: ".$daemon->{monitoredNode}->name().EOL;
	$answer .= "monitoredExecReportsDir: ".computeMonitoredShare().EOL;
	return $answer;
}

# -------------------------------------------------------------------------------------------------
sub computeMacrosRec {
	my ( $var ) = @_;
	my $result = $var;
	my $ref = ref( $var );
	if( $ref eq 'HASH' ){
		$result = {};
		foreach my $key ( keys %{$var} ){
			$result->{$key} = computeMacrosRec( $var->{$key} );
		}
	} elsif( $ref eq 'ARRAY' ){
		$result = [];
		foreach my $it ( @{$var} ){
			push( @{$result}, computeMacrosRec( $it ));
		}
	} elsif( !$ref ){
		my $remoteShare = configRemoteShare();
		$result =~ s/<REMOTEHOST>/$opt_remote/g;
		$result =~ s/<REMOTESHARE>/$remoteShare/g;
	}
	#msgVerbose( "var='$var' ref='$ref' result='$result'" );
	return $result;
}

# -------------------------------------------------------------------------------------------------
# Returns the computed monitored databases list as an array ref

sub computeMonitoredDatabases {
	return $daemon->{monitoredService}->var([ 'DBMS', 'databases' ], $daemon->{monitoredNode} );
}

# -------------------------------------------------------------------------------------------------
# Returns the computed monitored DBMS instance name

sub computeMonitoredInstance {
	return $daemon->{monitoredService}->var([ 'DBMS', 'instance' ], $daemon->{monitoredNode} );
}

# -------------------------------------------------------------------------------------------------
# Returns the computed monitored share

sub computeMonitoredShare {
	my $dir = $ep->var([ 'executionReports', 'withFile', 'dropDir' ], { jsonable => $daemon->{monitoredNode} });
	msgErr( "unable to compute executionRepots.withFile.dropDir for remote $opt_remote" ) if !defined $dir;
	my( $local_vol, $local_dirs, $local_file ) = File::Spec->splitpath( $dir );
	my( $remote_vol, $no_dirs, $no_file ) = File::Spec->splitpath( configRemoteShare());
	my $share = File::Spec->catpath( $remote_vol, $local_dirs, $local_file );
	return $share;
}

# -------------------------------------------------------------------------------------------------
# Returns the computed restored DBMS instance name

sub computeRestoredInstance {
	return $daemon->{monitoredService}->var([ 'DBMS', 'instance' ]);
}

# -------------------------------------------------------------------------------------------------
# Returns the configured 'localDir', or undef
# the value is searched for in the 'config' hash which is the result of macros substitutions

sub configLocalDir {
	return $daemon->{config}{localDir};
}

# -------------------------------------------------------------------------------------------------
# Returns the configured 'monitoredService', or undef
# the value is searched for in the 'config' hash which is the result of macros substitutions

sub configMonitoredService {
	return $daemon->{config}{monitoredService};
}

# -------------------------------------------------------------------------------------------------
# Returns the configured 'remoteShare' from the remote host configuration

sub configRemoteShare {
	my $remoteShare = undef;
	my $node = $daemon->{monitoredNode};
	if( $node ){
		my $remoteConfig = $node->jsonData();
		if( $remoteConfig ){
			$remoteShare = $remoteConfig->{remoteShare};
		}
	}
	return $remoteShare;
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
# new execution reports
# we are tracking backup databases with dbms.pl backup -nodummy
# warning when we have a diff without a previous full

sub doWithNew {
	my ( @newFiles ) = @_;
	my $reporter = TTP::Reporter->new( $ep );
	my $monitoredInstance = computeMonitoredInstance();
	my $monitoredDatabases = computeMonitoredDatabases();
	#print "newFiles".EOL.Dumper( @runningScan );
	foreach my $report ( @newFiles ){
		$stats->{count} += 1;
		msgVerbose( "new report '$report'" );
		if( $reporter->jsonLoad({ path => $report })){
			my $data = $reporter->jsonData();
			if( exists( $data->{command} ) && $data->{command} eq "dbms.pl" && exists( $data->{verb} ) && $data->{verb} eq "backup" && ( !exists( $data->{dummy} ) || !$data->{dummy} )){

				my $instance = $data->{instance};
				if( $instance ne $monitoredInstance ){
					msgVerbose( "instance='$instance' ignored" );
					$stats->{ignored} += 1;
					next;
				}

				my $database = $data->{database};
				if( !grep ( /$database/, @{$monitoredDatabases} )){
					msgVerbose( "database='$database' ignored" );
					$stats->{ignored} += 1;
					next;
				}

				# have to make sure we have locally this file to be restored, plus maybe the last full backup
				# transfert the remote backup file to our backup host, getting the local backup file (from remote host) to be restored
				my $result = locallySyncedBackups( $data );
				if( $result ){
					# restore instance if the instance defined for this service in this host
					my $restoreInstance = computeRestoredInstance();
					my $command = "dbms.pl restore -nocolored -instance $restoreInstance -database $database ";
					$command .= " -full $result->{full}";
					$command .= " -diff $result->{diff}" if $result->{diff};
					# happens that dbms.pl restore may block in WS2012R2 when run from a daemon
					my $null = TTP::nullByOS();
					msgVerbose( "$command < $null" );
					my $res = TTP::filter( `$command < $null` );
					my $rc = $?;
					msgVerbose( join( '\n', @{$res} ).EOL );
				} else {
					msgWarn( "result is undefined, unable to restore" );
				}
			} else {
				msgVerbose( "$report: not a dbms.pl backup execution report" );
			}
		}
	}
}

# -------------------------------------------------------------------------------------------------
sub _execReport {
	my ( $report ) = @_;
	TTP::execReportAppend( $report );
	push( @{$stats->{restored}}, $report );
}

# -------------------------------------------------------------------------------------------------
# (I):
# - backup report to be restored
# (O):
# returns a hash with following keys:
# - full: always, the (local) full backup to be restored
# - diff: if set, the (local) diff backup to be restored
# or undef in case of an error

sub locallySyncedBackups {
	my ( $report ) = @_;
	my $result = undef;
	msgVerbose( "locallySyncedBackups() entering with instance='$report->{instance}' database='$report->{database}' mode='$report->{mode}' output='$report->{output}'" );

	my $localTarget = syncedPath( $report->{output} );
	return false if !$localTarget;

	# if we are about to restore a full backup, then we are finished here
	# else, in order to be able to restore a diff backup, we have to also got the last full
	# happens that there are lot of situations where we will not be able to keep in memory the last full backup of a database
	# the first of these being the case where the daemon is restarted after a full backup has occured.
	# it we do not do something, it will not be able to restore anything until another full backup pass here..
	if( $report->{mode} eq "full" ){
		$result = { full => $localTarget };
		$full->{$report->{instance}}{$report->{database}} = $localTarget;

	} else {
		$result = { diff => $localTarget };
		$result->{full} = undef;
		# we can search for the last full in the global 'full' hash which is expected to remember this sort of thing,
		# or in the localDir, or remotely by examining execReports dir...
		# -> first thing: do we remember the last full ?
		if( exists( $full->{$report->{instance}}{$report->{database}} )){
			$result->{full} = $full->{$report->{instance}}{$report->{database}};
			msgVerbose( "found last full as remembered '$full->{$report->{instance}}{$report->{database}}'" );
		} else {
			# -> second: try to search in the localDir, hoping that the file has the old-classic name
			my $lastfull = locallySearchLastFull( $report );
			if( $lastfull ){
				$full->{$report->{instance}}{$report->{database}} = $lastfull;
				$result->{full} = $lastfull;
				msgVerbose( "found last full as local '$lastfull'" );
			} else {
				# -> last chance it to scan remote execution reports
				$lastfull = remoteSearchLastFull( $report );
				if( $lastfull ){
					$full->{$report->{instance}}{$report->{database}} = $lastfull;
					$result->{full} = $lastfull;
					msgVerbose( "found remote last full, transferred to '$lastfull'" );
				}
			}
		}
	}

	return $result;
}

# -------------------------------------------------------------------------------------------------
# search locally for the last full backup
# Returns the path to the local backup if we have found it
my $_localdata = {};

sub locallySearchLastFull {
	my ( $report ) = @_;
	my $res = undef;
	# search locally, based on TTP configuration
	# hardcoding the expected format file name as host-instance-database ... -mode.backup
	# this should be enough in most situations
	my $dir = configLocalDir();
	msgVerbose( "searching for full backup in '$dir'" );
	$_localdata = {};
	$_localdata->{host} = $report->{host};
	$_localdata->{instance} = $report->{instance};
	$_localdata->{database} = $report->{database};
	$_localdata->{found} = [];
	find( \&locallySearchLastFull_wanted, $dir );
	if( scalar @{$_localdata->{found}} ){
		my @candidates = sort @{$_localdata->{found}};
		$res = pop( @candidates );
	}
	return $res;
}

sub locallySearchLastFull_wanted {
	return unless /^$_localdata->{host}-$_localdata->{instance}-$_localdata->{database}-[0-9]{6,6}-[0-9]{6,6}-full\.backup$/;
	push( @{$_localdata->{found}}, $File::Find::name );
}

# -------------------------------------------------------------------------------------------------
# On disconnection, try to erase the published topics

sub mqttDisconnect {
	my ( $daemon ) = @_;
	my $topic = $daemon->topic();
	my $array = [];
	push( @{$array}, {
		topic => "$topic/monitoredHost",
		payload => ''
	},{
		topic => "$topic/monitoredService",
		payload => ''
	},{
		topic => "$topic/localDir",
		payload => ''
	},{
		topic => "$topic/monitoredExecReportsDir",
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
		topic => "$topic/monitoredHost",
		payload => $opt_remote
	},{
		topic => "$topic/monitoredService",
		payload => configMonitoredService()
	},{
		topic => "$topic/localDir",
		payload => configLocalDir()
	},{
		topic => "$topic/monitoredExecReportsDir",
		payload => computeMonitoredShare()
	});
	return $array;
}

# -------------------------------------------------------------------------------------------------
# search for last full backup starting by scanning remote execution reports
# return the transferred last full if possible;
my $_remote = [];

sub remoteSearchLastFull {
	my ( $report ) = @_;
	my $res = undef;
	# get the remote execution reports
	my $dir = computeMonitoredShare();
	my $reporter = TTP::Reporter->new( $ep );
	find( \&remoteSearchLastFull_wanted, $dir );
	# sort in reverse name order (the most recent first)
	my @sorted = reverse sort @{$_remote};
	foreach my $json ( @sorted ){
		#print __PACKAGE__."::remoteSearchLastFull() json='$json'".EOL;
		if( $reporter->jsonLoad({ path => $json })){
			my $remote = $reporter->jsonData();
			if( $remote->{instance} eq $report->{instance} && $remote->{database} eq $report->{database} && $remote->{mode} eq 'full' && !$remote->{dummy} ){
				$res = syncedPath( $remote->{output} );
			}
		} else {
			msgErr( "unable to read the '$json' JSON file" );
		}
	}
	return $res;
}

sub remoteSearchLastFull_wanted {
	return unless /\.json$/;
	push( @{$_remote}, $File::Find::name );
}

# -------------------------------------------------------------------------------------------------
# source file is file on the source host, specified in the source language (aka a local path rather
#  than a network path).
# we want here:
# - copy the remote file on the local host
# - returns the local path, or undef in case of an error

sub syncedPath {
	my ( $localSource ) = @_;
	msgVerbose( "syncedPath() localSource='$localSource'" );
	# the output file is specified as a local filename on the remote host
	# we need to build a the remote filename (source of the copy) and the local filename (target of the copy)
	my( $ls_vol, $ls_dirs, $ls_file ) = File::Spec->splitpath( $localSource );
	my( $rs_vol, $rs_dirs, $rs_file ) = File::Spec->splitpath( computeMonitoredShare());
	my $remoteSource = File::Spec->catpath( $rs_vol, $ls_dirs, $ls_file );
	msgVerbose( "syncedPath() remoteSource='$remoteSource'" );
	# local target
	my $localTarget = configLocalDir();
	msgVerbose( "localTarget='$localTarget'" );
	TTP::makeDirExist( $localTarget );
	my $res = TTP::copyFile( $remoteSource, $localTarget );
	if( $res ){
		msgVerbose( "syncedPath() successfully copied '$remoteSource' to '$localTarget'" );
		$localTarget = File::Spec->catfile( $localTarget, $ls_file );
	} else {
		msgErr( "syncedPath() unable to copy '$remoteSource' to '$localTarget': $!" );
		$localTarget = undef;
	}
	return $localTarget;
}

# -------------------------------------------------------------------------------------------------
# we find less files in this iteration than in the previous - maybe some files have been purged, deleted
# moved, or we have a new directory, or another reason - just reset and restart over

sub varReset {
	msgVerbose( "varReset()" );
	@previousScan = ();
	$first = true;
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
# do its work
# because the directories we are monitoring here are typically backups/logs directories and their
# name may change every day

sub works {
	# recompute at each loop all dynamic variables
	# - reevaluate the remote host configuration
	$daemon->{monitoredNode}->evaluate();
	# - interpret macros in this daemon configuration:
	#   > REMOTESHARE
	#   > REMOTEHOST
	$daemon->{config} = $daemon->jsonData();
	$daemon->{config} = computeMacrosRec( $daemon->{config} );
	# monitored dir is the (maybe daily) remote host execReportsDir
	$daemon->{monitoredShare} = computeMonitoredShare();
	# and scan..
	@runningScan = ();
	find( \&wanted, $daemon->{monitoredShare} );
	if( scalar @runningScan < scalar @previousScan ){
		varReset();
	} elsif( $first ){
		$first = false;
		@previousScan = sort @runningScan;
	} elsif( scalar @runningScan > scalar @previousScan ){
		my $prevHash = {};
		foreach my $it ( @previousScan ){
			$prevHash->{$it} = true;
		}
		my $newFiles = [];
		foreach my $it ( @runningScan ){
			push( @{$newFiles}, $it ) if !exists $prevHash->{$it};
		}
		doWithNew( @{$newFiles} );
		@previousScan = @runningScan;
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
	"ignoreInt!"		=> \$opt_ignoreInt,
	"remote=s"			=> \$opt_remote )){

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
msgVerbose( "found remote='$opt_remote'" );

msgErr( "'--json' option is mandatory, not specified" ) if !$opt_json;
msgErr( "'--remote' option is mandatory, not specified" ) if !$opt_remote;

if( !TTP::errs()){
	$daemon->setConfig({ json => $opt_json, ignoreInt => $opt_ignoreInt });
}

# deeply check arguments
# - monitored host must have a json configuration file
# - the daemon configuration must have monitoredService and localDir keys
# stop here if we do not have any configuration for the remote host 
if( !TTP::errs()){
	$daemon->{config} = $daemon->jsonData();
	$daemon->{config} = computeMacrosRec( $daemon->{config} );
	$daemon->{monitoredNode} = TTP::Node->new( $ep, { node => $opt_remote });
	#print Dumper( $daemon );
}

# check configuration for mandatory keys
if( !TTP::errs()){
	my $remoteConfig = $daemon->{monitoredNode}->jsonData();
	# monitoredService is mandatory
	my $monitoredService = configMonitoredService();
	if( $monitoredService ){
		my $remoteService = $remoteConfig->{Services}{$monitoredService};
		if( $remoteService ){
			msgVerbose( "monitored service '$monitoredService' successfully found in remote host '$opt_remote' configuration file" );
			$daemon->{monitoredService} = TTP::Service->new( $ep, { service => $monitoredService });
			$daemon->metricLabelAppend( 'service', $monitoredService );
		} else {
			msgErr( "monitored service '$monitoredService' doesn't exist in remote host '$opt_remote' configuration file" );
		}
	} else {
		msgErr( "'monitoredService' key must be specified in daemon configuration, not found" );
	}
	# localDir is mandatory: the directory where found remote backups are to be copied
	my $localDir = configLocalDir();
	if( $localDir ){
		msgVerbose( "localDir='$localDir' successfully found in daemon configuration file" );
	} else {
		msgErr( "'localDir' key must be specified in daemon configuration, not found" );
	}
	# the remoteHost must exhibit a 'remoteShare' which is the share to which we can connect to
	if( exists( $remoteConfig->{remoteShare} )){
		msgVerbose( "found remoteShare='$remoteConfig->{remoteShare}'" );
	} else {
		msgErr( "'remoteShare' key must be specified in remote host '$opt_remote' configuration, not found" );
	}
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
