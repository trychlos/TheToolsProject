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
# Message management.
#
# msgDummy
# msgErr
# msgOut
# msgVerbose
# msgWarn
#	are all functions provided to print a message on the console
#	They all default to also be logged, though this behavior may be disabled in toops/host configuration in key Message/msgOut/withLog
#	They all default to be colorable unless otherwise specified in the command-line (verbs are expected to handle this option)
#	This behavior can too be disabled in toops/host configuration in key Message/msgOut/withColor
#
# msgLog
#	in contrary just add a line to TTP/main.log

package TTP::Message;

use strict;
use utf8;
use warnings;

use Config;
use Data::Dumper;
use Path::Tiny qw( path );
use Sub::Exporter;
use Term::ANSIColor;
use vars::global qw( $ep );
use if $Config{osname} eq "MSWin32", "Win32::Console::ANSI";

use TTP;
use TTP::Constants qw( :all );
use TTP::Path;

Sub::Exporter::setup_exporter({
	exports => [ qw(
		EMERG
		ALERT
		CRIT
		ERR
		WARN
		NOTICE
		INFO
		DEBUG
		DUMMY
		VERBOSE
		
		msgDummy
		msgErr
		msgLog
		msgOut
		msgVerbose
		msgWarn
	)]
});

use constant {
	ALERT => 'ALERT',
	CRIT => 'CRIT',
	DEBUG => 'DEBUG',
	DUMMY => 'DUMMY',
	EMERG => 'EMERG',
	ERR => 'ERR',
	INFO => 'INFO',
	NOTICE => 'NOTICE',
	VERBOSE => 'VERBOSE',
	WARN => 'WARN'
};

# colors from https://metacpan.org/pod/Term::ANSIColor
my $Const = {
	ALERT => {
	},
	CRIT => {
	},
	DEBUG => {
	},
	DUMMY => {
		color => "cyan",
		marker => "(DUM) ",
		level => INFO,
		key => 'msgDummy'
	},
	EMERG => {
	},
	ERR => {
		color => "bold red",
		marker => "(ERR) ",
		key => 'msgErr'
	},
	INFO => {
		key => 'msgOut'
	},
	NOTICE => {
	},
	VERBOSE => {
		color => "bright_blue",
		marker => "(VER) ",
		level => INFO,
		key => 'msgVerbose'
	},
	WARN => {
		color => "bright_yellow",
		marker => "(WAR) ",
		key => 'msgWarn'
	}
};

my $Order = [
	EMERG,
	ALERT,
	CRIT,
	ERR,
	WARN,
	NOTICE,
	INFO,
	DEBUG
];

# make sure colors are resetted after end of line
$Term::ANSIColor::EACHLINE = EOL;

# -------------------------------------------------------------------------------------------------
# whether a user-provided level is known - level is case insensitive
# (I):
# - a level string
# (O):
# - true|false

sub isKnownLevel {
	my ( $level ) = @_;
	my $res = grep( /$level/i, keys %{$Const} );
	return $res;
}

# -------------------------------------------------------------------------------------------------
# returns the ordered list of known levels, maybe with their aliases
# (I):
# - (none)
# (O):
# - the list as a reference to an array where each item can be either a string or an array of strings

sub knownLevels {
	my $levels = {};
	# get all defined aliases
	foreach my $level( sort keys %{$Const} ){
		if( defined( $Const->{$level}{level} )){
			$levels->{$Const->{$level}{level}} = [] if !defined $levels->{$Const->{$level}{level}};
			push( @{$levels->{$Const->{$level}{level}}}, $level );
		} else {
			$levels->{$level} = [] if !defined $levels->{$level};
		}
	}
	# build an array of strings or of array of strings
	my $result = [];
	foreach my $level( @{$Order} ){
		if( scalar( @{$levels->{$level}} ) > 0 ){
			push( @{$result}, [ $level, @{$levels->{$level}} ]);
		} else {
			push( @{$result}, $level );
		}
	}
	return $result;
}

# -------------------------------------------------------------------------------------------------
# dummy message
# (I):
# - the message to be printed (usually the command to be run in dummy mode)

sub msgDummy {
	my $running = $ep->runner();
	if( $running && $running->dummy()){
		_printMsg({
			msg => shift,
			level => DUMMY,
			withPrefix => false
		});
	}
	return true;
}

# -------------------------------------------------------------------------------------------------
# Error message (should always be logged event if TTP let the site integrator disable that)
# (I):
# - the message to be printed on STDERR
# - an optional options hash with following keys:
#   > incErr: whether increment the errors count, defaulting to true
# (O):
# - increments the exit code

sub msgErr {
	my ( $msg, $opts ) = @_;
	$opts //= {};
	if( defined( $ep )){
		# let have a stack trace
		#TTP::stackTrace();
		# and send the message
		_printMsg({
			msg => $msg,
			level => ERR,
			handle => \*STDERR
		});
		my $running = $ep->runner();
		my $increment = true;
		$increment = $opts->{incErr} if exists $opts->{incErr};
		$running->runnableErrInc() if $running and $increment;
	}
}

# -------------------------------------------------------------------------------------------------
# prefix and log a message
# (I):
# - the message(s) to be written in TTP/main.log
#   may be a scalar (a string) or an array ref of scalars
# - an optional options hash with following keys:
#   > logFile: the path to the log file to be appended

sub msgLog {
	my ( $msg, $opts ) = @_;
	$opts //= {};
	my $ref = ref( $msg );
	if( $ref eq 'ARRAY' ){
		foreach my $line ( split( /[\r\n]/, @{$msg} )){
			chomp $line;
			msgLog( $line );
		}
	} elsif( !$ref ){
		_msgLogAppend( _msgPrefix().$msg, $opts );
	} else {
		msgWarn( "Message::msgLog() unmanaged type '$ref' for '$msg'" );
		TTP::stackTrace();
	}
}

# -------------------------------------------------------------------------------------------------
# log an already prefixed message
# do not try to write in logs while they are not initialized
# the host config is silently reevaluated on each call to be sure we are writing in the logs of the day
# (I):
# - the message(s) to be written in TTP/main.log
#   may be a scalar (a string) or an array ref of scalars
# - an optional options hash with following keys:
#   > logFile: the path to the log file to be appended, defaulting to node or site 'logsMain'

sub _msgLogAppend {
	my ( $msg, $opts ) = @_;
	$opts //= {};
	my $logFile = $opts->{logFile} || TTP::logsMain();
	if( $logFile ){
		my $host = TTP::host() || '-';
		my $username = $ENV{LOGNAME} || $ENV{USER} || $ENV{USERNAME} || 'unknown'; #getpwuid( $< );
		my $line = Time::Moment->now->strftime( '%Y-%m-%d %H:%M:%S.%5N' )." $host $$ $username $msg";
		# make sure the directory exists
		my ( $vol, $dir, $f ) = File::Spec->splitpath( $logFile );
		my $logdir = File::Spec->catpath( $vol, $dir );
		TTP::Path::makeDirExist( $logdir, { allowVerbose => false });
		path( $logFile )->append_utf8( $line.EOL );
	}
}

# -------------------------------------------------------------------------------------------------
# standard message on stdout
# (I):
# - the message to be outputed

sub msgOut {
	_printMsg({
		msg => shift
	});
}

# -------------------------------------------------------------------------------------------------
# Compute the message prefix, including a trailing space

sub _msgPrefix {
	my $prefix = '';
	my $running = $ep->runner();
	if( $running ){
		my $command = $running->runnableBNameFull();
		if( $command ){
			my $qualifier = $running->runnableQualifier() || '';
			$prefix = "[$command";
			$prefix .= " $qualifier" if $qualifier;
			$prefix.= '] ';
		}
	}
	return $prefix;
}

# -------------------------------------------------------------------------------------------------
# Verbose message
# (I):
# - the message to be outputed

sub msgVerbose {
	my $msg = shift;
	# be verbose to console ?
	my $verbose = false;
	my $running = $ep->runner();
	$verbose = $running->verbose() if $running;
	_printMsg({
		msg => $msg,
		level => VERBOSE,
		withConsole => $verbose
	});
}

# -------------------------------------------------------------------------------------------------
# Warning message - always logged
# (E):
# - the single warning message

sub msgWarn {
	#TTP::stackTrace();
	_printMsg({
		msg => shift,
		level => WARN
	});
}

# -------------------------------------------------------------------------------------------------
# print a message to stdout, and log
# argument is a single hash with following keys:
# - msg: the single line to be printed, defaulting to ''
# - level: the requested message level, defaulting to INFO
# - handle, the output handle, defaulting to STDOUT
# - withConsole: whether to output to the console, defaulting to true
# - withPrefix: whether to output the "[command.pl verb]" prefix, defaulting to true

sub _printMsg {
	my ( $args ) = @_;
	if( defined(  $ep )){
		$args //= {};
		my $line = '';
		my $configured = undef;
		my $running = $ep->runner();
		# have a prefix ?
		my $withPrefix = true;
		$withPrefix = $args->{withPrefix} if exists $args->{withPrefix};
		$line .= _msgPrefix() if $withPrefix;
		# have a level marker ?
		my $level = INFO;
		$level = $args->{level} if exists $args->{level};
		my $marker = '';
		$marker = $Const->{$level}{marker} if exists $Const->{$level}{marker};
		$configured = undef;
		$configured = $ep->var([ 'Message',  $Const->{$level}{key}, 'marker' ]) if exists $Const->{$level}{key};
		$marker = $configured if defined $configured;
		$line .= $marker;
		$line .= $args->{msg} if exists $args->{msg};
		# writes in log ?
		my $withLog = true;
		$configured = undef;
		$configured = $ep->var([ 'Message',  $Const->{$level}{key}, 'withLog' ]) if exists $Const->{$level}{key};
		$withLog = $configured if defined $configured;
		_msgLogAppend( $line ) if $withLog;
		# output to the console ?
		my $withConsole = true;
		$withConsole = $args->{withConsole} if exists $args->{withConsole};
		if( $withConsole ){
			# print a colored line ?
			# global runtime option is only considered if not disabled in toops/host configuration
			my $withColor = true;
			$configured = undef;
			$configured = $ep->var([ 'Message',  $Const->{$level}{key}, 'withColor' ]) if exists $Const->{$level}{key};
			#print __PACKAGE__."::_printMsg() configured='".( defined $configured ? $configured : '(undef)' )."'".EOL if $level eq "VERBOSE";
			$withColor = $configured if defined $configured;
			$withColor = $running->colored() if $running && $running->coloredSet();
			my $colorstart = '';
			my $colorend = '';
			if( $withColor ){
				$colorstart = color( $Const->{$level}{color} ) if exists( $Const->{$level}{color} );
				$configured = undef;
				$configured = $ep->var([ 'Message',  $Const->{$level}{key}, 'color' ]) if exists $Const->{$level}{key};
				$colorstart = color( $configured ) if defined $configured;
				$colorend = color( 'reset' );
			}
			# print on which handle ?
			my $handle = \*STDOUT;
			$handle = $args->{handle} if exists $args->{handle};
			print $handle "$colorstart$line$colorend".EOL;
		}
	}
}

1;
