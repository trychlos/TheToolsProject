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
# A base class for underlying product-specialized packages (Win32::SqlServer, PostgreSQL and MariaDB are involved)

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
# - an optional account, defaulting to the first one found
# (O):
# - an array ( username, password )

sub _getCredentials {
	my ( $self, $account ) = @_;

	my $credentials = TTP::Credentials::get([ 'services', $self->service()->name() ], { jsonable => $self->node() });
	#print STDERR "credentials=".TTP::chompDumper( $credentials ).EOL;
	my $passwd = undef;

	if( $credentials ){
		if( !$account ){
			$account = ( keys %{$credentials} )[0];
		}
		$passwd = $credentials->{$account} || undef;
		msgVerbose( __PACKAGE__."::_getCredentials() got account='".( $account || '(undef)' )."'" );

	} else {
		msgErr( __PACKAGE__."::_getCredentials() unable to get credentials with provided arguments" );
	}

	return ( $account, $passwd );
}

# -------------------------------------------------------------------------------------------------
# check that the specified database is member of the provided list
# (I):
# - the database name
# - an optional string or an optional array ref, each item maybe being a regular expression
# (O):
# - returns whether the database is member of the provided list

sub _isMemberOf {
	my ( $self, $database, $list ) = @_;

	my $member = false;

	if( $list ){
		my $ref = ref( $list );
		if( $ref && $ref ne 'ARRAY' ){
			msgErr( __PACKAGE__."::_isMemberOf() expects an array, got '$ref'" );
		} else {
			my $insensitive = $self->matchInsensitive();
			my @list = $ref ? @{$list} : ( $list );
			foreach my $it ( @list ){
				if(( $insensitive && $database =~ /^$it$/i ) || ( !$insensitive && $database =~ /^$it$/ )){
					$member = true;
					last;
				}
			}
		}
	}

	return $member;
}

### Public methods

# ------------------------------------------------------------------------------------------------
# compute the default backup output filename for the current machine/service/database
# making sure the output directory exists
# As of 2024 -1-31, default output filename is <host>-<instance>-<database>-<date>-<time>-<mode>.backup
# As of 2024 -2- 2, the backupDir is expected to be daily-ised, ie to contain a date/time part
# As of 2025- 5-10, the instance is replaced with the service
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
	if( TTP::errs()){
		TTP::stackTrace();
	} else {
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
# check that the specified database is not filtered by the configured exclusion list
# (I):
# - the database name
# - an optional array ref which list the databases we are limited to, defaulting to excludedDatabases()
# (O):
# - returns whether the database is filtered by the configured limited view: true|false

sub dbFilteredbyExclude {
	my ( $self, $database, $excluded ) = @_;

	$excluded = $self->excludedDatabases() if !$excluded;
	my $filtered = $self->_isMemberOf( $database, $excluded );

	msgVerbose( __PACKAGE__."::dbFilteredbyExclude() filtering database='$database'" ) if $filtered;
	return $filtered;
}

# ------------------------------------------------------------------------------------------------
# check that the specified database is not filtered by the configured limited view
# (I):
# - the database name
# - an optional array ref which list the databases we are limited to, defaulting to limitedDatabases()
# (O):
# - returns whether the database is filtered by the configured limited view: true|false

sub dbFilteredbyLimit {
	my ( $self, $database, $limited ) = @_;

	$limited = $self->limitedDatabases() if !$limited;
	my $filtered = !$self->_isMemberOf( $database, $limited );

	msgVerbose( __PACKAGE__."::dbFilteredbyLimit() filtering database='$database'" ) if $filtered;
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

	my $filtered = ( $self->excludeSystemDatabases() && grep( /^$database$/i, @{$systems} ));

	msgVerbose( __PACKAGE__."::dbFilteredBySystem() filtering database='$database'" ) if $filtered;
	return $filtered;
}

# ------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - the list of the databases this services which are excluded

sub excludedDatabases {
	my ( $self ) = @_;

	my $exclude = $self->service()->var([ 'DBMS', 'excludeDatabases' ]);

	return $exclude;
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
# starting from a raw list of databases, filter out those which are not to be viewed in this service
# (I):
# - the raw list of databases as an array ref of objects with a 'name' property
# - the list of system databases to be considered for this driver
# (O):
# - an array ref of the list of viewed databases,

sub filterGotDatabases {
	my ( $self, $dbs, $systemDbs ) = @_;

	my $databases = [];
	my $limited = $self->limitedDatabases();
	my $excluded = $self->excludedDatabases();
	foreach my $it ( @{$dbs} ){
		my $dbname = $it->{name};
		if( !$self->dbFilteredBySystem( $dbname, $systemDbs ) &&
			( !$limited || !$self->dbFilteredbyLimit( $dbname, $limited )) &&
			( !$excluded || !$self->dbFilteredbyExclude( $dbname, $excluded ))){
				push( @{$databases}, $dbname );
		}
	}
	msgVerbose( __PACKAGE__."::filterGotDatabases() got databases [ ". join( ', ', @{$databases} )." ]" );
	$self->{_dbms}{databases} = $databases;

	return $databases;
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
# Getter
# (I):
# - none
# (O):
# - the list of the databases this services is limited to view, or undef if no limit is set

sub limitedDatabases {
	my ( $self ) = @_;

	my $limit = $self->service()->var([ 'DBMS', 'limitDatabases' ]);
	if( !$limit ){
		$limit = $self->service()->var([ 'DBMS', 'databases' ]);
		if( $limit ){
			msgWarn( "'DBMS.databases' property is deprecated in favor of 'DBMS.limitDatabases'. You should update your configurations." );
		}
	}

	return $limit;
}

# ------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - whether the database names should be matched insensitively, defaulting to false

sub matchInsensitive {
	my ( $self ) = @_;

	my $insensitive = $self->service()->var([ 'DBMS', 'matchInsensitive' ]);
	$insensitive = false if !defined $insensitive;

	return $insensitive;
}

# ------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - returns the hosting TTP::Node node, defaulting to the current execution node

sub node {
	my ( $self, $node ) = @_;

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
#   > node: the TTP::Node object this DBMS runs on
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

	if( $args->{node} ){
		my $ref = ref( $args->{node} );
		if( $ref eq 'TTP::Node' ){
			$self->{_dbms}{node} = $args->{node};
		} else {
			msgErr( __PACKAGE__."::new() expects 'node' be a TTP::Node, got '$ref'" );
		}
	} else {
		msgErr( __PACKAGE__."::new() 'node' argument is mandatory, but is not specified" );
	}

	if( $args->{service} ){
		my $ref = ref( $args->{service} );
		if( $ref eq 'TTP::Service' ){
			$self->{_dbms}{service} = $args->{service};
		} else {
			msgErr( __PACKAGE__."::new() expects 'service' be a TTP::Service, got '$ref'" );
		}
	} else {
		msgErr( __PACKAGE__."::new() 'service' argument is mandatory, but is not specified" );
	}

	if( TTP::errs()){
		TTP::stackTrace();
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
# When requesting a DBMS configuration by key, we may address either global values or a service
#  dedicated one, depending of whether a service is requested. Hence this global function
# Order of precedence is:
#  1. node.services.<service>.DBMS.key	if a service is requested
#  2. node.DBMS.key
#  3. service.DBMS.key					if a service is requested
#  4. site.DBMS.key
# (I):
# - either a single string or a reference to an array of keys to be read from (e.g. [ 'moveDir', 'byOS', 'MSWin32' ])
#   each key can be itself an array ref of potential candidates for this level
# - an optional options hash with following keys:
#   > service: the TTP::Service object we are specifically requesting, defaulting to none
#   > node: the TTP::Node object to be searched, defaulting to current execution node
# (O):
# - the evaluated value of this variable, which may be undef

sub dbmsVar {
	my ( $keys, $opts ) = @_;
	$opts //= {};
	msgDebug( __PACKAGE__."::dbmsVar() keys=".( ref( $keys ) eq 'ARRAY' ? ( "[ ".join( ', ', @{$keys} )." ]" ) : "'$keys'" ));

	# if we do not have 'DBMS' key somewhere, install it at the first place
	my @local_keys = ( @{$keys} );
	unshift( @local_keys, 'DBMS' ) if !grep( /^DBMS$/, @{$keys} );

	# let TTP::Service do the job
	return TTP::Service::serviceVar( \@local_keys, $opts );
}

1;

__END__
