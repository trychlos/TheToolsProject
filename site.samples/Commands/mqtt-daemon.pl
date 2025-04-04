#!perl
#!/usr/bin/perl
# @(#) Connect to and monitor the published MQTT topics.
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --json=<filename>       the name of the JSON configuration file of this daemon [${json}]
# @(-) --[no]ignoreInt         ignore the (Ctrl+C) INT signal [${ignoreInt}]
# @(-) --[no]stdout            whether to print the found non-SYS topics on stdout [${stdout}]
# @(-) --[no]sys               whether to print the found SYS topics on stdout [${sys}]
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
# - topics: a HASH whose each key is a regular expression which is matched against the topics
#   and whose values are the behavior to have.

use utf8;
use strict;
use warnings;

use Data::Dumper;
use File::Spec;
use Getopt::Long;
use Time::Piece;

use TTP;
use TTP::Constants qw( :all );
use TTP::Daemon;
use TTP::Message qw( :all );
use TTP::MQTT;
use vars::global qw( $ep );

my $daemon = TTP::Daemon->init();

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	json => '',
	ignoreInt => 'no',
	stdout => 'no',
	sys => 'no'
};

my $opt_json = $defaults->{json};
my $opt_ignoreInt = false;
my $opt_stdout = undef;
my $opt_sys = undef;

my $commands = {
	#help => \&help,
};

# specific to this daemon
my $mqtt;
my $kept = {};
my $logFile;

# -------------------------------------------------------------------------------------------------
# some kept data are answered to some configured commands
# the input request is:
# - client socket
# - peer host, address and port
# - command
# - args

sub doCommand {
	my ( $req ) = @_;
	msgLog( "command='$req->{command}'" );
	my @answer = ();
	my $count = 0;
	foreach my $it ( keys %{$kept->{$req->{command}}} ){
		$count += 1;
		push( @answer, "$it $kept->{$req->{command}}{$it}" );
	}
	return $count ? join( "\n", @answer ) : '';
}

# -------------------------------------------------------------------------------------------------
# the received topic match a daemon configuration item
# known actions which can be executed on each message:
# - toLog: log the topic and its payload to a mqtt.log besides of TTP/main.log, defaulting to false
# - toStdout: display the topic and its payload on stdout, defaulting to false

sub doMatched {
	my ( $topic, $payload, $config ) = @_;
	# is a $SYS message ?
	my $isSYS = ( $topic =~ /^\$SYS/ );
	# whether to log the message
	my $toLog = false;
	$toLog = $config->{toLog} if exists $config->{toLog};
	msgLog( "$topic [$payload]", { logFile => $logFile }) if $toLog;
	# whether to print to stdout
	my $toStdout = false;
	$toStdout = $config->{toStdout} if exists $config->{toStdout};
	$toStdout = $opt_stdout if defined $opt_stdout && !$isSYS;
	$toStdout = $opt_sys if defined $opt_sys && $isSYS;
	print localtime->strftime( "%Y-%m-%d %H:%M:%S:" )." $topic $payload".EOL if $toStdout;
	# do we want keep and answer with the received data ?
	my $command = undef;
	$command = $config->{command} if exists $config->{command};
	if( $command ){
		$kept->{$command}{$topic} = $payload;
	}
}

# -------------------------------------------------------------------------------------------------
# setup the commands hash before the first listening loop

sub setCommands {
	foreach my $key ( keys %{$daemon->{config}{topics}} ){
		if( exists( $daemon->{config}{topics}{$key}{command} )){
			$commands->{$daemon->{config}{topics}{$key}{command}} = \&doCommand;
		}
	}
}

# -------------------------------------------------------------------------------------------------
# do its work, examining the MQTT queue

sub works {
	my ( $topic, $payload ) = @_;
	#print "$topic".EOL;
	foreach my $key ( keys %{$daemon->{config}{topics}} ){
		my $match = $topic =~ /$key/;
		#print "topic='$topic' key='$key' match=$match".EOL;
		if( $match ){
			doMatched( $topic, $payload, $daemon->{config}{topics}{$key} );
		}
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
	"stdout!"			=> \$opt_stdout,
	"sys!"				=> \$opt_sys )){

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
msgVerbose( "found stdout='".( defined $opt_stdout ? ( $opt_stdout ? 'true':'false' ) : '(undef)' )."'" );
msgVerbose( "found sys='".( defined $opt_sys ? ( $opt_sys ? 'true':'false' ) : '(undef)' )."'" );

msgErr( "'--json' option is mandatory, not specified" ) if !$opt_json;

if( !TTP::errs()){
	$daemon->setConfig({ json => $opt_json, ignoreInt => $opt_ignoreInt });
}
if( !TTP::errs()){
	$logFile = File::Spec->catfile( TTP::logsCommands(), $daemon->name().'.log' );
	$mqtt = TTP::MQTT::connect();
}
if( !TTP::errs()){
	$mqtt->subscribe( '#' => \&works, '$SYS/#' => \&works );
	setCommands();
}
if( TTP::errs()){
	TTP::exit();
}

$daemon->declareSleepables( $commands );
$daemon->sleepableDeclareFn( sub => sub { $mqtt->tick( $daemon->listeningInterval()); }, interval => $daemon->listeningInterval());
$daemon->sleepableStart();

TTP::MQTT::disconnect( $mqtt );
$daemon->terminate();
