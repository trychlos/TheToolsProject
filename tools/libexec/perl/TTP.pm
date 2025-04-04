# The Tools Project: a Tools System and Paradigm for IT Production
# Copyright (©) 1998-2023 Pierre Wieser (see AUTHORS)
# Copyright (©) 2023-2024 PWI Consulting
#
# The Tools Project is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version.
#
# The Tools Project is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with The Tools Project; see the file COPYING. If not,
# see <http://www.gnu.org/licenses/>.

package TTP;

use strict;
use warnings;
use utf8;

use Config;
use Data::Dumper;
use Data::UUID;
use Devel::StackTrace;
use File::Copy qw( copy move );
use File::Copy::Recursive qw( dircopy );
use File::Path qw( make_path remove_tree );
use File::Spec;
use JSON;
use open qw( :std :encoding(UTF-8) );
use Path::Tiny qw( path );
use Scalar::Util qw( looks_like_number );
use Test::Deep;
use Time::Moment;
use Time::Piece;
use vars::global create => qw( $ep );

use TTP::Constants qw( :all );
use TTP::EP;
use TTP::Finder;
use TTP::Message qw( :all );
use TTP::Node;

# autoflush STDOUT
$| = 1;

# store here our Toops variables
my $Const = {
	# defaults which depend of the host OS provided by 'Config' package
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
# (I):
# - none
# (O):
# - returns the alertsdir

sub alertsDir {
	my $dir = $ep->var([ 'alerts', 'withFile', 'dropDir' ]) || tempDir();
	return $dir;
}

# -------------------------------------------------------------------------------------------------
# Execute a command dependant of the running OS.
# This is expected to be configured in TOOPS.json as TOOPS => {<key>} => {command}
# where command may have some keywords to be remplaced before execution
# (I):
# argument is a hash with following keys:
# - command: the command to be evaluated and executed, may be undef
# - macros: a hash of the macros to be replaced where:
#   > key is the macro name, must be labeled in the toops.json as '<macro>' (i.e. between angle brackets)
#   > value is the value to be replaced
# (O):
# return a hash with following keys:
# - evaluated: the evaluated command after macros replacements
# - return: original exit code of the command
# - result: true|false

sub commandByOs {
	my ( $args ) = @_;
	my $result = {};
	$result->{command} = $args->{command};
	$result->{result} = false;
	msgVerbose( "Toops::commandByOs() evaluating and executing command='".( $args->{command} || '(undef)' )."'" );
	if( defined $args->{command} ){
		$result->{evaluated} = $args->{command};
		foreach my $key ( keys %{$args->{macros}} ){
			$result->{evaluated} =~ s/<$key>/$args->{macros}{$key}/;
		}
		msgVerbose( "Toops::commandByOs() evaluated to '$result->{evaluated}'" );
		if( $ep->runner()->dummy()){
			msgDummy( $result->{evaluated} );
			$result->{result} = true;
		} else {
			my $out = `$result->{evaluated}`;
			print $out;
			msgLog( $out );
			# https://www.perlmonks.org/?node_id=81640
			# Thus, the exit value of the subprocess is actually ($? >> 8), and $? & 127 gives which signal, if any, the
			# process died from, and $? & 128 reports whether there was a core dump.
			# https://ss64.com/nt/robocopy-exit.html
			my $res = $?;
			$result->{result} = ( $res == 0 ) ? true : false;
			msgVerbose( "Toops::commandByOs() return_code=$res firstly interpreted as result=$result->{result}" );
			if( $args->{command} =~ /robocopy/i ){
				$res = ( $res >> 8 );
				$result->{result} = ( $res <= 7 ) ? true : false;
				msgVerbose( "Toops::commandByOs() robocopy specific interpretation res=$res result=$result->{result}" );
			}
		}
	}
	msgVerbose( "Toops::commandByOs() result=$result->{result}" );
	return $result;
}

# -------------------------------------------------------------------------------------------------
# copy a directory and its content from a source to a target
# this is a design decision to make this recursive copy file by file in order to have full logs
# Toops allows to provide a system-specific command in its configuration file
# well suited for example to move big files to network storage
# return true|false

sub copyDir {
	my ( $source, $target ) = @_;
	my $result = false;
	msgVerbose( "Toops::copyDir() entering with source='$source' target='$target'" );
	if( ! -d $source ){
		msgErr( "$source: source directory doesn't exist" );
		return false;
	}
	my $cmdres = commandByOs({
		command => $ep->var([ 'copyDir', 'byOS', $Config{osname}, 'command' ]),
		macros => {
			SOURCE => $source,
			TARGET => $target
		}
	});
	if( defined $cmdres->{command} ){
		$result = $cmdres->{result};
		msgVerbose( "Toops::copyDir() commandByOs() result=$result" );
	} elsif( $ep->runner()->dummy()){
		msgDummy( "dircopy( $source, $target )" );
	} else {
		# https://metacpan.org/pod/File::Copy::Recursive
		# This function returns true or false: for true in scalar context it returns the number of files and directories copied,
		# whereas in list context it returns the number of files and directories, number of directories only, depth level traversed.
		my $res = dircopy( $source, $target );
		$result = $res ? true : false;
		msgVerbose( "Toops::copyDir() dircopy() res=$res result=$result" );
	}
	msgVerbose( "Toops::copyDir() returns result=$result" );
	return $result;
}

# -------------------------------------------------------------------------------------------------
# copy a file from a source to a target
# Toops allows to provide a system-specific command in its configuration file
# well suited for example to copy big files to network storage
# (I):
# - source: the source volume, directory and filename
# - target :the target volume and directory
# (O):
# return true|false

sub copyFile {
	my ( $source, $target ) = @_;
	my $result = false;
	msgVerbose( "Toops::copyFile() entering with source='$source' target='$target'" );
	# isolate the file from the source directory path
	my ( $vol, $dirs, $file ) = File::Spec->splitpath( $source );
	my $srcpath = File::Spec->catpath( $vol, $dirs );
	my $cmdres = commandByOs({
		command => $ep->var([ 'copyFile', 'byOS', $Config{osname}, 'command' ]),
		macros => {
			SOURCE => $srcpath,
			TARGET => $target,
			FILE => $file
		}
	});
	if( defined $cmdres->{command} ){
		$result = $cmdres->{result};
		msgVerbose( "Toops::copyFile() commandByOs() result=$result" );
	} elsif( $ep->runner()->dummy()){
		msgDummy( "copy( $source, $target )" );
	} else {
		# https://metacpan.org/pod/File::Copy
		# This function returns true or false
		$result = copy( $source, $target );
		if( $result ){
			msgVerbose( "Toops::copyFile() result=true" );
		} else {
			msgErr( "Toops::copyFile() $!" );
		}
	}
	msgVerbose( "Toops::copyFile() returns result=$result" );
	return $result;
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
	my $running = $ep->runner();
	return $running->runnableErrs() if $running;
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
#   when a new one is detected, or listen to the MQTT bus and suibscribe to interesting topics, and so on...).
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
# - return code
# - full run command

sub executionReport {
	my ( $args ) = @_;
	# write JSON file if configuration enables that and relevant arguments are provided
	my $enabled = $ep->var([ 'executionReports', 'withFile', 'enabled' ]);
	if( $enabled && $args->{file} ){
		_executionReportToFile( $args->{file} );
	}
	# publish MQTT message if configuration enables that and relevant arguments are provided
	$enabled = $ep->var([ 'executionReports', 'withMqtt', 'enabled' ]);
	if( $enabled && $args->{mqtt} ){
		_executionReportToMqtt( $args->{mqtt} );
	}
}

# Complete the provided data with the data collected by TTP

sub _executionReportCompleteData {
	my ( $data ) = @_;
	my $running = $ep->runner();
	$data->{cmdline} = "$0 ".join( ' ', @{$running->runnableArgs()} );
	$data->{command} = $running->command();
	$data->{verb} = $running->verb();
	$data->{host} = $ep->node()->name();
	$data->{code} = $running->runnableErrs();
	$data->{started} = $running->runnableStarted()->strftime( '%Y-%m-%d %H:%M:%S.%5N' );
	$data->{ended} = Time::Moment->now->strftime( '%Y-%m-%d %H:%M:%S.%5N' );
	$data->{dummy} = $running->dummy();
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
	$data = $args->{data} if exists $args->{data};
	if( defined $data ){
		$data = _executionReportCompleteData( $data );
		my $command = $ep->var([ 'executionReports', 'withFile', 'command' ]);
		if( $command ){
			my $running = $ep->runner();
			my $json = JSON->new;
			my $str = $json->encode( $data );
			# protect the double quotes against the CMD.EXE command-line
			$str =~ s/"/\\"/g;
			$command =~ s/<DATA>/$str/;
			my $dummy = $running->dummy() ? "-dummy" : "-nodummy";
			my $verbose = $running->verbose() ? "-verbose" : "-noverbose";
			my $cmd = "$command -nocolored $dummy $verbose";
			msgOut( "executing '$cmd'" );
			`$cmd`;
			msgVerbose( "TTP::_executionReportToFile() got $?" );
			$res = ( $? == 0 );
		} else {
			msgErr( "executionReportToFile() expected a 'command' argument, not found" );
		}
	} else {
		msgErr( "executionReportToFile() expected a 'data' argument, not found" );
	}
	return $res;
}

# send an execution report on the MQTT bus if Toops is configured for
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
	$data = $args->{data} if exists $args->{data};
	if( defined $data ){
		$data = _executionReportCompleteData( $data );
		my $topic = undef;
		$topic = $args->{topic} if exists $args->{topic};
		my $excludes = [];
		$excludes = $args->{excludes} if exists $args->{excludes} && ref $args->{excludes} eq 'ARRAY' && scalar $args->{excludes} > 0;
		if( $topic ){
			my $running = $ep->runner();
			my $dummy = $running->dummy() ? "-dummy" : "-nodummy";
			my $verbose = $running->verbose() ? "-verbose" : "-noverbose";
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
						`$cmd`;
						my $rc = $?;
						msgVerbose( "Toops::_executionReportToMqtt() got rc=$rc" );
						$res = ( $rc == 0 );
					} else {
						msgVerbose( "do not publish excluded '$key' key" );
					}
				}
			} else {
				msgErr( "executionReportToMqtt() expected a 'command' argument, not found" );
			}
		} else {
			msgErr( "executionReportToMqtt() expected a 'topic' argument, not found" );
		}
	} else {
		msgErr( "executionReportToMqtt() expected a 'data' argument, not found" );
	}
	return $res;
}

# -------------------------------------------------------------------------------------------------
# exit the command
# Return code is optional, defaulting to IRunnable count of errors

sub exit {
	my $rc = shift || $ep->runner()->runnableErrs();
	if( $rc ){
		msgErr( "exiting with code $rc" );
	} else {
		msgVerbose( "exiting with code $rc" );
	}
	exit $rc;
}

# -------------------------------------------------------------------------------------------------
# given a command output, extracts the [command.pl verb] lines, returning the rest as an array
# Note:
# - we receive an array of EOL-terminated strings when called as $result = TTP::filter( `$command` );
# - but we receive a single concatenated string when called as $result = `$command`; $result = TTP:filter( $result );
# (I):
# - the output of a command, as a string or an array of strings
# (O):
# - a ref to an array of output lines, having removed the "[command.pl verb]" lines

sub filter {
	my $single = join( '', @_ );
	my @lines = split( /[\r\n]/, $single );
	my @result = ();
	foreach my $it ( @lines ){
		chomp $it;
		$it =~ s/^\s*//;
		$it =~ s/\s*$//;
		push( @result, $it ) if !grep( /^\[|\(ERR|\(DUM|\(VER|\(WAR|^$/, $it ) && $it !~ /\(WAR\)/ && $it !~ /\(ERR\)/;
	}
	return \@result;
}

# -------------------------------------------------------------------------------------------------
# returns the path requested by the given command
# (I):
# - the command to be executed
# - an optional options hash with following keys:
#   > makeExist, defaulting to false
# ((O):
# - returns a path of undef if an error has occured

sub fromCommand {
	my( $cmd, $opts ) = @_;
	$opts //= {};
	msgErr( "fromCommand() command is not specified" ) if !$cmd;
	my $path = undef;
	if( !TTP::errs()){
		$path = `$cmd`;
		msgErr( "fromCommand() command doesn't output anything" ) if !$path;
	}
	if( !TTP::errs()){
		my @words = split( /\s+/, $path );
		if( scalar @words < 2 ){
			msgErr( "fromCommand() expect at least two words" );
		} else {
			$path = $words[scalar @words - 1];
			msgErr( "fromCommand() found an empty path" ) if !$path;
		}
	}
	if( !TTP::errs()){
		my $makeExist = false;
		$makeExist = $opts->{makeExist} if exists $opts->{makeExist};
		if( $makeExist ){
			my $rc = makeDirExist( $path );
			$path = undef if !$rc;
		}
	}
	$path = undef if TTP::errs();
	return $path;
}

# -------------------------------------------------------------------------------------------------
# returns a new unique temp filename

sub getTempFileName {
	my $fname = $ep->runner()->runnableBNameShort();
	my $qualifier = $ep->runner()->runnableQualifier();
	$fname .= "-$qualifier" if $qualifier;
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
# Getter
# (I):
# - none
# (O):
# - returns the current execution node name, which may be undef very early in the process

sub host {
	my $node = $ep->node();
	return $node ? $node->name() : undef;
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
	TTP::makeDirExist( File::Spec->catdir( $vol, $dirs ));
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
	stackTrace() if !$path;
	$opts //= {};
	msgVerbose( "jsonRead() path='$path'" );
	my $result = undef;
	if( $path && -r $path ){
		my $content = do {
		   open( my $fh, "<:encoding(UTF-8)", $path ) or msgErr( "jsonRead() $path: $!" );
		   local $/;
		   <$fh>
		};
		my $json = JSON->new;
		# may croak on error, intercepted below
		eval { $result = $json->decode( $content ) };
		if( $@ ){
			msgWarn( "jsonRead() $path: $@" );
			$result = undef;
		}
	} elsif( $path ){
		my $ignoreIfNotExist = false;
		$ignoreIfNotExist = $opts->{ignoreIfNotExist} if exists $opts->{ignoreIfNotExist};
		msgErr( "jsonRead() $path: not found or not readable" ) if !$ignoreIfNotExist;
	} else {
		msgErr( "jsonRead() expects a JSON path to be read" );
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
	TTP::makeDirExist( File::Spec->catdir( $vol, $dirs ));
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
	my $result = $ep->node() ? ( $ep->var( 'logsCommands' ) || logsDaily()) : undef;
	return $result;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'logsDaily' directory, which may be undef very early in the bootstrap process
#   and at least not definitive while the node has not been instanciated/loaded/evaluated

sub logsDaily {
	my $result = $ep->node() ? ( $ep->var( 'logsDaily' ) || logsRoot()) : undef;
	return $result;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'logsMain' full pathname, which may be undef very early in the bootstrap process
#   and at least not definitive while the node has not been instanciated/loaded/evaluated

sub logsMain {
	my $result = $ep->node() ? ( $ep->var( 'logsMain' ) || File::Spec->catfile( logsCommands(), 'main.log' )) : undef;
	return $result;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'logsRoot' directory, which may be undef very early in the bootstrap process
#   and at least not definitive while the node has not been instanciated/loaded/evaluated

sub logsRoot {
	my $result = $ep->node() ? ( $ep->var( 'logsRoot' ) || tempDir()) : undef;
	return $result;
}

# -------------------------------------------------------------------------------------------------
# make sure a directory exist
# note that this does NOT honor the '-dummy' option as creating a directory is easy and a work may
# be blocked without that
# NB: pwi 2024- 6- 4
#     creating a path like '\\ftpback-rbx2-207.ovh.net\ns3197235.ip-141-95-3.eu\WS12DEV2\SQLBackups' is OK and has been thoroughly tested
#     even  if this operation is subject to the 'Insufficient system resources exist to complete the requested service' error
#     (like all storage/network operations)
# (I):
# - the directory to be created if not exists
# - an optional options hash with following keys:
#   > allowVerbose whether you can call msgVerbose() function (false to not create infinite loop
#     when called from msgXxx()), defaulting to true
# (O):
# returns true|false

sub makeDirExist {
	my ( $dir, $opts ) = @_;
	$opts //= {};
	my $allowVerbose = true;
	$allowVerbose = $opts->{allowVerbose} if exists $opts->{allowVerbose};
	$allowVerbose = false if !$ep || !$ep->runner();
	my $result = false;
	if( -d $dir ){
		$result = true;
	} else {
		msgVerbose( "makeDirExist() make_path() dir='$dir'" ) if $allowVerbose;
		my $error;
		$result = true;
		make_path( $dir, {
			verbose => $allowVerbose && $ep->runner()->verbose(),
			error => \$error
		});
		# https://perldoc.perl.org/File::Path#make_path%28-%24dir1%2C-%24dir2%2C-....-%29
		if( $error && @$error ){
			for my $diag ( @$error ){
				my ( $file, $message ) = %$diag;
				if( $file eq '' ){
					msgErr( $message );
				} else {
					msgErr( "$file: $message" );
				}
			}
			$result = false;
		}
		msgVerbose( "makeDirExist() dir='$dir' result=$result" ) if $allowVerbose;
	}
	return $result;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'nodeRoot' directory specified in the site configuration to act as a replacement
#   to the mounted filesystem as there is no logical machine in this Perl version

sub nodeRoot {
	my $result = $ep->site() ? ( $ep->var( 'nodeRoot' ) || $Const->{byOS}{$Config{osname}}{tempDir} ) : undef;
	return $result;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'nodes.dirs' array of directories specified in the site configuration which are the
#   subdirectories of TTP_ROOTS where we can find nodes JSON configuration files.

sub nodesDirs {
	return TTP::Node->dirs();
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
		msgErr( "TTP::print() undefined prefix" ) if !defined $prefix;
		msgErr( "TTP::print() undefined value" ) if !defined $value;
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
			msgErr( "TTP::print() unmanaged reference '$ref'" );
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
# delete a directory and all its content
# (I):
# - the dir to be deleted
# (O):
# - true|false

sub removeTree {
	my ( $dir ) = @_;
	my $result = true;
	msgVerbose( "Toops::removeTree() removing '$dir'" );
	my $error;
	remove_tree( $dir, {
		verbose => $ep->{run}{verbose},
		error => \$error
	});
	# https://perldoc.perl.org/File::Path#make_path%28-%24dir1%2C-%24dir2%2C-....-%29
	if( $error && @$error ){
		for my $diag ( @$error ){
			my ( $file, $message ) = %$diag;
			if( $file eq '' ){
				msgErr( "remove_tree() $message" );
			} else {
				msgErr( "remove_tree() $file: $message" );
			}
		}
		$result = false;
	}
	msgVerbose( "Toops::removeTree() dir='$dir' result=$result" );
	return $result;
}

# -------------------------------------------------------------------------------------------------
# Run by the command
# Expects $0 be the full path name to the command script (this is the case in Windows+Strawberry)
# and @ARGV the command-line arguments

sub run {
	$ENV{TTP_DEBUG} && print STDERR Dumper( @ARGV );
	$ep = TTP::EP->new();
	$ep->bootstrap();
	$ep->runCommand();
}

# -------------------------------------------------------------------------------------------------
# print a stack trace
# https://stackoverflow.com/questions/229009/how-can-i-get-a-call-stack-listing-in-perl

sub stackTrace {
	my $trace = Devel::StackTrace->new;
	print $trace->as_string; # like carp
}

# ------------------------------------------------------------------------------------------------
# substitute the macros in a hash
# At the moment:
# - <NODE> the current execution node
# - <SERVICE> this service name
# (I):
# - the hash to be substituted
# - a hash ref where keys are the macro the be substituted and values are the substituted value
# (O):
# - substituted hash

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
			stackTrace();
		}
	} else {
		foreach my $it ( keys %{$macros} ){
			$data =~ s/$it/$macros->{$it}/;
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

1;
