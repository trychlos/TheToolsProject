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

use B qw( svref_2object );
use Capture::Tiny qw( capture );
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
use SemVer;
use String::Random;
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
	return TTP::alertsFileDropdir( @_ );
}

# -------------------------------------------------------------------------------------------------
# Returns the configured alertsDir (when alerts are sent by file), defaulting to tempDir()
# (I):
# - none
# (O):
# - returns the alertsdir

sub alertsFileDropdir {
	return TTP::Path::alertsFileDropdir( @_ );
}

# -------------------------------------------------------------------------------------------------
# Returns whether the 'withFile' alert is a default and whether it is enabled
# (I):
# - none
# (O):
# - returns an array ( default, enabled )

sub alertsWithFile {
	my $default = TTP::var([ 'alerts', 'withFile', 'default' ]) // false;
	my $enabled = TTP::var([ 'alerts', 'withFile', 'enabled' ]) // true;
	msgWarn( "alerts.withFile.default=true while alerts.withFile.enabled=false which is not consistent" ) if $default && !$enabled;
	return ( $default, $enabled );
}

# -------------------------------------------------------------------------------------------------
# Returns whether the 'withMms' alert is a default and whether it is enabled
# (I):
# - none
# (O):
# - returns an array ( default, enabled )

sub alertsWithMms {
	my $default = TTP::var([ 'alerts', 'withMms', 'default' ]) // false;
	my $enabled = TTP::var([ 'alerts', 'withMms', 'enabled' ]) // true;
	msgWarn( "alerts.withMms.default=true while alerts.withMms.enabled=false which is not consistent" ) if $default && !$enabled;
	return ( $default, $enabled );
}

# -------------------------------------------------------------------------------------------------
# Returns whether the 'withMmqtt' alert is a default and whether it is enabled
# (I):
# - none
# (O):
# - returns an array ( default, enabled )

sub alertsWithMqtt {
	my $default = TTP::var([ 'alerts', 'withMmqtt', 'default' ]) // false;
	my $enabled = TTP::var([ 'alerts', 'withMmqtt', 'enabled' ]) // true;
	msgWarn( "alerts.withMmqtt.default=true while alerts.withMmqtt.enabled=false which is not consistent" ) if $default && !$enabled;
	return ( $default, $enabled );
}

# -------------------------------------------------------------------------------------------------
# Returns whether the 'withSms' alert is a default and whether it is enabled
# (I):
# - none
# (O):
# - returns an array ( default, enabled )

sub alertsWithSms {
	my $default = TTP::var([ 'alerts', 'withSms', 'default' ]) // false;
	my $enabled = TTP::var([ 'alerts', 'withSms', 'enabled' ]) // true;
	msgWarn( "alerts.withSms.default=true while alerts.withSms.enabled=false which is not consistent" ) if $default && !$enabled;
	return ( $default, $enabled );
}

# -------------------------------------------------------------------------------------------------
# Returns whether the 'withSmtp' alert is a default and whether it is enabled
# (I):
# - none
# (O):
# - returns an array ( default, enabled )

sub alertsWithSmtp {
	my $default = TTP::var([ 'alerts', 'withSmtp', 'default' ]) // false;
	my $enabled = TTP::var([ 'alerts', 'withSmtp', 'enabled' ]) // true;
	msgWarn( "alerts.withSmtp.default=true while alerts.withSmtp.enabled=false which is not consistent" ) if $default && !$enabled;
	return ( $default, $enabled );
}

# -------------------------------------------------------------------------------------------------
# Returns whether the 'withTextToSpeech' alert is a default and whether it is enabled
# (I):
# - none
# (O):
# - returns an array ( default, enabled )

sub alertsWithTts {
	my $default = TTP::var([ 'alerts', 'withTextToSpeech', 'default' ]) // false;
	my $enabled = TTP::var([ 'alerts', 'withTextToSpeech', 'enabled' ]) // true;
	msgWarn( "alerts.withTextToSpeech.default=true while alerts.withTextToSpeech.enabled=false which is not consistent" ) if $default && !$enabled;
	return ( $default, $enabled );
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
	$str =~ s/;$//;
	chomp $str;
	return $str;
}

# -------------------------------------------------------------------------------------------------
# find coderefs inside of an object
# usage:
#   my @where = coderefs_find( $object );
#   for my $hit (@where) {
#       warn "CODE at $hit->{path}", ($hit->{name} ? " ($hit->{name})" : ""), "\n";
#   }

sub coderefs_find {
    my ($root) = @_;
    my %seen;
    my @hits;
    coderef_walk($root, '$conf', \%seen, \@hits);
    return @hits;
}

# -------------------------------------------------------------------------------------------------

sub coderef_name {
    my ($code) = @_;
    my $cv = svref_2object($code);
    my $gv = $cv->GV or return undef;
    my $pkg = $gv->STASH->NAME;
    my $name = $gv->NAME;
    return "${pkg}::${name}";
}

# -------------------------------------------------------------------------------------------------

sub coderef_walk {
    my ($v, $path, $seen, $hits) = @_;
    return unless ref $v;
    return if $seen->{$v}++;
    my $rt = reftype($v) // '';

    if ($rt eq 'CODE') {
        push @{$hits}, { path => $path, name => coderef_name($v) // '__ANON__' };
        return;
    }
    if ($rt eq 'ARRAY') {
        for my $i (0..$#$v) { coderef_walk($v->[$i], "$path\->[$i]", $seen, $hits) }
        return;
    }
    if ($rt eq 'HASH') {
        for my $k (sort keys %$v) {
            my $kp = $k =~ /^[A-Za-z_]\w*$/ ? "{$k}" : "{'$k'}";
            coderef_walk($v->{$k}, "$path\->$kp", $seen, $hits);
        }
        return;
    }
    # For blessed refs, still descend (most Perl OO are blessed HASH/ARRAY)
    if( blessed( $v )){
        coderef_walk( $v, $path, $seen, $hits );  # already handled above by ref type
    }
}

# -------------------------------------------------------------------------------------------------
# Read from configuration either a 'command' or a 'commands' property.
# 'command' itself is obsoleted starting with v4.16
# Both 'command' and 'commands' accept:
# - either a single string
# - or an array
#   when each item is either a single string or an object with a 'byOS' property
# - or an object with a 'byOS' property.
# (I):
# - the list of keys before the 'command' as an array ref
# - an optional options hash ref with following keys:
#   > jsonable: a IJSONable to be searched for for the provided keys, defaulting to node/site data
# (O):
# - in a list context, returns:
#   > a flag true|false, true if no error has been detected (which doesn't mean there is any valid command)
#   > a ref to an array of the found command(s), which may be empty
# - in a scalar context, returns a ref to an array of the found command(s), which may be empty

sub commandByOS {
	my ( $keys, $opts ) = @_;
	$opts //= {};
	my $commands = [];

	# search for a 'command' property
	my @locals = ( @{$keys}, 'command' );
	my ( $res, $obj ) = commandByOS_getObject( \@locals, $opts );
	if( $res ){
		if( $obj ){
			# as of v4.16.2, we come back on the 'command' deprecation
			#msgWarn( "'command' property is deprecated in favor of 'commands'. You should update your configurations." );
		# search for a 'commands' property
		} else {
			@locals = ( @{$keys}, 'commands' );
			( $res, $obj ) = commandByOS_getObject( \@locals, $opts );
		}
	}

	# if no error and something has been found, resolve the 'byOS' configs
	if( $res && $obj ){
		my $ref = ref( $obj );
		if( $ref eq 'ARRAY' ){
			foreach my $it ( @{$obj} ){
				push( @{$commands}, commandByOS_resolveItem( $it ));
			}
		} elsif( $ref eq 'HASH' ){
			push( @{$commands}, commandByOS_resolveHash( $obj ));

		} else {
			push( @{$commands}, $obj );
		}
	}

	# returns either in list or scalar context
	return wantarray ? ( $res, $commands ) : $commands;
}

# a hash must have a single 'byOS' key
sub commandByOS_checkHash {
	my ( $hash ) = @_;
	my $ok = true;
	my @keys = sort keys( %{$hash} );
	if( scalar @keys == 1 ){
		if( !defined( $hash->{byOS} )){
			msgErr( __PACKAGE__."::commandByOS_checkHash() expects a single 'byOS' which has not been found" );
			$ok = false;
		}
	} else {
		msgErr( __PACKAGE__."::commandByOS_checkHash() expects a single 'byOS', but found [ ".join( ', ', @keys )." ] key(s)" );
		$ok = false;
	}
	return $ok;
}

# an item can be either a single string or a byOS hash
sub commandByOS_checkItem {
	my ( $item ) = @_;
	my $ok = true;
	my $ref = ref( $item );
	if( $ref ){
		if( $ref eq 'HASH' ){
			$ok = commandByOS_checkHash( $item );
		} else {
			msgErr( __PACKAGE__."::commandByOS_checkItem() unexpected object found as $item ($ref)" );
			$ok = false;
		}
	}
	return $ok;
}

# expects either a string or an array or a hash with a byOS key
# returns:
# - a true|false error success indicator, false as soon as an error is detectzed
# - a ref to the found array, which may be undef or empty

sub commandByOS_getObject {
	my ( $locals, $opts ) = @_;
	my $ok = true;
	my $obj = $ep->var( $locals, $opts );
	msgDebug( "locals=[".join( ',', @{$locals} )."] got ".chompDumper( $obj ));
	if( $obj ){
		my $ref = ref( $obj );
		if( $ref eq 'ARRAY' ){
			foreach my $it ( @{$obj} ){
				$ok = commandByOS_checkItem( $it );
				last if !$ok;
			}
		} elsif( $ref eq 'HASH' ){
			$ok = commandByOS_checkHash( $obj );

		} elsif( $ref ){
			msgErr( __PACKAGE__."::commandByOS_getObject() unexpected object found in [".join( ', ', @{$locals} )."] configuration: $obj ($ref)" );
			$ok = false;
		}
	}
	return ( $ok, $obj );
}

# a hash is expected to have a byOS key
sub commandByOS_resolveHash {
	my ( $hash ) = @_;
	return $hash->{byOS}{$Config{osname}};
}

# an item can be either a single string or a byOS hash
sub commandByOS_resolveItem {
	my ( $item ) = @_;
	my $ref = ref( $item );
	if( $ref ){
		if( $ref eq 'HASH' ){
			return commandByOS_resolveHash( $item );
		}
		# other cases are expected to have been previously filtered
	}
	return $item;
}

# -------------------------------------------------------------------------------------------------
# Execute an external command through system() system call.
# The provided command is not modified at all. If it should support say --verbose or --[no]colored,
# then these options should be specified by the caller.
# See also: https://perldoc.perl.org/functions/system
# (I):
# - the command to be evaluated and executed
#   can be specified as:
#   > a single string, will be executed through the shell and is so subject to shell interpretation
#   > an object with following keys:
#     - a single command string
#     - a ref to an array of arguments
#     in this case, system() function will not use shell interpretation
#   > or an array of strings or objects
#     the commands will be executed in sequence, regardless of their individual return code
# - an optional options hash with following keys:
#   > macros: a hash of the macros to be replaced where:
#     - key is the macro name, must be labeled in the toops.json as '<macro>' (i.e. between angle brackets)
#     - value is the replacement value
#   > withDummy: whether to honor RunnerVerb.dummy property, defaulting to true
#     to be used when we want execute a (read-only) command in all cases
# (O):
# returns a hash with following keys:
# - success: true|false the consolidated result of each command (true only if all were ok)
# - stdouts: the consolidated stdout's
# - stderrs: the consolidated stderr's
# - results: an array ref of hashes with following keys:
#   > evaluated: the evaluated commands after macros replacements
#   > stdout: stdout as a reference to the array of lines
#   > stderr: stderr as a reference to the array of lines
#   > exit: original exit code of the command
#   > success: true|false

sub commandExec {
	my ( $commands, $opts ) = @_;
	$opts //= {};
	my $result = {
		success => true,
		count => 0,
		results => [],
		stdouts => [],
		stderrs => []
	};
	if( !$commands ){
		msgErr( __PACKAGE__."::commandExec() undefined command" );
		stackTrace();
	}
	my $ref = ref( $commands );
	if( $ref eq 'ARRAY'){
		foreach my $cmd ( @{$commands} ){
			$result = commandExec_item( $cmd, $opts, $result );
		}
	} else {
		$result = commandExec_item( $commands, $opts, $result );
	}
	return $result;
}

# consolidate the results
# (I):
# - the consolidated result (to be returned)
# - the result of the last command

sub commandExec_consolidate {
	my ( $result, $res ) = @_;

	$result->{success} &= $res->{success};
	push( @{$result->{results}}, $res );
	foreach my $it ( @{$res->{stdout}} ){
		chomp $it;
		push( @{$result->{stdouts}}, $it ) if $it;
	}
	foreach my $it ( @{$res->{stderr}} ){
		chomp $it;
		push( @{$result->{stderrs}}, $it ) if $it;
	}
	$result->{count} += 1;

	return $result;
}

# execute a command results
# the command can be either a single string or a hash { command, args }

sub commandExec_item {
	my ( $command, $opts, $result ) = @_;
	# if the command is undefined or empty, just ignore it
	if( !$command ){
		msgVerbose( __PACKAGE__."::commandExec_item() got an empty command" );
		return $result;
	}
	# else execute it
	my $res = {
		stdout => [],
		stderr => [],
		exit => -1,
		success => true,
		evaluated => undef,
		args => undef
	};

	my $ref = ref( $command );
	# command is passed by object -> WITHOUT shell intepretation
	if( $ref eq 'HASH' ){
		msgVerbose( __PACKAGE__."::commandExec_item() got command='".( $command->{command} )."', args=[".join( ',', @{$command->{args}} )."]" );
		$res->{evaluated} = $command->{command};
		$res->{evaluated} = TTP::substituteMacros( $res->{evaluated}, $opts->{macros} ) if $opts->{macros};
		my @args = ();
		foreach my $arg ( @{$command->{args}} ){
			if( $opts->{macros} ){
				push( @args, TTP::substituteMacros( $arg, $opts->{macros} ));
			} else {
				push( @args, $arg );
			}
		}
		$res->{args} = \@args;
		msgVerbose( __PACKAGE__."::commandExec() evaluated to '$res->{evaluated}' args=[".join( ',', @args )."]" );

	} elsif( $ref ){
		msgErr( __PACKAGE__."::commandExec_item() unexpected command type, got '$ref'" );
		TTP::stackTrace();

	# command is passed as a single string -> WITH shell intepretation
	} else {
		msgVerbose( __PACKAGE__."::commandExec_item() got command='".( $command )."'" );
		$res->{evaluated} = $command;
		$res->{evaluated} = TTP::substituteMacros( $res->{evaluated}, $opts->{macros} ) if $opts->{macros};
		msgVerbose( __PACKAGE__."::commandExec() evaluated to '$res->{evaluated}'" );
	}

	# and go
	my $withDummy = true;
	$withDummy = $opts->{withDummy} if defined $opts->{withDummy};
	if( $withDummy && $ep->runner()->dummy()){
		msgDummy( $res->{evaluated} );
	} else {
		# https://stackoverflow.com/questions/799968/whats-the-difference-between-perls-backticks-system-and-exec
		# as of v4.12 choose to use system() instead of backtits, this later not returning stderr
		my ( $res_out, $res_err, $res_code );
		if( $res->{args} ){
			( $res_out, $res_err, $res_code ) = capture { system( $res->{evaluated}, @{$res->{args}} ); };
		} else {
			( $res_out, $res_err, $res_code ) = capture { system( $res->{evaluated} ); };
		}
		# https://www.perlmonks.org/?node_id=81640
		# Thus, the exit value of the subprocess is actually ($? >> 8), and $? & 127 gives which signal, if any, the
		# process died from, and $? & 128 reports whether there was a core dump.
		# https://ss64.com/nt/robocopy-exit.html
		$res->{exit} = $res_code;
		$res->{success} = ( $res_code == 0 ) ? true : false;
		msgVerbose( "TTP::commandExec() return_code=$res_code firstly interpreted as success=".( $res->{success} ? 'true' : 'false' ));
		if( $res->{evaluated} =~ /^\s*robocopy/i ){
			$res_code = ( $res_code >> 8 );
			$res->{success} = ( $res_code <= 7 ) ? true : false;
			msgVerbose( "TTP::commandExec() robocopy specific interpretation res=$res_code success=".( $res->{success} ? 'true' : 'false' ));
		}
		# stdout
		chomp $res_out;
		msgVerbose( "TTP::commandExec() stdout='$res_out'" );
		my @res_out = split( /[\r\n]/, $res_out );
		$res->{stdout} = \@res_out;
		# stderr
		chomp $res_err;
		msgVerbose( "TTP::commandExec() stderr='$res_err'" );
		my @res_err = split( /[\r\n]/, $res_err );
		$res->{stderr} = \@res_err;
	}
	msgVerbose( "TTP::commandExec() success=".( $res->{success} ? 'true' : 'false' ));
	$result = commandExec_consolidate( $result, $res );
	return $result;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'archives.periodicDir' directory, which may be undef very early in the bootstrap process
#   and at least not definitive while the node has not been instanciated/loaded/evaluated

sub dbmsArchivesPeriodic {
	return TTP::Path::dbmsArchivesPeriodic( @_ );
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'archives.rootDir' directory, which may be undef very early in the bootstrap process
#   and at least not definitive while the node has not been instanciated/loaded/evaluated

sub dbmsArchivesRoot {
	return TTP::Path::dbmsArchivesRoot( @_ );
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'backups.periodicDir' directory, which may be undef very early in the bootstrap process
#   and at least not definitive while the node has not been instanciated/loaded/evaluated

sub dbmsBackupsPeriodic {
	return TTP::Path::dbmsBackupsPeriodic( @_ );
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'backups.rootDir' directory, which may be undef very early in the bootstrap process
#   and at least not definitive while the node has not been instanciated/loaded/evaluated

sub dbmsBackupsRoot {
	return TTP::Path::dbmsBackupsRoot( @_ );
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
# remotely execute the provided command
# (I):
# - the target node
# - the command to be executed, defaulting to the current command, verb and arguments
# (O):
# - doesn't return anything
# - set the runner errors count to the return code of the command

sub execRemote {
	my ( $target, $command ) = @_;

	# a target is mandatory
	if( !$target ){
		msgErr( __PACKAGE__."::execRemote() expects a target, not specified" );
		TTP::stackTrace();
	}
	my $targetNode = TTP::Node->new( $ep, { node => $target });

	# get the source part of the command
	my $commands = commandByOS([ 'execRemote', 'source' ]);
	my $source_command = ( $commands && scalar( @{$commands} )) ? $commands->[0] : "ssh <TARGET_NAME>";

	# get the target part of the command
	$commands = commandByOS([ 'execRemote', 'target' ], { jsonable => $targetNode });
	my $target_command = ( $commands && scalar( @{$commands} )) ? $commands->[0] : ". ~/.ttp_remote;";

	# build the full command
	$commands = commandByOS([ 'execRemote', 'full' ]);
	my $full_remote = ( $commands && scalar( @{$commands} )) ? $commands->[0] : "<SOURCE_COMMAND> \"<TARGET_COMMAND> <ORIGINAL_COMMAND>\"";

	# command defaults to the current command and verb and its arguments
	$command = $ep->runner()->command()." ".join( " ", @{$ep->runner()->argv()} ) if !$command;

	$full_remote = substituteMacros( $full_remote, {
		ORIGINAL_COMMAND => $command,
		SOURCE_COMMAND => $source_command,
		TARGET_COMMAND => $target_command,
		TARGET_NAME => $target
	});

	# and execute
	msgOut( __PACKAGE__."::execRemote() $full_remote" );
	my $rc = system( $full_remote );
	$ep->runner()->runnableErrs( $rc );
}

# ------------------------------------------------------------------------------------------------
# (I):
# - an optional options hash with following keys:
#   > config: host configuration (useful when searching for a remote host)
#   > makeDirExist: whether to create the directory if it doesn't yet exist, defaulting to true
# (O):
# - the (maybe daily) execution reports directory

sub execReportsDir {
	return TTP::Path::execReportsDir( @_ );
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
	$args //= {};
	$args->{data} //= {};
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

# build the macros hash from (completed) data

sub _executionReportBuildMacros {
	my ( $data ) = @_;
	# protect double-quotes against shell interpretation
	my $str = encode_json( $data );
	$str =~ s/"/\\"/g;
	my $macros = {
		COMMAND => $ep->runner()->command(),
		JSON => $str,
		NODE => $data->{node} || $ep->node()->name(),
		OPTIONS => '',
		SERVICE => $data->{service} || '',
		STAMP => Time::Moment->now->strftime( '%Y%m%d%H%M%S%6N' ),
		VERB => $ep->runner()->verb()
	};
	return $macros;
}

# Complete the provided data with the data collected by TTP

sub _executionReportCompleteData {
	my ( $data ) = @_;
	$data->{cmdline} = "$0 ".join( ' ', @{$ep->runner()->runnableArgs()} );
	$data->{command} = $ep->runner()->command();
	$data->{verb} = $ep->runner()->verb();
	$data->{node} = $ep->node()->name();
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
		my $macros = _executionReportBuildMacros( $data );
		my $commands = TTP::commandByOS([ 'executionReports', 'withFile' ]);
		if( !$commands || !scalar( @{$commands} )){
			my $dropdir = TTP::Path::execReportsDir();
			my $template = 'report-'.Time::Moment->now->strftime( '%y%m%d%H%M%S' ).'-XXXXXX';
			$commands = [ "ttp.pl writejson -dir $dropdir -template $template -suffix .json -data \"<JSON>\"" ];
		}
		my $result = TTP::commandExec( $commands, { macros => $macros });
		$res = $result->{success};
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
#   > topic, as a string, defaulting to <node>/executionReport/<command>/<verb>
#   > options, as a string
#   > excludes, the list of data keys to be excluded

sub _executionReportToMqtt {
	my ( $args ) = @_;
	my $res = false;
	my $data = undef;
	$data = $args->{data} if defined $args->{data};
	if( defined $data ){
		$data = _executionReportCompleteData( $data );
		my $macros = _executionReportBuildMacros( $data );
		# have a topic
		my $topic = $args->{topic};
		$topic = $ep->node()->name()."/executionReport/".$ep->runner()->command()."/".$ep->runner()->verb() if !$topic;
		# have a command
		my $commands = TTP::commandByOS([ 'executionReports', 'withMqtt' ]);
		if( !$commands || !scalar( @{$commands} )){
			$commands = [ "mqtt.pl publish -topic <TOPIC>/<KEYNAME> -payload \"<KEYVALUE>\" -retain <OPTIONS>" ];
		}
		# publish each key
		my $excludes = [];
		$excludes = $args->{excludes} if defined $args->{excludes} && ref $args->{excludes} eq 'ARRAY' && scalar $args->{excludes} > 0;
		foreach my $key ( keys %{$data} ){
			if( grep( /$key/, @{$excludes} )){
				msgVerbose( "do not publish excluded '$key' key" );
			} else {
				$macros->{TOPIC} = $topic;
				$macros->{KEYNAME} = $key;
				$macros->{KEYVALUE} = $data->{$key};
				my $result = TTP::commandExec( $commands, { macros => $macros });
				$res = $result->{success};
			}
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
# - the command string, or a ref to an array of command strings
# - an optional options argument to be passed to TTP::commandExec()
# (O):
# - a ref to an array of stdout outputed lines, having removed the "[command.pl verb]" lines

sub filter {
	my ( $commands, $opts ) = @_;
	$opts //= {};

	my @result = ();
	my $res = TTP::commandExec( $commands, $opts );
	foreach my $item ( @{$res->{results}} ){
		foreach my $it ( @{$item->{stdout}} ){
			$it =~ s/^\s*//;
			$it =~ s/\s*$//;
			push( @result, $it ) if $it !~ /\(DBG|DUM|ERR|VER|WAR\)/ && $it !~ /^\[\w[\w\.\s]*\]/;
		}
	}

	return \@result;
}

# -------------------------------------------------------------------------------------------------
# returns a new unique temp filename built with the qualifiers and a random string
# (I):
# - an optional options args with following keys:
#   > suffix: a filename suffix, defaulting to empty

sub getTempFileName {
	my ( $args ) = @_;
	$args //= {};

	my $fname = $ep->runner()->runnableBNameShort();
	my @qualifiers = @{$ep->runner()->runnableQualifiers()};
	if( scalar( @qualifiers ) > 0 ){
		shift( @qualifiers );
		$fname .= "-".join( '-', @qualifiers );
	}
	
	# starting with v4.26, use String::Random instead of a UUID
	#my $random = random();
	my $sr = String::Random->new();
	$sr->{'.'} = [ 'a'..'z', '0'..'9' ];
	my $random = $sr->randpattern( '............' );

	my $suffix = $args->{suffix} // '';
	my $tempfname = File::Spec->catfile( logsCommands(), "${fname}-${random}${suffix}.tmp" );
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
	return TTP::Path::logsCommands( @_ );
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'logsDaily' directory, which may be undef very early in the bootstrap process
#   and at least not definitive while the node has not been instanciated/loaded/evaluated

sub logsDaily {
	msgWarn( "TTP::logsDaily() is deprecated in favor of TTP:logsPeriodic(). You should update your code." );
	return TTP::Path::logsPeriodic( @_ );
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'logsMain' full pathname, which may be undef very early in the bootstrap process
#   and at least not definitive while the node has not been instanciated/loaded/evaluated

sub logsMain {
	return TTP::Path::logsMain( @_ );
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'logsPeriodic' directory, which may be undef very early in the bootstrap process
#   and at least not definitive while the node has not been instanciated/loaded/evaluated

sub logsPeriodic {
	return TTP::Path::logsPeriodic( @_ );
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'logsRoot' directory, which may be undef very early in the bootstrap process
#   and at least not definitive while the node has not been instanciated/loaded/evaluated

sub logsRoot {
	return TTP::Path::logsRoot( @_ );
}

# ------------------------------------------------------------------------------------------------
# (I):
# - scalar
# - scalar
# (O):
# - the bigger of the two scalars

sub max {
	return $_[$_[0] < $_[1]];
}

# ------------------------------------------------------------------------------------------------
# (I):
# - scalar
# - scalar
# (O):
# - the lower of the two scalars

sub min {
	return $_[$_[0] > $_[1]];
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
	TTP::stackTrace();
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
# Substitute the macros in a string, array or hash (values)
# Always honors <NODE> macro which defaults to current execution node
# Macros must be specified as {
#	MACRO => value
# }
# To deal with the case where a macro embeds another macro, we iter while the result changes.
# (I):
# - the value to be substituted, which can be a scalar, or an array, or a hash
# - a hash ref where keys are the macro the be substituted and values are the substituted value
# (O):
# - substituted value

sub substituteMacros {
	my ( $data, $macros ) = @_;

	# safery guard when the caller doesn't provide any data
	return $data if !$data;

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
		my $prev;
		do {
			$prev = $data;
			foreach my $it ( keys %{$macros} ){
				$data =~ s/<$it>/$macros->{$it}/g;
			}
			if( !defined $macros->{NODE} && $ep->node()){
				my $executionNode = $ep->node()->name();
				$data =~ s/<NODE>/$executionNode/g;
			}
		# when output data is same than prev data, then all has been changed and nothing we are capable of is left
		} while( $data ne $prev );
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
# Returns the max version string of the defined TTP trees
# (I):
# - none
# (O):
# - the found version string or undef

sub version {
	my $version = undef;

	# compute the max found version
	my $versions = TTP::versions();
	foreach my $it ( @{$versions} ){
		if( $version ){
			if( $it > $version ){
				$version = $it;
			}
		} else {
			$version = $it;
		}
	}

	# on Windows SemVer 0.10.0, '$version' is a single string instead of being a SemVer object
	return ref( $version ) ? $version->normal : $version;
}

# -------------------------------------------------------------------------------------------------
# Returns the list of inline versions
# (I):
# - none
# (O):
# - a ref to the array of inline versions

sub versions {
	my $versions = [];

	# simpler than provide a code ref to IFindable
	my @roots = split( /$Config{path_sep}/, $ENV{TTP_ROOTS} );
	foreach my $it ( @roots ){
		my $parent = dirname( $it );
		my $candidate = File::Spec->catfile( $parent, ".VERSION" );
		if( -r $candidate ){
			my $version = path( $candidate )->slurp_utf8;
			chomp $version;
			push( @{$versions}, SemVer->new( $version ));
		}
	}

	return $versions;
}

1;
