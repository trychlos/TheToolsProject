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
# compute the default backup output filename for the current machine/service/database
# making sure the output directory exists
# As of 2024 -1-31, default output filename is <host>-<instance>-<database>-<date>-<time>-<mode>.backup
# As of 2024 -2- 2, the backupDir is expected to be daily-ised, ie to contain a date/time part
# As of 2025- 6-10, the instance is replaced with the service
# (I):
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
	my $node = $self->node();
	my $backupDir = TTP::dbmsBackupsPeriodic();
	TTP::Path::makeDirExist( $backupDir );
	# compute the filename
	my $fname = $node->name().'-'.$self->service()->name()."-$parms->{database}-".( Time::Moment->now->strftime( '%y%m%d-%H%M%S' ))."-$mode.backup";
	$output = File::Spec->catdir( $backupDir, $fname );
	msgVerbose( __PACKAGE__."::computeDefaultBackupFilename() computing output default as '$output'" );
	return $output;
}

# ------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - the configured connection string, may be undef

sub connectionString {
	my ( $self ) = @_;

	my $str = $self->service()->var([ 'DBMS', 'host' ]);

	return $str;
}

# -------------------------------------------------------------------------------------------------
# check that the specified database exists in the DBMS
# (I):
# - the database name
# (O):
# - returns true|false

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
		TTP::stackTrace();
	}

	msgVerbose( __PACKAGE__."::databaseExists() database='".( $database || '(undef)' )."' returning ".( $exists ? 'true' : 'false' ));
	return $exists;
}

# -------------------------------------------------------------------------------------------------
# check that the specified database is not filtered by the configured limited view
# (I):
# - the database name
# (O):
# - returns whether the database is filtered by the configured limited view: true|false

sub dbFilteredbyLimit {
	my ( $self, $database ) = @_;

	my $limited = $self->viewedDatabases();

	my $filtered = ( $limited && grep( /^$database$/, @{$limited} ));

	return $filtered;
}

# -------------------------------------------------------------------------------------------------
# check that the specified database is not filtered as a system database
# (I):
# - the database name
# - the list of system databases
# (O):
# - returns whether the database is filtered as a system database: true|false

sub dbFilteredBySystem {
	my ( $self, $database, $systems ) = @_;

	my $filtered = ( $self->excludeSystemDatabases() && grep( /^$database$/, @{$systems} ));

	return $filtered;
}

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

	my $props = [];

	push( @{$props}, { name => 'excludeSystemDatabases', value => $self->excludeSystemDatabases() ? 'true' : 'false' });
	push( @{$props}, { name => 'wantsLocal', value => $self->wantsLocal() ? 'true' : 'false' });
	push( @{$props}, { name => 'package', value => $self->package() });
	push( @{$props}, { name => 'connectionString', value => $self->connectionString() || '(undef)' });

	return $props;
}

# ------------------------------------------------------------------------------------------------
# Getter/Setter
# (I):
# - an optional hosting node
# (O):
# - returns the hosting TTP::Node node, defaulting to the current execution node

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

# -------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# returns the name of the package which manages this DBMS

sub package {
	my ( $self ) = @_;

	return ref( $self );
}

# ------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - returns the server or the connection string as configured in the DBMS service

sub server {
	my ( $self ) = @_;

	my $server = $self->service()->var([ 'DBMS', 'host' ], $self->node()) || $self->node()->name();

	return $server;
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
# - the list of the databases this services is limited to view, or undef if no limit is set

sub viewedDatabases {
	my ( $self ) = @_;

	my $limit = $self->service()->var([ 'DBMS', 'databases' ]);

	return $limit;
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

1;

__END__
