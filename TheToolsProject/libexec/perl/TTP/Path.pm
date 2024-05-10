# Copyright (@) 2023-2024 PWI Consulting
#
# Various paths management
#
# The integrator must configure:
#
# - as environment variables:
#
#   > TTP_CONFDIR: as the path to the tree which contains all configurations files, and specially 'toops.json'
#     it is suggested that this configuration tree be outside of the Toops installation
#     it is addressed by siteConfigurationsDir()
#     the structure is fixed at the moment:
#
#       TTP_CONFDIR/
#        |
#        +- toops.json
#            |
#            +- daemons/
#            |
#            +- machines/
#
# - in toops.json:
#
#   > logsRoot: the root of the logs tree
#     is is used by logsRootDir()
#     this package takes care of creating it if it doesn't exist yet

package TTP::Path;

use strict;
use warnings;

use Config;
use Data::Dumper;
use File::Path qw( make_path );
use File::Spec;
use Time::Piece;
use vars::global qw( $ep );

use TTP;
use TTP::Constants qw( :all );
use TTP::Message qw( :all );

# ------------------------------------------------------------------------------------------------
# (O):
# - the credentials directory
sub credentialsDir {
	my ( $opts ) = @_;
	$opts //= {};
	my $dir = $ep->var([ 'credentialsDir' ], $opts );
	if( !defined $dir || !length $dir ){
		msgWarn( "'credentialsDir' is not defined in toops.json nor in host configuration" );
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
		msgWarn( "'archivesDir' is not defined in toops.json nor in host configuration" );
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
		msgWarn( "'archivesRoot' is not defined in toops.json nor in host configuration" );
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
		msgWarn( "'backupsDir' is not defined in toops.json nor in host configuration" );
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
		msgWarn( "'backupsRoot' is not defined in toops.json nor in host configuration" );
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
		msgWarn( "'executionReports/withFile/dropDir' is not defined in toops.json nor in host configuration" );
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
	msgErr( "Path::fromCommand() command is not specified" ) if !$cmd;
	my $path = undef;
	if( !TTP::errs()){
		$path = `$cmd`;
		msgErr( "Path::fromCommand() command doesn't output anything" ) if !$path;
	}
	if( !TTP::errs()){
		my @words = split( /\s+/, $path );
		if( scalar @words < 2 ){
			msgErr( "Path::fromCommand() expect at least two words" );
		} else {
			$path = $words[scalar @words - 1];
			msgErr( "Path::fromCommand() found an empty path" ) if !$path;
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
# (I):
# - optionally a hostname, defaulting to the current host
#   remind that Unix has case sensitive filesystems, while Windows has not - we do not modify here the case
# (O):
# returns the full path of the host configuration file
sub hostConfigurationPath {
	my ( $host ) = @_;
	$host = TTP::host() if !$host;
	return File::Spec->catfile( hostsConfigurationsDir(), "$host.json" );
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
	my $result = false;
	if( -d $dir ){
		#msgVerbose( "Path::makeDirExist() dir='$dir' exists" );
		$result = true;
	} else {
		# why is that needed in TTP::Path !?
		TTP::Message::msgVerbose( "Path::makeDirExist() make_path() dir='$dir'" ) if $allowVerbose;
		my $error;
		$result = true;
		make_path( $dir, {
			verbose => $ep->runner()->verbose(),
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
		# why is that needed in TTP::Path !?
		TTP::Message::msgVerbose( "Path::makeDirExist() dir='$dir' result=$result" ) if $allowVerbose;
	}
	return $result;
}

# -------------------------------------------------------------------------------------------------
# Remove the trailing character
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
sub removeTrailingSeparator {
	my $dir = shift;
	my $sep = File::Spec->catdir( '' );
	return removeTrailingChar( $dir, $sep );
}

# ------------------------------------------------------------------------------------------------
# (I):
# - the service name
# (O):
# returns the full pathname of the service JSON configuration file
sub serviceConfigurationPath {
	my ( $service ) = @_;
	return File::Spec->catfile( servicesConfigurationsDir(), "$service.json" );
}

# ------------------------------------------------------------------------------------------------
# (O):
# returns the dir which contains services configuration files
# at the moment, a non-configurable subdirectory of TTP_CONFDIR
sub servicesConfigurationsDir {
	return File::Spec->catdir( siteConfigurationsDir(), "services" );
}

# ------------------------------------------------------------------------------------------------
sub siteConfigurationsDir {
	msgErr( "TTP_CONFDIR is not found in your environment, but is required" ) if !$ENV{TTP_CONFDIR};
	return $ENV{TTP_CONFDIR};
}

# ------------------------------------------------------------------------------------------------
sub siteRoot {
	return $ep->var([ 'siteRoot' ]);
}

# ------------------------------------------------------------------------------------------------
sub toopsConfigurationPath {
	return File::Spec->catfile( siteConfigurationsDir(), "toops.json" );
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
