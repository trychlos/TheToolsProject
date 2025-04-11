# Copyright (@) 2023-2025 PWI Consulting
#
# Various paths management

package TTP::Path;

use strict;
use utf8;
use warnings;

use Config;
use Data::Dumper;
use File::Copy::Recursive qw( dircopy fcopy );
use File::Find;
use File::Path qw( make_path remove_tree );
use File::Spec;
use Text::Glob qw( match_glob );
use vars::global qw( $ep );

use TTP;
use TTP::Constants qw( :all );
use TTP::Message qw( :all );

# -------------------------------------------------------------------------------------------------
# copy a directory and its content from a source to a target
# TTP allows to provide a system-specific command in its configuration file, defaulting to dircopy()
# or fcopy() if exclusions are specified.
# (I):
# - source path
# - destination path
# - an optional options hash ref with following keys:
#   > 'excludeDirs': a ref to a list of source dir globs to exclude
#   > 'excludeFiles': a ref to a list of source file globs to exclude
#   > 'options': additional options to pass to the (external) command
#   > 'emptyTree': whether to empty the target tree before the copy, defaulting to true
# return true|false

sub copyDir {
	my ( $source, $target, $opts ) = @_;
	$opts //= {};
	my $result = false;
	TTP::Message::msgVerbose( "TTP::Path::copyDir() entering with source='$source' target='$target'" );
	if( ! -d $source ){
		TTP::Message::msgErr( "$source: source directory doesn't exist" );
		return false;
	}
	# remove the target tree before copying
	my $emptyTree = $opts->{emptyTree};
	$emptyTree = true if !defined $emptyTree;
	if( $emptyTree ){
		removeTree( $target );
	} else {
		TTP::Message::msgVerbose( "TTP::Path::copyDir() doesn't empty target tree before copying as emptyTree is false" );
	}
	# have a command or use dircopy() or use fcopy()
	my $command = TTP::commandByOs([ 'copyDir' ]);
	if( $command ){
		TTP::Message::msgVerbose( "TTP::Path::copyDir() found command='$command', executing it" );
		my $cmdres = TTP::commandExec({
			command => $command,
			macros => {
				SOURCE => $source,
				TARGET => $target,
				EXCLUDEDIRS => $opts->{excludeDirs},
				EXCLUDEFILES => $opts->{excludeFiles},
				OPTIONS => $opts->{options}
			}
		});
		$result = $cmdres->{success};

	} elsif( $ep->runner()->dummy()){
		TTP::Message::msgDummy( "TTP::Path::copyDir( $source, $target )" );

	} else {
		if(( $opts->{excludeDirs} && scalar( @{$opts->{excludeDirs}} ) > 0 ) || ( $opts->{excludeFiles} && scalar( @{$opts->{excludeFiles}} ) > 0 )){
			TTP::Message::msgVerbose( "TTP::Path::copyDir() somes exclusions are specified, falling back to TTP::Path::copyFile()" );
			$opts->{work} = {};
			$opts->{work}{source} = $source;
			$opts->{work}{target} = $target;
			$opts->{work}{errors_count} = 0;
			$opts->{work}{makeDirExist} = true;
			find( sub { _copy_to( $opts, $_ ); }, $source );
			$result = !$opts->{work}{errors_count};
			$opts->{work} = undef;
		} else {
			TTP::Message::msgVerbose( "TTP::Path::copyDir() no exclusions are specified, using dircopy()" );
			# https://metacpan.org/pod/File::Copy::Recursive
			# This function returns true or false: for true in scalar context it returns the number of files and directories copied,
			# whereas in list context it returns the number of files and directories, number of directories only, depth level traversed.
			my $res = dircopy( $source, $target );
			$result = $res ? true : false;
			TTP::Message::msgVerbose( "TTP::Path::copyDir() dircopy() res=$res" );
		}
	}
	TTP::Message::msgVerbose( "TTP::Path::copyDir() returns result=".( $result ? 'true' : 'false' ));
	return $result;
}

# a companion subroutine when searching for files to copy
# (I):
# - caller options
# - current filename
# (O):
# - increment opts->{errors_count}

sub _copy_to {
	my ( $opts, $file ) = @_;
	if( $file ne '.' ){
		if( !_copy_match_dir( $File::Find::dir, $opts->{excludeDirs} ) && !_copy_match_file( $file, $opts->{excludeFiles} )){
			my $rel_path = File::Spec->abs2rel( $File::Find::name, $opts->{work}{source} );
			my $dst_file = File::Spec->catfile( $opts->{work}{target}, $rel_path );
			if( !copyFile( $File::Find::name, $dst_file, $opts->{work} )){
				$opts->{work}{errors_count} += 1;
			}
		}
	}
}

# a companion subroutine which try to match dirname agaist excluded dirs
# NB: have to try to match every single component of the provided dirname
# (I):
# - current dir
# - excluded dirs as an array ref
# (O):
# - true if match (dir is excluded)

sub _copy_match_dir {
	my ( $dir, $excluded ) = @_;
	my $match = false;
	my ( $xvol, $xdir, $xfile ) = File::Spec->splitpath( $dir );
	my @dirs = File::Spec->splitdir( $xdir );
	push( @dirs, $xfile );
	OUTER: foreach my $spec ( @{$excluded} ){
		foreach my $component ( @dirs ){
			if( $component ){
				if( match_glob( $spec, $component )){
					$match = true;
					last OUTER;
				}
			}
		}
	}
	return $match;
}

# a companion subroutine which try to match filename agaist excluded files
# (I):
# - caller options
# - current file
# (O):
# - true if match (file is excluded)

sub _copy_match_file {
	my ( $file, $excluded ) = @_;
	my $match = false;
	foreach my $spec ( @{$excluded} ){
		if( match_glob( $spec, $file )){
			$match = true;
			last;
		}
	}
	return $match;
}

# -------------------------------------------------------------------------------------------------
# copy a file from a source to a target
# TTP allows to provide a system-specific command in its configuration file
# (I):
# - source: the source volume, directory and filename
# - target :the target volume and directory
# - an optional options hash ref with following keys:
#   > 'options': additional options to pass to the (external) command
#   > 'makeDirExist', when using fcopy(), whether a source directory must be created on the target, defaulting to false
#      fcopy() default behavior is to refuse to copy just a directory (because it wants copy files!), and returns an error message
#      this option let us reverse this behavior, e.g. when copying a directory tree with empty dirs
# (O):
# return true|false

sub copyFile {
	my ( $source, $target, $opts ) = @_;
	$opts //= {};
	my $result = false;
	TTP::Message::msgVerbose( "TTP::Path::copyFile() entering with source='$source' target='$target'" );
	my $command = TTP::commandByOs([ 'copyFile' ]);
	if( $command ){
		my $cmdres = TTP::commandExec({
			command => $command,
			macros => {
				SOURCE => $source,
				TARGET => $target,
				OPTIONS => $opts->{options}
			}
		});
		$result = $cmdres->{success};

	} elsif( $ep->runner()->dummy()){
		TTP::Message::msgDummy( "TTP::Path::copyFile( $source, $target )" );

	} else {
		# https://metacpan.org/pod/File::Copy
		# This function returns true or false
		my $makeDirExist = $opts->{makeDirExist};
		if( -d $source ){
			if( $makeDirExist ){
				$result = TTP::Path::makeDirExist( $source );
			} else {
				TTP::Message::msgVerbose( "TTP::Path::copyFile() doesn't create directory as makeDirExist is not true" );
				$result = true;
			}
		} else {
			$result = fcopy( $source, $target );
			if( !$result ){
				TTP::Message::msgErr( "TTP::Path::copyFile( $source, $target ) $!" );
			}
		}
	}
	TTP::Message::msgVerbose( "TTP::Path::copyFile() returns result=".( $result ? 'true' : 'false' ));
	return $result;
}

# ------------------------------------------------------------------------------------------------
# (O):
# - the credentials directory
sub credentialsDir {
	my ( $opts ) = @_;
	$opts //= {};
	my $dir = $ep->var([ 'credentialsDir' ], $opts );
	if( !defined $dir || !length $dir ){
		TTP::Message::msgWarn( "'credentialsDir' is not defined in toops.json nor in host configuration" );
	}
	return $dir;
}

# ------------------------------------------------------------------------------------------------
# (O):
# returns the directory which contains the daemons configurations
# at the moment, a non-configurable subdirectory of TTP_CONFDIR
sub daemonsConfigurationsDir {
	return File::Spec->catdir( siteConfigurationsDir(), "daemons" );
}

# ------------------------------------------------------------------------------------------------
# (O):
# the current DBMS archives directory, making sure the dir exists
# the dir can be defined in toops.json, or overriden in host configuration
sub dbmsArchivesDir {
	my $dir = $ep->var([ 'DBMS', 'archivesDir' ]);
	if( !defined $dir || !length $dir ){
		TTP::Message::msgWarn( "'archivesDir' is not defined in toops.json nor in host configuration" );
	}
	return $dir;
}

# ------------------------------------------------------------------------------------------------
# (O):
# the current DBMS archives root tree, making sure the dir exists
# the dir can be defined in toops.json, or overriden in host configuration
sub dbmsArchivesRoot {
	my $dir = $ep->var([ 'DBMS', 'archivesRoot' ]);
	if( !defined $dir || !length $dir ){
		TTP::Message::msgWarn( "'archivesRoot' is not defined in toops.json nor in host configuration" );
	}
	return $dir;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - an optional options hash with following keys:
#   > config: host configuration (useful when searching for a remote host)
# (O):
# the current DBMS backups directory, making sure the dir exists
# the dir can be defined in toops.json, or overriden in host configuration
sub dbmsBackupsDir {
	my ( $opts ) = @_;
	$opts //= {};
	my $dir = $ep->var( [ 'DBMS', 'backupsDir' ], $opts );
	if( defined $dir && length $dir ){
		makeDirExist( $dir );
	} else {
		TTP::Message::msgWarn( "'backupsDir' is not defined in toops.json nor in host configuration" );
	}
	return $dir;
}

# ------------------------------------------------------------------------------------------------
# (O):
# the root the the DBMS backups directories, making sure the dir exists
# the root can be defined in toops.json, or overriden in host configuration
sub dbmsBackupsRoot {
	my $dir = $ep->var([ 'DBMS', 'backupsRoot' ]);
	if( defined $dir && length $dir ){
		makeDirExist( $dir );
	} else {
		TTP::Message::msgWarn( "'backupsRoot' is not defined in toops.json nor in host configuration" );
	}
	return $dir;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - an optional options hash with following keys:
#   > config: host configuration (useful when searching for a remote host)
#   > makeDirExist: whether to create the directory if it doesn't yet exist, defaulting to true
# (O):
# - the (maybe daily) execution reports directory
sub execReportsDir {
	my ( $opts ) = @_;
	$opts //= {};
	my $dir = $ep->var([ 'executionReports', 'withFile', 'dropDir' ], $opts );
	if( defined $dir && length $dir ){
		my $makeDirExist = true;
		$makeDirExist = $opts->{makeDirExist} if exists $opts->{makeDirExist};
		makeDirExist( $dir ) if $makeDirExist;
	} else {
		TTP::Message::msgWarn( "'executionReports/withFile/dropDir' is not defined in toops.json nor in host configuration" );
	}
	return $dir;
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
	TTP::Message::msgErr( "Path::fromCommand() command is not specified" ) if !$cmd;
	my $path = undef;
	if( !TTP::errs()){
		$path = `$cmd`;
		TTP::Message::msgErr( "Path::fromCommand() command doesn't output anything" ) if !$path;
	}
	if( !TTP::errs()){
		my @words = split( /\s+/, $path );
		if( scalar @words < 2 ){
			TTP::Message::msgErr( "Path::fromCommand() expect at least two words" );
		} else {
			$path = $words[scalar @words - 1];
			TTP::Message::msgErr( "Path::fromCommand() found an empty path" ) if !$path;
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

# ------------------------------------------------------------------------------------------------
# (O):
# returns the dir which contains hosts configuration files
# at the moment, a non-configurable subdirectory of TTP_CONFDIR
sub hostsConfigurationsDir {
	return File::Spec->catdir( siteConfigurationsDir(), "machines" );
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
	$allowVerbose = $opts->{allowVerbose} if defined $opts->{allowVerbose};
	$allowVerbose = false if !$ep || !$ep->runner() || !$ep->runner()->verbose();
	my $result = false;
	if( -d $dir ){
		#TTP::Message::msgVerbose( "TTP::Path::makeDirExist() dir='$dir' exists" );
		$result = true;
	} else {
		# why is that needed in TTP::Path !?
		TTP::Message::msgVerbose( "TTP::Path::makeDirExist() make_path() dir='$dir'" ) if $allowVerbose;
		my $error;
		$result = true;
		make_path( $dir, {
			verbose => $allowVerbose,
			error => \$error
		});
		# https://perldoc.perl.org/File::Path#make_path%28-%24dir1%2C-%24dir2%2C-....-%29
		if( $error && @$error ){
			for my $diag ( @$error ){
				my ( $file, $message ) = %$diag;
				if( $file eq '' ){
					TTP::Message::msgErr( $message );
				} else {
					TTP::Message::msgErr( "$file: $message" );
				}
			}
			$result = false;
		}
		# why is that needed in TTP::Path !?
		TTP::Message::msgVerbose( "TTP::Path::makeDirExist() dir='$dir' result=$result" ) if $allowVerbose;
	}
	return $result;
}

# -------------------------------------------------------------------------------------------------
# Remove the trailing character
# (I):
# - the string to work with
# - the character to remove
# (O):
# - the same string without trailing character

sub removeTrailingChar {
	my $line = shift;
	my $char = shift;
	if( substr( $line, -1 ) eq $char ){
		$line = substr( $line, 0, length( $line )-1 );
	}
	return $line;
}

# -------------------------------------------------------------------------------------------------
# Remove the trailing path separator
# (I):
# - the path to work with
# (O):
# - the same path without any trailing path separator

sub removeTrailingSeparator {
	my $dir = shift;
	my $sep = File::Spec->catdir( '' );
	return removeTrailingChar( $dir, $sep );
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
	TTP::Message::msgVerbose( "TTP::Path::removeTree() removing '$dir'" );
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
				TTP::Message::msgErr( "TTP::Path::removeTree.remove_tree() $message" );
			} else {
				TTP::Message::msgErr( "TTP::Path::removeTree.remove_tree() $file: $message" );
			}
		}
		$result = false;
	}
	TTP::Message::msgVerbose( "TTP::Path::removeTree() dir='$dir' result=$result" );
	return $result;
}

# ------------------------------------------------------------------------------------------------
sub siteConfigurationsDir {
	TTP::Message::msgErr( "TTP_CONFDIR is not found in your environment, but is required" ) if !$ENV{TTP_CONFDIR};
	return $ENV{TTP_CONFDIR};
}

# ------------------------------------------------------------------------------------------------
sub siteRoot {
	return $ep->var([ 'siteRoot' ]);
}

# -------------------------------------------------------------------------------------------------
# Make sure we returns a path with a trailing separator
sub withTrailingSeparator {
	my $dir = shift;
	$dir = removeTrailingSeparator( $dir );
	my $sep = File::Spec->catdir( '' );
	$dir .= $sep;
	return $dir;
}

1;
