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
#
# An indirection level between the verb scripts and the underlying product-specialized packages
#(Win32::SqlServer, PostgreSQL and MariaDB are involved)

package TTP::DBMS;
die __PACKAGE__ . " must be loaded as TTP::DBMS\n" unless __PACKAGE__ eq 'TTP::DBMS';

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Data::Dumper;
use File::Path;
use File::Spec;
use Module::Load;
use Path::Tiny qw( path );
use Time::Moment;

use TTP;
use TTP::Constants qw( :all );
use TTP::Message qw( :all );
use TTP::Path;

### Private methods

# ------------------------------------------------------------------------------------------------
# returns the first account defined for this DBMS service
# (I):
# - none
# (O):
# - an array ( username, password )

sub _getCredentials {
	my ( $self ) = @_;

	my $credentials = TTP::Credentials::get([ 'services', $self->service()->name() ], { jsonable => $self->node() });
	#print STDERR "credentials=".TTP::chompDumper( $credentials ).EOL;
	my $account = undef;
	my $passwd = undef;

	if( $credentials ){
		$account = ( keys %{$credentials} )[0];
		$passwd = $credentials->{$account};
		msgVerbose( __PACKAGE__."::_getCredentials() got account='".( $account || '(undef)' )."'" );

	} else {
		msgErr( __PACKAGE__."::_getCredentials() unable to get credentials with provided arguments" );
	}

	return ( $account, $passwd );
}

### Public methods

# ------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - whether listing the databases should exclude the system databases

sub excludeSystemDatabases {
	my ( $self ) = @_;

	my $exclude = $self->service()->var([ 'DBMS', 'excludeSystemDatabases' ]);
	$exclude = true if !defined $exclude;

	return $exclude;
}

# -------------------------------------------------------------------------------------------------
# returns the list of databases in this DBMS
# this base method tries to returns the cached list of previously got databases, else returns undef
# (I):
# - none
# (O):
# - the list of databases in the instance as an array ref, may be empty, or undef if not yet cached

sub getDatabases {
	my ( $self ) = @_;

	my $databases = $self->{_dbms}{databases};

	return $databases;
}

# -------------------------------------------------------------------------------------------------
# returns the list of tables in the database
# (I):
# - the database to list the tables from
# (O):
# - undef here

sub getDatabaseTables {
	my ( $self, $database ) = @_;

	msgWarn( __PACKAGE__."::getDatabaseTables() should not run there" );

	return undef;
}

# -------------------------------------------------------------------------------------------------
# returns the list of properties of the DBMS service
# (I):
# - none
# (O):
# - the list of properties as a { name, value } array ref

sub getProperties {
	my ( $self, $database ) = @_;


	return [];
}

# ------------------------------------------------------------------------------------------------
# Getter/Setter
# (I):
# - an optional hosting node
# (O):
# - returns the hosting node, defaulting to the current execution node

sub node {
	my ( $self, $node ) = @_;

	if( defined( $node )){
		my $ref = ref( $node );
		if( $ref eq 'TTP::Node' ){
			$self->{_dbms}{node} = $node;
			msgVerbose( __PACKAGE__."::node() set hosting node='".$node->name()."'" );
		} else {
			msgErr( __PACKAGE__."::node() expects a TTP::Node, got '$ref'" );
		}
	}

	return $self->{_dbms}{node};
}

# ------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - returns the TTP::Service this DBMS belongs to

sub service {
	my ( $self ) = @_;

	return $self->{_dbms}{service};
}

# ------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - whether this DBMS instance is only bound to local connections, defaulting to true

sub wantsLocal {
	my ( $self ) = @_;

	my $wantsLocal = $self->service()->var([ 'DBMS', 'wantsLocal' ]);
	$wantsLocal = true if !defined $wantsLocal;

	return $wantsLocal;
}

### Class methods

# -------------------------------------------------------------------------------------------------
# Constructor
# (I):
# - the TTP EP entry point
# - an argument object with following keys:
#   > service: the TTP::Service object this DBMS belongs to
# (O):
# - this object, or undef in case of an error

sub new {
	my ( $class, $ep, $args ) = @_;
	$class = ref( $class ) || $class;
	$args //= {};
	my $self = $class->SUPER::new( $ep, $args );
	bless $self, $class;

	$self->{_dbms} = {};

	if( $args->{service} ){
		my $ref = ref( $args->{service} );
		if( $ref eq 'TTP::Service' ){
			$self->{_dbms}{service} = $args->{service};
			msgVerbose( __PACKAGE__."::new() service='".$args->{service}->name()."'" );
		} else {
			msgErr( __PACKAGE__."::new() expects 'service' be a TTP::Service, got '$ref'" );
			$self = undef;
		}
	} else {
		msgErr( __PACKAGE__."::new() service argument is mandatory, but is not specified" );
		$self = undef;
	}

	return $self;
}

# -------------------------------------------------------------------------------------------------
# Destructor
# (I):
# - instance
# (O):

sub DESTROY {
	my $self = shift;
	$self->SUPER::DESTROY();
	return;
}

### Global functions
### Note for the developer: while a global function doesn't take any argument, it can be called both
### as a class method 'TTP::Package->method()' or as a global function 'TTP::Package::method()',
### the former being preferred (hence the writing inside of the 'Class methods' block).

# -------------------------------------------------------------------------------------------------
# Backup a database
# (I):
# - parms is a hash ref with following keys:
#   > database: mandatory
#   > output: optional
#   > mode: full-diff, defaulting to 'full'
#   > compress: true|false
# returns a hash reference with:
# - status: true|false
# - output: the output filename (even if provided on input)

sub backupDatabase {
	my ( $self, $parms ) = @_;
	my $result = { status => false };
	msgErr( __PACKAGE__."::backupDatabase() database is mandatory, but is not specified" ) if !$parms->{database};
	msgErr( __PACKAGE__."::backupDatabase() mode must be 'full' or 'diff', found '$parms->{mode}'" ) if $parms->{mode} ne 'full' && $parms->{mode} ne 'diff';
	if( !TTP::errs()){
		if( !$parms->{output} ){
			$parms->{output} = $self->computeDefaultBackupFilename( $parms );
		}
		msgOut( "backuping to '$parms->{output}'" );
		my $res = $self->toPackage( 'apiBackupDatabase', $parms );
		$result->{status} = $res->{ok};
	}
	$result->{output} = $parms->{output};
	if( !$result->{status} ){
		msgErr( __PACKAGE__."::backupDatabase() ".$self->instance()."\\$parms->{database} NOT OK" );
	} else {
		msgVerbose( __PACKAGE__."::backupDatabase() returning status='true' output='$result->{output}'" );
	}
	return $result;
}

# ------------------------------------------------------------------------------------------------
# compute the default backup output filename for the current machine/intance/database
# making sure the output directory exists
# As of 2024 -1-31, default output filename is <host>-<instance>-<database>-<date>-<time>-<mode>.backup
# As of 2024 -2- 2, the backupDir is expected to be daily-ised, ie to contain a date part
# (I):
# - dbms, the DBMS object from _buildDbms()
# - parms is a hash ref with keys:
#   > database name: mandatory
#   > mode: defaulting to 'full'
# (O):
# - the default output full filename

sub computeDefaultBackupFilename {
	my ( $self, $parms ) = @_;
	#msgVerbose( __PACKAGE__."::computeDefaultBackupFilename() entering" );
	my $output = undef;
	msgErr( __PACKAGE__."::computeDefaultBackupFilename() database is mandatory, but is not specified" ) if !$parms->{database};
	my $mode = 'full';
	$mode = $parms->{mode} if defined $parms->{mode};
	msgErr( __PACKAGE__."::computeDefaultBackupFilename() mode must be 'full' or 'diff', found '$mode'" ) if $mode ne 'full' and $mode ne 'diff';
	# compute the dir and make sure it exists
	my $node = $self->ep()->node();
	my $backupDir = TTP::dbmsBackupsPeriodic();
	TTP::Path::makeDirExist( $backupDir );
	# compute the filename
	my $fname = $node->name().'-'.$self->instance()."-$parms->{database}-".( Time::Moment->now->strftime( '%y%m%d-%H%M%S' ))."-$mode.backup";
	$output = File::Spec->catdir( $backupDir, $fname );
	msgVerbose( __PACKAGE__."::computeDefaultBackupFilename() computing output default as '$output'" );
	return $output;
}

# -------------------------------------------------------------------------------------------------
# check that the specified database exists in the instance
# (I):
# - the database name
# (O):
# returns true|false

sub databaseExists {
	my ( $self, $database ) = @_;
	my $exists = false;

	if( $database ){
		my $list = $self->getDatabases();
		$exists = true if grep( /$database/i, @{$list} );
		if( $self->ep()->runner()->dummy()){
			msgDummy( "considering exists='true'" );
			$exists = true;
		}
	} else {
		msgErr( __PACKAGE__."::databaseExists() database is mandatory, but is not specified" );
	}

	msgVerbose( "checkDatabaseExists() database='".( $database || '(undef)' )."' returning ".( $exists ? 'true' : 'false' ));
	return $exists;
}

# -------------------------------------------------------------------------------------------------
# execute a sql command
# (I):
# - the command string to be executed
# - an optional options hash which may contain following keys:
#   > tabular: whether to format data as tabular data, defaulting to true
#   > json: an output file where data is to be saved
#   > multiple: whether we expect several result sets, defaulting to false
# (O):
# returns a hash ref with following keys:
# - ok: true|false
# - result: an array ref to hash results

sub execSqlCommand {
	my ( $self, $command, $opts ) = @_;
	$opts //= {};
	my $parms = {
		command => $command,
		opts => $opts
	};
	my $result = $self->toPackage( 'apiExecSqlCommand', $parms );
	#print Dumper( $parms );
	#print Dumper( $result );
	#print Dumper( $opts );
	if( $result && $result->{ok} ){
		# tabular output if asked for
		my $tabular = true;
		$tabular = $opts->{tabular} if defined $opts->{tabular};
		if( $tabular ){
			TTP::displayTabular( $result->{result} );
		} else {
			msgVerbose( "do not display tabular result as opts->{tabular}='false'" );
		}
		# json output if asked for
		my $json = '';
		$json = $opts->{json} if defined $opts->{json};
		if( $json ){
			TTP::jsonOutput( $result->{result}, $json );
		} else {
			msgVerbose( "do not save JSON result as opts->{json} is not set" );
		}
		# columns names output if asked for
		# pwi 2024-12-23 doesn't work in Win23::SQLServer so ignored at the moment
		#my $columns = '';
		#$columns = $opts->{columns} if defined $opts->{columns};
		#if( $columns ){
		#	$self->columnsOutput( $command, $columns );
		#} else {
		#	msgVerbose( "do not save columns names as opts->{columns} is not set" );
		#}
	}
	return $result;
}

# -------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# returns the name of the package which manages this DBMS

#sub package {
#	my ( $self ) = @_;
#
#	return $self->{_dbms}{package};
#}

# ------------------------------------------------------------------------------------------------
# Restore a file into a database
# (I):
# - parms is a hash ref with keys:
#   > database: mandatory
#   > full: mandatory, the full backup file
#   > diff: optional, the diff backup file
#   > verifyonly: whether we want only check the restorability of the provided file
# (O):
# - returns true|false

sub restoreDatabase {
	my ( $self, $parms ) = @_;
	my $result = undef;
	msgErr( __PACKAGE__."::restoreDatabase() database is mandatory, but is not specified" ) if !$parms->{database} && !$parms->{verifyonly};
	msgErr( __PACKAGE__."::restoreDatabase() full backup is mandatory, but is not specified" ) if !$parms->{full};
	msgErr( __PACKAGE__."::restoreDatabase() $parms->{diff}: file not found or not readable" ) if $parms->{diff} && ! -f $parms->{diff};
	if( !TTP::errs()){
		$result = $self->toPackage( 'apiRestoreDatabase', $parms );
	}
	if( $result && $result->{ok} ){
		msgVerbose( __PACKAGE__."::restoreDatabase() returning status='true'" );
	} else {
		msgErr( __PACKAGE__."::restoreDatabase() ".$self->instance()."\\$parms->{database} NOT OK" );
	}
	return $result && $result->{ok};
}

# -------------------------------------------------------------------------------------------------
# address a function in the package which deserves the instance
#  and returns the result which is expected to be a hash with (at least) a 'ok' key, or undef
# (I):
# - the name of the function to be called
# - an optional options hash to be passed to the function
# (O):
# - the result

#sub toPackage {
#	my ( $self, $fname, $parms ) = @_;
#	msgVerbose( __PACKAGE__."::toPackage() entering with fname='".( $fname || '(undef)' )."'" );
#	my $result = undef;
#	if( $fname ){
#		my $package = $self->package();
#		Module::Load::load( $package );
#		if( $package->can( $fname )){
#			$result = $package->$fname( $self, $parms );
#		} else {
#			msgWarn( __PACKAGE__."::toPackage() package '$package' says it cannot '$fname'" );
#		}
#	} else {
#		msgErr( __PACKAGE__."::toPackage() function name must be specified" );
#	}
#	msgVerbose( __PACKAGE__."::toPackage() returning with result='".( defined $result ? ( $result->{ok} ? 'true':'false' ) : '(undef)' )."'" );
#	return $result;
#}

1;

__END__
