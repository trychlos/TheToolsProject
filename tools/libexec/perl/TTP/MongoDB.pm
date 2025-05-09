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
# A package dedicated to MongoDB

package TTP::MongoDB;
die __PACKAGE__ . " must be loaded as TTP::MongoDB\n" unless __PACKAGE__ eq 'TTP::MongoDB';

use base qw( TTP::DBMS );
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Config;
use Capture::Tiny qw( :all );
use Data::Dumper;
use File::Spec;
use MongoDB;
use Path::Tiny;
use Time::Moment;

use TTP;
use TTP::Constants qw( :all );
use TTP::Credentials;
use TTP::Message qw( :all );

my $Const = {
	# the list of system databases to be excluded
	systemDatabases => [
		'admin',
		'config',
		'local'
	],
	# the list of system tables to be excluded
	systemTables => [
	]
};

### Private methods

# ------------------------------------------------------------------------------------------------
# get a connection to the MongoDB server instance
# (I):
# - none
# (O):
# - an opaque handle on the connection, or undef

sub _connect {
	my ( $self ) = @_;

	my $handle = $self->{_dbms}{connect};
	if( $handle ){
		msgVerbose( __PACKAGE__."::_connect() already connected" );

	} else {
		my( $account, $passwd ) = $self->_getCredentials();
		if( length $account && length $passwd ){
			my $host = $self->service()->var([ 'DBMS', 'host' ]) || 'localhost:27017';
			$handle = MongoDB::MongoClient->new( host => $host, username => $account, password => $passwd );
			$self->{_dbms}{connect} = $handle;
			if( $handle ){
				#print STDERR Dumper( $handle );
				msgVerbose( __PACKAGE__."::_connect() successfully connected" );
			}
		} else {
			msgErr( __PACKAGE__."::_connect() unable to get account/password couple" );
		}
	}

	return $handle;
}

# ------------------------------------------------------------------------------------------------
# execute a command on the server
# (I):
# - the DBMS instance
# - the command
# - an optional options hash
# (O):
# - the result as a hash ref with following keys:
#   > ok: true|false

sub _noSql {
	my ( $self, $command, $opts ) = @_;
	$opts //= {};
	msgErr( __PACKAGE__."::_noSql() command is mandatory, but is not specified" ) if !$command;
	my $res = {
		ok => false,
		result => [],
		stdout => [],
		stderr => []
	};
	if( !TTP::errs()){
	}
	return $res;
}

### Public methods

# -------------------------------------------------------------------------------------------------
# returns the list of databases in this DBMS
# cache the result (the list of found databases) to request the DBMS only once
# (I):
# - none
# (O):
# - returns the list of databases in the instance as an array ref, may be empty

sub getDatabases {
	my ( $self ) = @_;

	my $databases = $self->TTP::DBMS::getDatabases();
	if( defined( $databases )){
		msgVerbose( __PACKAGE__."::getDatabases() got cached databases [ ". join( ', ', @{$databases} )." ]" );
	} else {
		my $handle = $self->_connect();
		if( $handle ){
			my @dbs = $handle->list_databases;
			$databases = [];
			foreach my $it ( @dbs ){
				my $dbname = $it->{name};
				if( !grep( /^$dbname$/, @{$Const->{systemDatabases}} )){
					push( @{$databases}, $dbname );
				}
			}
			msgVerbose( __PACKAGE__."::getDatabases() got databases [ ". join( ', ', @{$databases} )." ]" );
			$self->{_dbms}{databases} = $databases;
		}
	}

	return $databases || [];
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

	if( $self ){
		bless $self, $class;
		msgVerbose( __PACKAGE__."::new()" );
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
