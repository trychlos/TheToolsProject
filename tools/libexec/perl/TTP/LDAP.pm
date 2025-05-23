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

package TTP::LDAP;
die __PACKAGE__ . " must be loaded as TTP::LDAP\n" unless __PACKAGE__ eq 'TTP::LDAP';

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Data::Dumper;

use TTP;
use TTP::Constants qw( :all );
use TTP::Message qw( :all );

my $Const = {
	# ldap defaults
	defaults => {
		configdir => '/etc/openldap/slapd.d',
		datadir => '/var/lib/ldap',
		ownerAccount => 'ldap',
		ownerGroup => 'ldap',
		slapadd => 'slapadd',
		slapcat => 'slapcat',
		sysunit => 'slapd'
	}
};

### Private methods

### Public methods

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the standard LDAP macros to be substituted

sub macros {
	my ( $self ) = @_;

	my $macros = {
		CONFIGDIR => ldapVar( 'configdir' ) || $Const->{defaults}{configdir},
		DATADIR => ldapVar( 'datadir' ) || $Const->{defaults}{datadir},
		OWNER_ACCOUNT => ldapVar( 'owner_account' ) || $Const->{defaults}{ownerAccount},
		OWNER_GROUP => ldapVar( 'owner_group' ) || $Const->{defaults}{ownerGroup},
		SLAPADD => ldapVar( 'slapadd' ) || $Const->{defaults}{slapadd},
		SLAPCAT => ldapVar( 'slapcat' ) || $Const->{defaults}{slapcat},
		SYSUNIT => ldapVar( 'sysunit' ) || $Const->{defaults}{sysunit},
	};

	return $macros;
}

# ------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - returns the TTP::Service this LDAP object belongs to

sub service {
	my ( $self ) = @_;

	return $self->{_ldap}{service};
}

### Class methods

# -------------------------------------------------------------------------------------------------
# Constructor
# (I):
# - the TTP EP entry point
# - an argument object with following keys:
#   > node: the TTP::Node object this LDAP service runs on
#   > service: the TTP::Service object this LDAP object belongs to
# (O):
# - this object, or undef in case of an error

sub new {
	my ( $class, $ep, $args ) = @_;
	$class = ref( $class ) || $class;
	$args //= {};
	my $self = $class->SUPER::new( $ep, $args );
	bless $self, $class;

	$self->{_ldap} = {};

	if( $args->{node} ){
		my $ref = ref( $args->{node} );
		if( $ref eq 'TTP::Node' ){
			$self->{_ldap}{node} = $args->{node};
		} else {
			msgErr( __PACKAGE__."::new() expects 'node' be a TTP::Node, got '$ref'" );
		}
	} else {
		msgErr( __PACKAGE__."::new() 'node' argument is mandatory, but is not specified" );
	}

	if( $args->{service} ){
		my $ref = ref( $args->{service} );
		if( $ref eq 'TTP::Service' ){
			$self->{_ldap}{service} = $args->{service};
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
# When requesting a LDAP configuration by key, we may address either global values or a service
#  dedicated one, depending of whether a service is requested. Hence this global function
# Order of precedence is:
#  1. node:services.<service>.LDAP.key	if a service is requested
#  2. node:LDAP.key
#  3. service:LDAP.key					if a service is requested
#  4. site:LDAP.key
# (I):
# - either a single string or a reference to an array of keys to be read from (e.g. [ 'moveDir', 'byOS', 'MSWin32' ])
#   each key can be itself an array ref of potential candidates for this level
# - an optional options hash with following keys:
#   > service: the TTP::Service object we are specifically requesting, defaulting to none
#   > node: the TTP::Node object to be searched, defaulting to current execution node
# (O):
# - the evaluated value of this variable, which may be undef

sub ldapVar {
	my ( $keys, $opts ) = @_;
	$opts //= {};
	msgDebug( __PACKAGE__."::ldapVar() keys=".( ref( $keys ) eq 'ARRAY' ? ( "[ ".join( ', ', @{$keys} )." ]" ) : "'$keys'" ));

	# if we do not have 'DBMS' key somewhere, install it at the first place
	my @local_keys = ( @{$keys} );
	unshift( @local_keys, 'LDAP' ) if !grep( /^LDAP$/, @{$keys} );

	# let TTP::Service do the job
	return TTP::Service::serviceVar( \@local_keys, $opts );
}

1;

__END__
