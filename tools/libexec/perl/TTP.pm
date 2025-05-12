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

package TTP;
die __PACKAGE__ . " must be loaded as TTP\n" unless __PACKAGE__ eq 'TTP';

use strict;
use utf8;
use warnings;

use Capture::Tiny qw( :all );
use Config;
use Data::Dumper;
use Data::UUID;
use Devel::StackTrace;
use File::Basename;
use File::Spec;
use JSON;
use open qw( :std :encoding(UTF-8));
use Path::Tiny qw( path );
use Scalar::Util qw( looks_like_number );
use Test::Deep;
use Time::Moment;
use vars::global create => qw( $ep );

use TTP::Constants qw( :all );
use TTP::EP;
use TTP::Message qw( :all );
use TTP::Node;
use TTP::Path;

# autoflush STDOUT
$| = 1;

# store here our TTP variables
my $Const = {
	# defaults which depend of the host OS provided by 'Config{osname}' package's value
	byOS => {
		darwin => {
			tempDir => '/tmp',
			null => '/dev/null'
		},
		linux => {
			tempDir => '/tmp',
			null => '/dev/null'
		},
		MSWin32 => {
			tempDir => 'C:\\Temp',
			null => 'NUL'
		}
	}
};

# -------------------------------------------------------------------------------------------------
# Returns the configured alertsDir (when alerts are sent by file), defaulting to tempDir()
# Deprecated in v4.1
# (I):
# - none
# (O):
# - returns the alertsdir

sub alertsDir {
	msgWarn( "TTP::alertsDir() is deprecated in favor of TTP:alertsFileDropdir(). You should update your code." );
	return TTP::alertsFileDropdir();
}

# -------------------------------------------------------------------------------------------------
# Returns the configured alertsDir (when alerts are sent by file), defaulting to tempDir()
# (I):
# - none
# (O):
# - returns the alertsdir

sub alertsFileDropdir {
	my $dir = $ep->var([ 'alerts', 'withFile', 'dropDir' ]) || File::Spec->catdir( TTP::tempDir(), 'TTP', 'alerts' );
	return $dir;
}

# -------------------------------------------------------------------------------------------------
# returns a Dumper of the data, without terminating end-of-line
# (I):
# - the data to be dumped
# (O):
# - the data as an expanded string

sub chompDumper {
	my ( $data ) = @_;
	my $str = Dumper( $data );
	$str =~ s/^\$VAR[0-9]+\s+=\s*//;
	chomp $str;
	return $str;
}

# -------------------------------------------------------------------------------------------------
# Read from configuration either a command as a string or as a byOS-command.
# We are searching for a 'command' property below the provided keys.
# This command may be a simple string or an object 'command.byOS.<OSname>'.
# (I):
# - the list of keys before the 'command' as an array ref
# - an optional options hash ref with following keys:
#   > withCommand: whether to have a top 'command' property before 'byOS', defaulting to false
#   > withCommands: whether to have a top 'commands' property before 'byOS', defaulting to false
#	  NB: must have one and only one of 'withCommand' and 'withCommands'!
#   > jsonable: a IJSONable to be searched for for the provided keys, defaulting to node/site data
# (O):
# - the found command as a string, or undef

sub commandByOS {
	my ( $keys, $opts ) = @_;
	$opts //= {};
	my $command = undef;
	my @locals = @{$keys};
	# have withCommand or withCommands ?
	my $withCommand = $opts->{withCommand};
	$withCommand = false if !defined $withCommand;
	my $withCommands = $opts->{withCommands};
	$withCommands = false if !defined( $withCommands );
	my $count = 0;
	$count += 1 if $withCommand;
	$count += 1 if $withCommands;
	if( $count == 0 ){
		msgErr( __PACKAGE__."::commandByOS() must have one of 'withCommand' or 'withCommands', found none" );
		TTP::stackTrace();
	} elsif( $count > 1 ){
		msgErr( __PACKAGE__."::commandByOS() must have one of 'withCommand' or 'withCommands', found both" );
		TTP::stackTrace();
	} else {
		push( @locals, 'command' ) if $withCommand;
		push( @locals, 'commands' ) if $withCommands;
		# search...
		my $obj = $ep->var( \@locals, $opts );
		if( defined( $obj )){
			my $ref = ref( $obj );
			# a single command: expects a command or a 'byOS' object
			if( $withCommand ){
				$command = commandByOS_getObject( \@locals, $obj, $opts );
			# several commands: expects an array here
			} elsif( $withCommands ){
				if( $ref eq 'ARRAY' ){
					$command = [];
					foreach my $it ( @{$obj} ){
						push( @{$command}, commandByOS_getObject( \@locals, $it, $opts ));
					}
				} else {
					msgErr( __PACKAGE__."::commandByOS() unexpected object found in [".join( ', ', @locals )."] configuration: $obj ($ref)." );
				}
			} else {
				msgErr( __PACKAGE__."::commandByOS() unexpected 'withCommand(s)' mode" );
				TTP::stackTrace();
			}
		} else {
			msgVerbose( __PACKAGE__."::commandByOS() nothing found at [ ".join( ', ', @locals )." ]" );
		}
	}
	return $command;
}

sub commandByOS_getObject {
	my ( $locals, $parent, $opts ) = @_;
	my $command = undef;
	my $ref = ref( $parent );
	if( $ref eq 'HASH' ){
		my @locals = @{$locals};
		push( @locals, 'byOS', $Config{osname} );
		my $obj = $ep->var( \@locals, $opts );
		if( defined( $obj )){
			$ref = ref( $obj );
			if( !$ref ){
				$command = $obj;
				msgVerbose( __PACKAGE__."::commandByOS() found command '$command' at [ ".join( ', ', @locals )." ]" );
			} else {
				msgErr( __PACKAGE__."::commandByOS() unexpected object found in [".join( ', ', @locals )."] configuration: $obj ($ref)." );
			}
		} else {
			msgWarn( __PACKAGE__."::commandByOS() nothing found at [ ".join( ', ', @locals )." ]" );
		}
	} else {
		$command = $parent;
	}
	return $command;
}

# -------------------------------------------------------------------------------------------------
# Execute an external command.
# The provided command is not modified at all. If it should support say --verbose or --[no]colored,
# then these options should be specified by the caller.
# (I):
# - the command to be evaluated and executed
# - an optional options hash with following keys:
#   > macros: a hash of the macros to be replaced where:
#     - key is the macro name, must be labeled in the toops.json as '<macro>' (i.e. between angle brackets)
#     - value is the replacement value
#   > stdinFromNull: whether stdin must be redirected from NULL, defaulting to true
# (O):
# returns a hash with following keys:
# - evaluated: the evaluated command after macros replacements
# - stdout: stdout as a reference to the array of lines
# - stderr: stderr as a reference to the array of lines
# - exit: original exit code of the command
# - success: true|false

sub commandExec {
	my ( $command, $opts ) = @_;
	$opts //= {};
	my $result = {
		stdout => [],
		stderr => [],
		exit => -1,
		success => false
	};
	if( !$command ){
		msgErr( __PACKAGE__."::commandExec() undefined command" );
		stackTrace();
	} else {
		msgVerbose( __PACKAGE__."::commandExec() got command='".( $command )."'" );
		my $stdinFromNull = true;
		$stdinFromNull = $opts->{stdinFromNull} if defined $opts->{stdinFromNull};
		if( $stdinFromNull ){
			$command .= " < ".TTP::nullByOS();
			msgVerbose( __PACKAGE__."::commandExec() rewritten to='".( $command )."'" );
		}
		$result->{evaluated} = $command;
		if( $opts->{macros} ){
			foreach my $key ( sort keys %{$opts->{macros}} ){
				my $value = $opts->{macros}{$key} || '';
				$result->{evaluated} =~ s/<$key>/$value/g;
			}
		}
		msgVerbose( __PACKAGE__."::commandExec() evaluated to '$result->{evaluated}'" );
		if( $ep->runner()->dummy()){
			msgDummy( $result->{evaluated} );
			$result->{success} = true;
		} else {
			# https://stackoverflow.com/questions/799968/whats-the-difference-between-perls-backticks-system-and-exec
			# as of v4.12 choose to use system() instead of backtits, this later not returning stderr
			my ( $res_out, $res_err, $res_code ) = capture { system( $result->{evaluated} ); };
			#print "code ".Dumper( $res_code );
			# https://www.perlmonks.org/?node_id=81640
			# Thus, the exit value of the subprocess is actually ($? >> 8), and $? & 127 gives which signal, if any, the
			# process died from, and $? & 128 reports whether there was a core dump.
			# https://ss64.com/nt/robocopy-exit.html
			$result->{exit} = $res_code;
			$result->{success} = ( $res_code == 0 ) ? true : false;
			msgVerbose( "TTP::commandExec() return_code=$res_code firstly interpreted as success=".( $result->{success} ? 'true' : 'false' ));
			if( $result->{evaluated} =~ /^\s*robocopy/i ){
				$res_code = ( $res_code >> 8 );
				$result->{success} = ( $res_code <= 7 ) ? true : false;
				msgVerbose( "TTP::commandExec() robocopy specific interpretation res=$res_code success=".( $result->{success} ? 'true' : 'false' ));
			}
			# stdout
			chomp $res_out;
			msgVerbose( "TTP::commandExec() stdout='$res_out'" );
			my @res_out = split( /[\r\n]/, $res_out );
			$result->{stdout} = \@res_out;
			# stderr
			chomp $res_err;
			msgVerbose( "TTP::commandExec() stderr='$res_err'" );
			my @res_err = split( /[\r\n]/, $res_err );
			$result->{stderr} = \@res_err;
		}
		msgVerbose( "TTP::commandExec() success=".( $result->{success} ? 'true' : 'false' ));
	}
	return $result;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'archives.periodicDir' directory, which may be undef very early in the bootstrap process
#   and at least not definitive while the node has not been instanciated/loaded/evaluated

sub dbmsArchivesPeriodic {
	return TTP::Path::dbmsArchivesPeriodic();
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'archives.rootDir' directory, which may be undef very early in the bootstrap process
#   and at least not definitive while the node has not been instanciated/loaded/evaluated

sub dbmsArchivesRoot {
	return TTP::Path::dbmsArchivesRoot();
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'backups.periodicDir' directory, which may be undef very early in the bootstrap process
#   and at least not definitive while the node has not been instanciated/loaded/evaluated

sub dbmsBackupsPeriodic {
	return TTP::Path::dbmsBackupsPeriodic();
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'backups.rootDir' directory, which may be undef very early in the bootstrap process
#   and at least not definitive while the node has not been instanciated/loaded/evaluated

sub dbmsBackupsRoot {
	return TTP::Path::dbmsBackupsRoot();
}

# -------------------------------------------------------------------------------------------------
# Display an array of hashes as a (sql-type) table
# (I):
# - an array of hashes, or an array of array of hashes if multiple result sets are provided
# - an optional options hash with following keys:
#   > display: a ref to an array of keys to be displayed
# (O):
# - print on stdout

sub displayTabular {
	my ( $result, $opts ) = @_;
	$opts //= {};
	my $displayable = $opts->{display};
	my $ref = ref( $result );
	# expects an array, else just give up
	if( $ref ne 'ARRAY' ){
		msgVerbose( __PACKAGE__."::displayTabular() expected an array, but found '$ref', so just give up" );
		return;
	}
	if( !scalar @{$result} ){
		msgVerbose( __PACKAGE__."::displayTabular() got an empty array, so just give up" );
		return;
	}
	# expects an array of hashes
	# if we got an array of arrays, then this is a multiple result sets and recurse
	$ref = ref( $result->[0] );
	if( $ref eq 'ARRAY' ){
		foreach my $set ( @{$result} ){
			displayTabular( $set, $opts );
		}
		return;
	}
	if( $ref ne 'HASH' ){
		msgVerbose( __PACKAGE__."::displayTabular() expected an array of hashes, but found an array of '$ref', so just give up" );
		return;
	}
	# first compute the max length of each field name + keep the same field order
	my $lengths = {};
	my @fields = ();
	foreach my $key ( sort keys %{@{$result}[0]} ){
		if( !$displayable || grep( /$key/, @{$displayable} )){
			push( @fields, $key );
			$lengths->{$key} = length $key;
		} else {
			msgVerbose( "key='$key' is not included among displayable fields [".join( ', ', @{$displayable} )."]" );
		}
	}
	# and for each field, compute the max length content
	my $haveWarned = false;
	foreach my $it ( @{$result} ){
		foreach my $key ( keys %{$it} ){
			if( !$displayable || grep( /$key/, @{$displayable} )){
				if( $lengths->{$key} ){
					if( defined $it->{$key} && length $it->{$key} > $lengths->{$key} ){
						$lengths->{$key} = length $it->{$key};
					}
				} elsif( !$haveWarned ){
					msgWarn( "found a row with different result set, do you have omit '--multiple' option ?" );
					$haveWarned = true;
				}
			}
		}
	}
	# and last display the full resulting array
	# have a carriage return to be aligned on line beginning in log files
	foreach my $key ( @fields ){
		print pad( "+", $lengths->{$key}+3, '-' );
	}
	print "+".EOL;
	foreach my $key ( @fields ){
		print pad( "| $key", $lengths->{$key}+3, ' ' );
	}
	print "|".EOL;
	foreach my $key ( @fields ){
		print pad( "+", $lengths->{$key}+3, '-' );
	}
	print "+".EOL;
	foreach my $it ( @{$result} ){
		foreach my $key ( @fields ){
			print pad( "| ".( defined $it->{$key} ? $it->{$key} : "" ), $lengths->{$key}+3, ' ' );
		}
		print "|".EOL;
	}
	foreach my $key ( @fields ){
		print pad( "+", $lengths->{$key}+3, '-' );
	}
	print "+".EOL;
}

# -------------------------------------------------------------------------------------------------
# Returns the current count of errors

sub errs {
	return $ep->runner()->runnableErrs() if $ep && $ep->runner();
	return 0;
}

# -------------------------------------------------------------------------------------------------
# report an execution
# The exact data, the target to report to and the used medium are up to the caller.
# But at the moment we manage a) a JSON execution report file and b) a MQTT message.
# This is a design decision to limit TTP to these medias because:
# - we do not want have here some code for each and every possible medium a caller may want use a day or another
# - as soon as we can have either a JSON file or a MQTT message, or even both of these medias, we can also have
#   any redirection from these medias to another one (e.g. scan the execution report JSON files and do something
#   when a new one is detected, or listen to the MQTT bus and subscribe to interesting topics, and so on...).
# Each medium is only evaluated if and only if:
# - the corresponding 'enabled' option is 'true' for the considered host
# - and the relevant options are provided by the caller. 
# (I):
# - A ref to a hash with following keys:
#   > file: a ref to a hash with following keys:
#     - data: a ref to a hash to be written as JSON execution report data
#   > mqtt: a ref to a hash with following keys:
#     - data: a ref to a hash to be written as MQTT payload (in JSON format)
#     - topic as a mandatory string
#     - options, as an optional string
# This function automatically appends:
# - hostname
# - start timestamp
# - end timestamp
# - exit code
# - full run command

sub executionReport {
	my ( $args ) = @_;
	# write JSON file if configuration enables that and relevant arguments are provided
	my $enabled = $ep->var([ 'executionReports', 'withFile', 'enabled' ]);
	$enabled = true if !defined $enabled;
	if( $enabled && $args->{file} ){
		_executionReportToFile( $args->{file} );
	}
	# publish MQTT message if configuration enables that and relevant arguments are provided
	$enabled = $ep->var([ 'executionReports', 'withMqtt', 'enabled' ]);
	$enabled = true if !defined $enabled;
	if( $enabled && $args->{mqtt} ){
		_executionReportToMqtt( $args->{mqtt} );
	}
}

# Complete the provided data with the data collected by TTP

sub _executionReportCompleteData {
	my ( $data ) = @_;
	$data->{cmdline} = "$0 ".join( ' ', @{$ep->runner()->runnableArgs()} );
	$data->{command} = $ep->runner()->command();
	$data->{verb} = $ep->runner()->verb();
	$data->{host} = $ep->node()->name();
	$data->{code} = $ep->runner()->runnableErrs();
	$data->{started} = $ep->runner()->runnableStarted()->strftime( '%Y-%m-%d %H:%M:%S.%6N %:z' );
	$data->{ended} = Time::Moment->now->strftime( '%Y-%m-%d %H:%M:%S.%6N %:z' );
	$data->{dummy} = $ep->runner()->dummy();
	return $data;
}

# write an execution report to a file
# the needed command is expected to be configured
# managed macros:
# - DATA
# (I):
# - a hash ref with following keys:
#   > data, a hash ref
# (O):
# - returns true|false

sub _executionReportToFile {
	my ( $args ) = @_;
	my $res = false;
	my $data = undef;
	$data = $args->{data} if defined $args->{data};
	if( defined $data ){
		$data = _executionReportCompleteData( $data );
		my $command = $ep->var([ 'executionReports', 'withFile', 'command' ]);
		if( $command ){
			my $json = JSON->new;
			my $str = $json->encode( $data );
			# protect the double quotes against the CMD.EXE command-line
			$str =~ s/"/\\"/g;
			$command =~ s/<DATA>/$str/;
			my $dummy = $ep->runner()->dummy() ? "-dummy" : "-nodummy";
			my $verbose = $ep->runner()->verbose() ? "-verbose" : "-noverbose";
			my $cmd = "$command -nocolored $dummy $verbose";
			msgOut( "executing '$cmd'" );
			my $result = TTP::commandExec( $cmd );
			$res = $result->{success};
		} else {
			msgErr( __PACKAGE__."::_executionReportToFile() expected a 'command' argument, not found" );
		}
	} else {
		msgErr( __PACKAGE__."::_executionReportToFile() expected a 'data' argument, not found" );
		TTP::stackTrace();
	}
	return $res;
}

# send an execution report on the MQTT bus if TTP is configured for
# managed macros:
# - SUBJECT
# - DATA
# - OPTIONS
# (I):
# - a hash ref with following keys:
#   > data, a hash ref
#   > topic, as a string
#   > options, as a string
#   > excludes, the list of data keys to be excluded

sub _executionReportToMqtt {
	my ( $args ) = @_;
	my $res = false;
	my $data = undef;
	$data = $args->{data} if defined $args->{data};
	if( defined $data ){
		$data = _executionReportCompleteData( $data );
		my $topic = undef;
		$topic = $args->{topic} if defined $args->{topic};
		my $excludes = [];
		$excludes = $args->{excludes} if defined $args->{excludes} && ref $args->{excludes} eq 'ARRAY' && scalar $args->{excludes} > 0;
		if( $topic ){
			my $dummy = $ep->runner()->dummy() ? "-dummy" : "-nodummy";
			my $verbose = $ep->runner()->verbose() ? "-verbose" : "-noverbose";
			my $command = $ep->var([ 'executionReports', 'withMqtt', 'command' ]);
			if( $command ){
				foreach my $key ( keys %{$data} ){
					if( !grep( /$key/, @{$excludes} )){
						#my $json = JSON->new;
						#my $str = $json->encode( $data );
						my $cmd = $command;
						$cmd =~ s/<SUBJECT>/$topic\/$key/;
						$cmd =~ s/<DATA>/$data->{$key}/;
						my $options = $args->{options} ? $args->{options} : "";
						$cmd =~ s/<OPTIONS>/$options/;
						$cmd = "$cmd -nocolored $dummy $verbose";
						msgOut( "executing '$cmd'" );
						my $result = TTP::commandExec( $cmd );
						$res = $result->{success};
					} else {
						msgVerbose( "do not publish excluded '$key' key" );
					}
				}
			} else {
				msgErr( __PACKAGE__."::_executionReportToMqtt() expected a 'command' argument, not found" );
			}
		} else {
			msgErr( __PACKAGE__."::_executionReportToMqtt() expected a 'topic' argument, not found" );
		}
	} else {
		msgErr( __PACKAGE__."::_executionReportToMqtt() expected a 'data' argument, not found" );
		TTP::stackTrace();
	}
	return $res;
}

# -------------------------------------------------------------------------------------------------
# exit the command
# Return code is optional, defaulting to IRunnable count of errors

sub exit {
	my $rc = shift || $ep->runner()->runnableErrs();
	msgDebug( __PACKAGE__."::exit() rc=$rc" );
	if( $rc ){
		msgErr( "exiting with code $rc" );
	} else {
		msgVerbose( "exiting with code $rc" );
	}
	exit $rc;
}

# -------------------------------------------------------------------------------------------------
# given a command, executes it and extracts the [command.pl verb] lines from stdout, returning the
# rest as an array
# (I):
# - the command string
# - an optional options argument to be passed to TTP::commandExec()
# (O):
# - a ref to an array of stdout outputed lines, having removed the "[command.pl verb]" lines

sub filter {
	my ( $command, $opts ) = @_;
	$opts //= {};

	my @result = ();
	my $res = TTP::commandExec( $command, $opts );
	foreach my $it ( @{$res->{stdout}} ){
		$it =~ s/^\s*//;
		$it =~ s/\s*$//;
		push( @result, $it ) if $it !~ /\(DBG|DUM|ERR|VER|WAR\)/ && $it !~ /^\[\w[\w\.\s]*\]/;
	}

	return \@result;
}

# -------------------------------------------------------------------------------------------------
# returns a new unique temp filename built with the qualifiers and a random string

sub getTempFileName {
	my $fname = $ep->runner()->runnableBNameShort();
	my @qualifiers = @{$ep->runner()->runnableQualifiers()};
	if( scalar( @qualifiers ) > 0 ){
		shift( @qualifiers );
		$fname .= "-".join( '-', @qualifiers );
	}
	my $random = random();
	my $tempfname = File::Spec->catfile( logsCommands(), "$fname-$random.tmp" );
	msgVerbose( "getTempFileName() tempfname='$tempfname'" );
	return $tempfname;
}

# -------------------------------------------------------------------------------------------------
# Converts back the output of TTP::displayTabular() function to an array of hashes
# as the only way for an external command to get the output of a sql batch is to pass through a tabular display output and re-interpretation
# (I):
# - an array of the lines outputed by a 'dbms.pl sql -tabular' command, which may contains several result sets
#   it is expected the output has already be filtered through TTP::filter()
# (O):
# returns:
# - an array of hashes if we have found a single result set
# - an array of arrays of hashes if we have found several result sets

sub hashFromTabular {
	my ( $self, $output ) = @_;
	my $result = [];
	my $multiple = false;
	my $array = [];
	my $sepCount = 0;
	my @columns = ();
	foreach my $line ( @{$output} ){
		if( $line =~ /^\+---/ ){
			$sepCount += 1;
			next;
		}
		# found another result set
		if( $sepCount == 4 ){
			$multiple = true;
			push( @{$result}, $array );
			$array = [];
			@columns = ();
			$sepCount = 1;
		}
		# header line -> provide column names
		if( $sepCount == 1 ){
			@columns = split( /\s*\|\s*/, $line );
			shift @columns;
		}
		# get data
		if( $sepCount == 2 ){
			my @data = split( /\s*\|\s*/, $line );
			shift @data;
			my $row = {};
			for( my $i=0 ; $i<scalar @columns ; ++$i ){
				$row->{$columns[$i]} = $data[$i];
			}
			push( @{$array}, $row );
		}
		# end of the current result set
		#if( $sepCount == 3 ){
		#}
	}
	# at the end, either push the current array, or set it
	if( $multiple ){
		push( @{$result}, $array );
	} else {
		$result = $array;
	}
	return $result;
}

# -------------------------------------------------------------------------------------------------
# Append a JSON element to a file
# (I):
# - the hash to be written into
# - the full path to be created
# (O):
# - returns true|false

sub jsonAppend {
	my ( $hash, $path ) = @_;
	msgVerbose( "jsonAppend() to '$path'" );
	my $json = JSON->new;
	my $str = $json->encode( $hash );
	my ( $vol, $dirs, $file ) = File::Spec->splitpath( $path );
	TTP::Path::makeDirExist( File::Spec->catdir( $vol, $dirs ));
	# some daemons may monitor this file in order to be informed of various executions - make sure each record has an EOL
	my $res = path( $path )->append_utf8( $str.EOL );
	msgVerbose( "jsonAppend() returns ".Dumper( $res ));
	return $res ? true : false;
}

# -------------------------------------------------------------------------------------------------
# Output an array of hashes as a json file
# (I):
# - an array of hashes, or an array of array of hashes if multiple result sets are provided
# - the output file path
# (O):
# - json file written

sub jsonOutput {
	my ( $result, $json ) = @_;
	my $ref = ref( $result );
	# expects an array, else just give up
	if( $ref ne 'ARRAY' ){
		msgVerbose( __PACKAGE__."::jsonOutput() expected an array, but found '$ref', so just give up" );
		return;
	}
	if( !scalar @{$result} ){
		msgVerbose( __PACKAGE__."::jsonOutput() got an empty array, so just give up" );
		return;
	}
	# expects an array of hashes
	# if we got an array of arrays, then this is a multiple result sets and recurse
	$ref = ref( $result->[0] );
	if( $ref eq 'ARRAY' ){
		foreach my $set ( @{$result} ){
			jsonOutput( $set, $json );
		}
		return;
	}
	if( $ref ne 'HASH' ){
		msgVerbose( __PACKAGE__."::jsonOutput() expected an array of hashes, but found an array of '$ref', so just give up" );
		return;
	}
	# output as json
	jsonAppend( $result, $json );
}

# -------------------------------------------------------------------------------------------------
# Read a JSON file into a hash
# Do not evaluate here, just read the file data
# (I):
# - the full path to the to-be-loaded-and-interpreted json file
# - an optional options hash with following keys:
#   > ignoreIfNotExist: defaulting to false
# (O):
# returns the read hash, or undef

sub jsonRead {
	my ( $path, $opts ) = @_;
	TTP::stackTrace() if !$path;
	$opts //= {};
	#msgVerbose( "jsonRead() path='$path'" );
	my $result = undef;
	if( $path && -r $path ){
		my $content = do {
		   open( my $fh, "<:encoding(UTF-8)", $path ) or msgErr( __PACKAGE__."::jsonRead() $path: $!" );
		   local $/;
		   <$fh>
		};
		my $json = JSON->new;
		# may croak on error, intercepted below
		eval { $result = $json->decode( $content ) };
		if( $@ ){
			chomp $@;
			msgWarn( "jsonRead() $path: $@" );
			$result = undef;
		}
	} elsif( $path ){
		my $ignoreIfNotExist = false;
		$ignoreIfNotExist = $opts->{ignoreIfNotExist} if defined $opts->{ignoreIfNotExist};
		msgErr( __PACKAGE__."::jsonRead() $path: not found or not readable" ) if !$ignoreIfNotExist;
	} else {
		msgErr( __PACKAGE__."::jsonRead() expects a JSON path to be read" );
	}
	return $result;
}

# -------------------------------------------------------------------------------------------------
# Write a hash to a JSON file
# (I):
# - the hash to be written into
# - the full path to be created (is overwritten if already exists)
# (O):
# - returns true|false

sub jsonWrite {
	my ( $hash, $path ) = @_;
	msgVerbose( "jsonWrite() to '$path'" );
	my $json = JSON->new;
	my $str = $json->encode( $hash );
	my ( $vol, $dirs, $file ) = File::Spec->splitpath( $path );
	TTP::Path::makeDirExist( File::Spec->catdir( $vol, $dirs ));
	# some daemons may monitor this file in order to be informed of various executions - make sure we end up with an EOL
	# '$res' is an array with the original path and an interpreted one - may also return true
	my $res = path( $path )->spew_utf8( $str.EOL );
	msgVerbose( "jsonWrite() returns ".Dumper( $res ));
	return (( looks_like_number( $res ) && $res == 1 ) || ( ref( $res ) eq 'Path::Tiny' && scalar( @{$res} ) > 0 )) ? true : false;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'logsCommands' directory, which may be undef very early in the bootstrap process
#   and at least not definitive while the node has not been instanciated/loaded/evaluated

sub logsCommands {
	return TTP::Path::logsCommands();
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'logsDaily' directory, which may be undef very early in the bootstrap process
#   and at least not definitive while the node has not been instanciated/loaded/evaluated

sub logsDaily {
	msgWarn( "TTP::logsDaily() is deprecated in favor of TTP:logsPeriodic(). You should update your code." );
	return TTP::Path::logsPeriodic();
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'logsMain' full pathname, which may be undef very early in the bootstrap process
#   and at least not definitive while the node has not been instanciated/loaded/evaluated

sub logsMain {
	return TTP::Path::logsMain();
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'logsPeriodic' directory, which may be undef very early in the bootstrap process
#   and at least not definitive while the node has not been instanciated/loaded/evaluated

sub logsPeriodic {
	return TTP::Path::logsPeriodic();
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'logsRoot' directory, which may be undef very early in the bootstrap process
#   and at least not definitive while the node has not been instanciated/loaded/evaluated

sub logsRoot {
	return TTP::Path::logsRoot();
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the name of the current node, which may be undef in the very early stage of bootstrap

sub nodeName {
	my $node = $ep ? $ep->node() : undef;
	return $node ? $node->name() : undef;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'nodeRoot' directory - removed in v4.7

sub nodeRoot {
	msgErr( __PACKAGE__."::nodeRoot() is deprecated and not replaced. You should update your code." );
	return undef;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the null value to be used for this OS

sub nullByOS {
	return $Const->{byOS}{$Config{osname}}{null};
}

# -------------------------------------------------------------------------------------------------
# pad the provided string until the specified length with the provided char
# (I):
# - the to-be-padded string
# - the target length
# - the pad character
# (O):
# - returns the padded string

sub pad {
	my( $str, $length, $pad ) = @_;
	while( length( $str ) < $length ){
		$str .= $pad;
	}
	return $str;
}

# -------------------------------------------------------------------------------------------------
# print a value on stdout
# (I):
# - the value to be printed, maybe undef
# (O):
# - printed on stdout or nothing

sub print {
	my ( $prefix, $value ) = @_;
	if( defined( $prefix ) && defined( $value )){
		print_rec( $prefix, $value );
	} else {
		msgErr( __PACKAGE__."::print() undefined prefix" ) if !defined $prefix;
		msgErr( __PACKAGE__."::print() undefined value" ) if !defined $value;
	}
}

sub print_rec {
	my ( $prefix, $value ) = @_;
	my $ref = ref( $value );
	if( $ref ){
		if( $ref eq 'ARRAY' ){
			foreach my $it ( @{$value} ){
				print_rec( $prefix, $it );
			}
		} elsif( $ref eq 'HASH' ){
			foreach my $it ( sort keys %{$value} ){
				print_rec( "$prefix.$it", $value->{$it} );
			}
		} else {
			msgErr( __PACKAGE__."::print_rec() unmanaged reference '$ref'" );
			TTP::stackTrace();
		}
	} else {
		print "$prefix: $value".EOL;
	}
}

# -------------------------------------------------------------------------------------------------
# returns a random identifier
# (I):
# - none
# (O):
# - a random (UUID-based) string of 32 hexa lowercase characters

sub random {
	my $ug = new Data::UUID;
	my $uuid = lc $ug->create_str();
	$uuid =~ s/-//g;
	return $uuid;
}

# -------------------------------------------------------------------------------------------------
# Run by the command
# Expects $0 be the full path name to the command script (this is the case in Windows+Strawberry)
# and @ARGV the command-line arguments

sub runCommand {
	msgDebug( __PACKAGE__."::runCommand() \@ARGV=".TTP::chompDumper( @ARGV ));
	require TTP::RunnerVerb;
	$ep = TTP::EP->new();
	$ep->bootstrap();
	my $command = TTP::RunnerVerb->new( $ep );
	$command->run();
	return $command;
}

# -------------------------------------------------------------------------------------------------
# Run by the command
# Expects $0 be the full path name to the command script (this is the case in Windows+Strawberry)
# and @ARGV the command-line arguments

sub runExtern {
	msgDebug( __PACKAGE__."::runCommand() \@ARGV=".TTP::chompDumper( @ARGV ));
	require TTP::RunnerExtern;
	$ep = TTP::EP->new();
	$ep->bootstrap();
	my $command = TTP::RunnerExtern->new( $ep );
	return $command;
}

# -------------------------------------------------------------------------------------------------
# print a stack trace
# https://stackoverflow.com/questions/229009/how-can-i-get-a-call-stack-listing-in-perl
# to be called for code errors
# (I):
# - an optional options hash with following keys:
#   > exit: whether to exit after the stack trace, defaulting to true

sub stackTrace {
	my ( $opts ) = @_;
	$opts //= {};
	$opts->{exit} = true if !defined $opts->{exit};
	my $trace = Devel::StackTrace->new;
	print $trace->as_string;
	if( $opts->{exit} ){
		TTP::exit( 1 );
	} else {
		msgDebug( __PACKAGE__."::stackTrace() returning" );
	}
}

# ------------------------------------------------------------------------------------------------
# Substitute the macros in a hash
# Always honors <NODE> macro which defaults to current execution node
# Macros must be specified as {
#	<MACRO> => value
# }
# (I):
# - the value to be substituted, which can be a scalar, or an array, or a hash
# - a hash ref where keys are the macro the be substituted and values are the substituted value
# (O):
# - substituted value

sub substituteMacros {
	my ( $data, $macros ) = @_;

	my $ref = ref( $data );
	if( $ref ){
		if( $ref eq 'ARRAY' ){
			for( my $i=0 ; $i<scalar @{$data} ; ++$i ){
				$data->[$i] = substituteMacros( $data->[$i], $macros );
			}
		} elsif( $ref eq 'HASH' ){
			foreach my $it ( sort keys %{$data} ){
				$data->{$it} = substituteMacros( $data->{$it}, $macros );
			}
		} elsif( $ref ne 'JSON::PP::Boolean' ){
			msgErr( __PACKAGE__."::substituteMacros() unmanaged ref '$ref'" );
			TTP::stackTrace();
		}
	} else {
		foreach my $it ( keys %{$macros} ){
			$data =~ s/<$it>/$macros->{$it}/g;
		}
		if( !defined $macros->{NODE} && $ep->node()){
			my $executionNode = $ep->node()->name();
			$data =~ s/<NODE>/$executionNode/g;
		}
	}

	return $data;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'tempDir' directory for the running OS

sub tempDir {
	my $result = $Const->{byOS}{$Config{osname}}{tempDir};
	return $result;
}

# -------------------------------------------------------------------------------------------------
# Returns a variable value
# This function is callable as '$ep->var()' and is so one the preferred way of accessing
# configurations values from configuration files themselves as well as from external commands.
# (I):
# - a scalar, or an array of scalars which are to be successively searched, or an array of arrays
#   of scalars, these later being to be successively tested.
# (O):
# - the found value or undef

sub var {
	return $ep->var( @_ );
}

# -------------------------------------------------------------------------------------------------
# Returns the version string of *this* TTP tree
# (I):
# - none
# (O):
# - the found version string or undef

sub version {
	my $version = undef;

	# simpler than provide a code ref to IFindable
	my @roots = split( /$Config{path_sep}/, $ENV{TTP_ROOTS} );
	foreach my $it ( @roots ){
		my $parent = dirname( $it );
		my $candidate = File::Spec->catfile( $parent, ".VERSION" );
		if( -r $candidate ){
			$version = path( $candidate )->slurp_utf8;
			chomp $version;
			last;
		}
	}

	return $version;
}

1;
