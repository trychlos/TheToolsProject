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
die __PACKAGE__ . " must be loaded as TTP::Message\n" unless __PACKAGE__ eq 'TTP::Message';

use strict;
use utf8;
use warnings;
binmode( STDOUT, ':encoding(UTF-8)' );
binmode( STDERR, ':encoding(UTF-8)' );

use Config;
use Data::Dumper;
use Path::Tiny qw( path );
use Sub::Exporter;
use Term::ANSIColor;
use Time::Moment;
use if $Config{osname} eq 'MSWin32', "Win32::Console::ANSI";

use TTP;
use vars::global qw( $ep );

use TTP::Constants qw( :all );

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
		
		msgDebug
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
		color => "light_gray",
		marker => "(DBG)",
		key => 'msgDebug'
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
# debug message
# can be called very early, for example while a sh bootstrap
# (I):
# - the message to be printed
# (O):
# - the message is printed on STDERR until TTP::EP has been bootstrapped - is logged after that

my $_inside_debug_ = false;

sub msgDebug {
	my ( $msg ) = @_;
	return if $_inside_debug_;
	$_inside_debug_ = true;
	if( $ENV{TTP_DEBUG} ){
		if( $ep && $ep->bootstrapped()){
			msgLog( "$Const->{DEBUG}{marker} $msg" );
		} else {
			print STDERR "$Const->{DEBUG}{marker} $msg".EOL;
		}
	}
	$_inside_debug_ = false;
}

# -------------------------------------------------------------------------------------------------
# dummy message
# (I):
# - the message to be printed (usually the command to be run in dummy mode)
# - an optional options hash with following keys:
#   > withLog: whether to (try to) log the message, defaulting to true
# (O):
# - returns true to simulate a successful operation

sub msgDummy {
	msgDebug( __PACKAGE__."::msgDummy() ".TTP::chompDumper( @_ ));
	my ( $msg, $opts ) = @_;
	$opts //= {};
	my $withLog = true;
	$withLog = $opts->{withLog} if defined $opts->{withLog};
	if( $ep && $ep->runner() && $ep->runner()->dummy()){
		_printMsg({
			msg => $msg,
			level => DUMMY,
			withLog => $withLog
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
#   > withLog: whether to (try to) log the message, defaulting to true
# (O):
# - increments the exit code

sub msgErr {
	msgDebug( __PACKAGE__."::msgErr() ".TTP::chompDumper( @_ ));
	my ( $msg, $opts ) = @_;
	$opts //= {};
	my $ref = ref( $msg );
	if( $ref eq 'ARRAY' ){
		foreach my $it ( @{$msg} ){
			msgErr( $it, $opts );
		}
	} elsif( !$ref ){
		my $withLog = true;
		$withLog = $opts->{withLog} if defined $opts->{withLog};
		_printMsg({
			msg => $msg,
			level => ERR,
			handle => \*STDERR,
			withLog => $withLog
		});
	} else {
		msgErr( __PACKAGE__."::msgErr() unmanaged type '$ref' for '$msg'" );
		TTP::stackTrace();
	}
	my $increment = true;
	$increment = $opts->{incErr} if defined $opts->{incErr};
	$ep->runner()->runnableErrInc() if $ep && $ep->runner() and $increment;
}

# -------------------------------------------------------------------------------------------------
# prefix and log a message
# (I):
# - the message(s) to be written in TTP/main.log
#   may be a scalar (a string) or an array ref of scalars
# - an optional options hash with following keys:
#   > logFile: the path to the log file to be appended

sub msgLog {
	msgDebug( __PACKAGE__."::msgLog() ".TTP::chompDumper( @_ ));
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
		msgErr( __PACKAGE__."::msgLog() unmanaged type '$ref' for '$msg'" );
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
	if( $ep && $ep->bootstrapped()){
		require TTP::Path;
		$opts //= {};
		my $logFile = $opts->{logFile} || TTP::logsMain();
		msgDebug( __PACKAGE__."::_msgLogAppend() msg='$msg' opts=".TTP::chompDumper( $opts )." logFile=".( $logFile ? "'$logFile'" : '(undef)' ));
		if( $logFile ){
			my $host = TTP::nodeName() || '-';
			my $username = $ENV{LOGNAME} || $ENV{USER} || $ENV{USERNAME} || 'unknown'; #getpwuid( $< );
			my $line = Time::Moment->now->strftime( '%Y-%m-%d %H:%M:%S.%6N %:z' )." $host $$ $username $msg";
			# make sure the directory exists
			my ( $vol, $dir, $f ) = File::Spec->splitpath( $logFile );
			my $logdir = File::Spec->catpath( $vol, $dir );
			TTP::Path::makeDirExist( $logdir, { verbose => false });
			path( $logFile )->append_utf8( $line.EOL );
		}
	}
}

# -------------------------------------------------------------------------------------------------
# standard message on stdout
# (I):
# - the message to be outputed
# - an optional options hash with following keys:
#   > withLog: whether to (try to) log the message, defaulting to true
#   > withPrefix: whether to display the standard prefix, defaulting to true
#   > withEol: whether to append an end-of-line, defaulting to true

sub msgOut {
	msgDebug( __PACKAGE__."::msgOut() ".TTP::chompDumper( @_ ));
	my ( $msg, $opts ) = @_;
	$opts //= {};
	my $ref = ref( $msg );
	if( $ref eq 'ARRAY' ){
		foreach my $it ( @{$msg} ){
			msgOut( $it, $opts );
		}
	} elsif( !$ref ){
		my $withLog = true;
		$withLog = $opts->{withLog} if defined $opts->{withLog};
		my $withPrefix = true;
		$withPrefix = $opts->{withPrefix} if defined $opts->{withPrefix};
		my $withEol = true;
		$withEol = $opts->{withEol} if defined $opts->{withEol};
		_printMsg({
			msg => $msg,
			withLog => $withLog,
			withPrefix => $withPrefix,
			withEol => $withEol
		});
	} else {
		msgErr( __PACKAGE__."::msgOut() unmanaged type '$ref' for '$msg'" );
		TTP::stackTrace();
	}
}

# -------------------------------------------------------------------------------------------------
# Compute the message prefix, including a trailing space

sub _msgPrefix {
	my $prefix = '';
	if( $ep && $ep->runner()){
		$prefix .= "[".join( ' ', @{$ep->runner()->runnableQualifiers()} )."] ";
	}
	return $prefix;
}

# -------------------------------------------------------------------------------------------------
# Verbose message
# (I):
# - the message to be outputed
# - an optional options hash with following keys:
#   > withLog: whether to (try to) log the message, defaulting to true

sub msgVerbose {
	msgDebug( __PACKAGE__."::msgVerbose() ".TTP::chompDumper( @_ ));
	my ( $msg, $opts ) = @_;
	$opts //= {};
	my $ref = ref( $msg );
	if( $ref eq 'ARRAY' ){
		foreach my $it ( @{$msg} ){
			msgVerbose( $it, $opts );
		}
	} elsif( !$ref ){
		my $withLog = true;
		$withLog = $opts->{withLog} if defined $opts->{withLog};
		# be verbose to console ?
		my $verbose = false;
		$verbose = $ep->runner()->verbose() if $ep && $ep->runner();
		_printMsg({
			msg => $msg,
			level => VERBOSE,
			withConsole => $verbose,
			withLog => $withLog
		});
	} else {
		msgErr( __PACKAGE__."::msgVerbose() unmanaged type '$ref' for '$msg'" );
		TTP::stackTrace();
	}
}

# -------------------------------------------------------------------------------------------------
# Warning message - always logged
# (E):
# - the single warning message
# - an optional options hash with following keys:
#   > withLog: whether to (try to) log the message, defaulting to true

sub msgWarn {
	msgDebug( __PACKAGE__."::msgWarn() ".TTP::chompDumper( @_ ));
	my ( $msg, $opts ) = @_;
	$opts //= {};
	my $ref = ref( $msg );
	if( $ref eq 'ARRAY' ){
		foreach my $it ( @{$msg} ){
			msgWarn( $it, $opts );
		}
	} elsif( !$ref ){
		my $withLog = true;
		$withLog = $opts->{withLog} if defined $opts->{withLog};
		_printMsg({
			msg => shift,
			level => WARN,
			withLog => $withLog
		});
	} else {
		msgErr( __PACKAGE__."::msgWarn() unmanaged type '$ref' for '$msg'" );
		TTP::stackTrace();
	}
}

# -------------------------------------------------------------------------------------------------
# print a message to stdout, and log
# argument is a single hash with following keys:
# - msg: the single line to be printed, defaulting to ''
# - level: the requested message level, defaulting to INFO
# - handle, the output handle, defaulting to STDOUT
# - withConsole: whether to output to the console, defaulting to true
# - withPrefix: whether to output the "[command.pl verb]" prefix, defaulting to true
# - withLog: whether to log the message, defaulting to true
# - withEol: whether to append an end-of-line, defaulting to true

sub _printMsg {
	msgDebug( __PACKAGE__."::_printMsg() ".TTP::chompDumper( @_ ));
	my ( $args ) = @_;
	if( defined( $ep )){
		$args //= {};
		my $line = '';
		my $configured = undef;
		# have a prefix ?
		my $withPrefix = true;
		$withPrefix = $args->{withPrefix} if defined $args->{withPrefix};
		$line .= _msgPrefix() if $withPrefix;
		# have a level marker ?
		# the computed one can be empty, but never undef
		my $level = INFO;
		$level = $args->{level} if defined $args->{level};
		$line .= _printMsg_marker( $level );
		$line .= $args->{msg} if defined $args->{msg};
		# writes in log ?
		# the computed one defaults to (hardcoded) true which hopefully covers all non-particular cases
		my $withLog = true;
		$withLog = $args->{withLog} if defined $args->{withLog};
		_msgLogAppend( $line ) if $withLog && _printMsg_withLog( $level );
		# output to the console ?
		my $withConsole = true;
		$withConsole = $args->{withConsole} if defined $args->{withConsole};
		if( $withConsole ){
			# print a colored line ?
			# global runtime option is only considered if not disabled in toops/host configuration
			my $withColor = _printMsg_withColor( $level );
			my $color = $withColor ?  _printMsg_color( $level ) : '';
			my $colorstart = '';
			my $colorend = '';
			if( $withColor && $color ){
				$colorstart = color( $color );
				$colorend = color( 'reset' );
			}
			# print on which handle ?
			my $handle = \*STDOUT;
			$handle = $args->{handle} if defined $args->{handle};
			# have an end-of-line ?
			my $withEol = true;
			$withEol = $args->{withEol} if defined $args->{withEol};
			print $handle "$colorstart$line$colorend";
			print $handle EOL if $withEol;
		}
	}
}

# -------------------------------------------------------------------------------------------------
# computes the marker of the message depending of the current level and of the site/node configuration
# As a particular case, we emit the deprecation warning only once to not clutter the user.
# - returns the color or an empty string

sub _printMsg_color {
	my ( $level ) = @_;
	my $color = '';
	if( $Const->{$level}{key} ){
		$color = $ep->var([ 'messages', $Const->{$level}{key}, 'color' ]) || '';
		if( !$color ){
			$color = $ep->var([ 'Message', $Const->{$level}{key}, 'color' ]) || '';
			if( $color && $ep->boostrapped() && !$ep->{_warnings}{message} && !$ENV{ttp_me} ){
				msgWarn( "'Message' property is deprecated in favor of 'messages'. You should update your configurations." );
				$ep->{_warnings}{message} = true;
			}
		}
	}
	if( !$color ){
		$color = $Const->{$level}{color} if defined $Const->{$level}{color};
	}
	return $color;
}

# -------------------------------------------------------------------------------------------------
# computes the marker of the message depending of the current level and of the site/node configuration
# As a particular case, we emit the deprecation warning only once to not clutter the user.
# - returns the marker or an empty string

sub _printMsg_marker {
	my ( $level ) = @_;
	my $marker = '';
	if( $Const->{$level}{key} ){
		$marker = $ep->var([ 'messages', $Const->{$level}{key}, 'marker' ]) || '';
		if( !$marker ){
			$marker = $ep->var([ 'Message', $Const->{$level}{key}, 'marker' ]) || '';
			if( $marker && $ep->boostrapped() && !$ep->{_warnings}{message} && !$ENV{ttp_me} ){
				msgWarn( "'Message' property is deprecated in favor of 'messages'. You should update your configurations." );
				$ep->{_warnings}{message} = true;
			}
		}
	}
	if( !$marker ){
		$marker = $Const->{$level}{marker} if defined $Const->{$level}{marker};
	}
	return $marker;
}

# -------------------------------------------------------------------------------------------------
# computes whether the current message should be colored depending of the current level and of the
#  site/node configuration
# As a particular case, we emit the deprecation warning only once to not clutter the user.
# - returns whether to write in log file, defaulting to (hardcoded) true

sub _printMsg_withColor {
	my ( $level ) = @_;
	my $withColor = true;
	if( $ep && $ep->runner() && $ep->runner()->coloredSet()){
		$withColor = $ep->runner()->colored();
	} elsif( $Const->{$level}{key} ){
		my $value = $ep->var([ 'messages', $Const->{$level}{key}, 'withColor' ]);
		if( !defined $value ){
			$value = $ep->var([ 'Message', $Const->{$level}{key}, 'withColor' ]);
			if( defined $value && $ep->boostrapped() && !$ep->{_warnings}{message} && !$ENV{ttp_me} ){
				msgWarn( "'Message' property is deprecated in favor of 'messages'. You should update your configurations." );
				$ep->{_warnings}{message} = true;
			}
		}
		$withColor = $value if defined $value;
	}
	return $withColor;
}

# -------------------------------------------------------------------------------------------------
# computes whether the current message should be written in log file depending of the current level
#  and of the site/node configuration
# As a particular case, we emit the deprecation warning only once to not clutter the user.
# - returns whether to write in log file, defaulting to (hardcoded) true

sub _printMsg_withLog {
	my ( $level ) = @_;
	my $withLog = true;
	if( $Const->{$level}{key} ){
		my $value = $ep->var([ 'messages', $Const->{$level}{key}, 'withLog' ]);
		if( !defined $value ){
			$value = $ep->var([ 'Message', $Const->{$level}{key}, 'withLog' ]);
			if( defined $value && $ep->boostrapped() && !$ep->{_warnings}{message} && !$ENV{ttp_me} ){
				msgWarn( "'Message' property is deprecated in favor of 'messages'. You should update your configurations." );
				$ep->{_warnings}{message} = true;
			}
		}
		$withLog = $value if defined $value;
	}
	return $withLog;
}

1;
