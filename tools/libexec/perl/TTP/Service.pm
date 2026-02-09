# TheToolsProject - Tools System and Working Paradigm for IT Production
# Copyright (©) 1998-2023 Pierre Wieser (see AUTHORS)
# Copyright (©) 2023-2026 PWI Consulting
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
# Manage the service configurations.
#
# A service:
# - can be configured in an optional <service>.json file
# - must at least be mentionned in each and every <node>.json which manage or participate to the service.
# Note:
# - Even if the node doesn't want override any service key, it still MUST define the service in the
#   'services' object of its own configuration file

package TTP::Service;
die __PACKAGE__ . " must be loaded as TTP::Service\n" unless __PACKAGE__ eq 'TTP::Service';

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Carp;
use Config;
use Data::Dumper;
use Module::Load;
use Role::Tiny::With;

with 'TTP::IAcceptable', 'TTP::IEnableable', 'TTP::IFindable', 'TTP::IJSONable';

use TTP;
use vars::global qw( $ep );

use TTP::Constants qw( :all );
use TTP::LDAP;
use TTP::Message qw( :all );
use TTP::Node;

my $Const = {
	# hardcoded subpaths to find the <service>.json files
	# even if this not too sexy in Win32, this is a standard and a common usage on Unix/Darwin platforms
	finder => {
		dirs => [
			'etc/services'
		],
		suffix => '.json'
	}
};

### Private methods

### Public methods

# ------------------------------------------------------------------------------------------------
# Getter
# (I):
# - the list of keys to be considered as an array ref
# (O):
# - returns an array ref to the configured commands as provided by TTP::commandByOS(), which may be empty or undef

sub commands {
	my ( $self, $keys ) = @_;

	my $commands = [];

	# search in this same service definition if exists
	if( $self->jsonLoaded()){
		my $parts = TTP::commandByOS( $keys, { jsonable => $self });
		push( @{$commands}, @{$parts} ) if $parts && scalar( @{$parts} );
	}

	# search in 'services'
	my $serviceKeys = [ 'services', $self->name(), @{$keys} ];
	my $parts = TTP::commandByOS( $serviceKeys, { jsonable => $ep->node() });
	push( @{$commands}, @{$parts} ) if $parts && scalar( @{$parts} );

	# search in (deprecated in v4.10) 'Services'
	$serviceKeys = [ 'Services', $self->name(), @{$keys} ];
	$parts = TTP::commandByOS( $serviceKeys, { jsonable => $ep->node() });
	push( @{$commands}, @{$parts} ) if $parts && scalar( @{$parts} );

	return $commands;
}

# ------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - returns true|false, whether the service is enabled, defaulting to true

sub enabled {
	my ( $self ) = @_;

	my $enabled = $self->var([ 'enabled' ]);
	$enabled = true if !defined $enabled;

	return $enabled;
}

# ------------------------------------------------------------------------------------------------
# Override the 'IJSONable::evaluate()' method to manage the macros substitutions
# (I):
# - none
# (O):
# - this same object

sub evaluate {
	my ( $self ) = @_;

	$self->TTP::IJSONable::evaluate();

	TTP::substituteMacros( $self->jsonData(), {
		NODE => $self->ep()->node()->name(),
		SERVICE => $self->name()
	});

	return $self;
}

# ------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - returns true|false, whether the service is hidden, defaulting to false

sub hidden {
	my ( $self ) = @_;

	my $hidden = $self->var([ 'hidden' ]);
	$hidden = false if !defined $hidden;

	return $hidden;
}

# ------------------------------------------------------------------------------------------------
# Getter
# (I):
# - the current TTP::Node node
# (O):
# - returns the defined host, which may be undef

sub host {
	my ( $self, $node ) = @_;

	my $str = $self->var([ 'host' ], $node );
	if( !defined( $str )){
		$str = $self->var([ 'DBMS', 'host' ], $node );
		if( defined( $str )){
			msgWarn( "'DBMS.host' property is deprecated in favor of 'host' since v4.32. You should update your code and/or your configurations." );
		}
	}

	return $str;
}

# ------------------------------------------------------------------------------------------------
# Returns the name of the service
# (I):
# - none
# (O):
# - returns the name of the service, or undef

sub name {
	my ( $self ) = @_;

	return $self->{_name};
}

# ------------------------------------------------------------------------------------------------
# Instanciates the DBMS object
# (I):
# - an optional arguments object with following keys:
#   > node: the hosting node, defaulting to the current execution node
# (O):
# - returns the DBMS-derived instance or undef

sub newDbms {
	my ( $self, $args ) = @_;
	$args //= {};

	my $dbms = undef;

	my $package = $self->var([ 'DBMS', 'package' ]);
	if( $package ){
		msgVerbose( __PACKAGE__."::newDbms() got package='$package'" );
		load $package, ':all';
		if( $package->can( 'new' )){
			$dbms = $package->new( $ep, {
				node => $args->{node} || $ep->node(),
				service => $self
			});
		} else {
			msgErr( __PACKAGE__."::newDbms() package '$package' says it cannot 'new()'" );
		}
	} else {
		msgErr( __PACKAGE__."::newDbms() unable to find a suitable DBMS package for '".$self->name()."' service" );
	}

	return $dbms;
}

# ------------------------------------------------------------------------------------------------
# Instanciates the LDAP object
# (I):
# - an optional arguments object with following keys:
#   > node: the hosting node, defaulting to the current execution node
# (O):
# - returns the LDAP-derived instance or undef

sub newLdap {
	my ( $self, $args ) = @_;
	$args //= {};

	my $ldap = TTP::LDAP->new( $ep, {
		node => $args->{node} || $ep->node(),
		service => $self
	});

	return $ldap;
}

# ------------------------------------------------------------------------------------------------
# Returns the value of the specified var.
# The var is successively searched for in the Node configuration, then in this Service configuration
# and last at the site level.
# (I):
# - a ref to the array of successive keys to be addressed
# - an optional node to be searched for, defaulting to current execution node
#   the node can be specified either as a string (the node name) or a TTP::Node object
# (O):
# - returns the found value, or undef

sub var {
	my ( $self, $args, $node ) = @_;
	my $value = undef;
	my $jsonable = undef;
	# do we have a provided node ?
	if( $node ){
		my $ref = ref( $node );
		if( $ref ){
			if( $ref eq 'TTP::Node' ){
				$jsonable = $node;
			} else {
				msgErr( __PACKAGE__."::var() expects node be provided either by name or as a 'TTP::Node', found '$ref'" );
			}
		} else {
			my $nodeObj = TTP::Node->new( $self->ep(), { node => $node });
			if( $nodeObj->loaded()){
				$jsonable = $nodeObj;
			}
		}
	} else {
		$jsonable = $self->ep()->node();
	}
	if( $jsonable ){
		$value = serviceVar( $args, {
			service => $self,
			node => $jsonable
		});
	}
	return $value;
}

# ------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - whether this service is only bound to local connections, defaulting to true

sub wantsLocal {
	my ( $self ) = @_;

	my $wantsLocal = $self->var([ 'wantsLocal' ]);
	$wantsLocal = true if !defined $wantsLocal;

	return $wantsLocal;
}

# -------------------------------------------------------------------------------------------------
# Whether we should warn when several hosting nodes are found is rather a site-level property.
# it is nonetheless overridable on a per-service or per-node basis. Hence this method.
# (I):
# - none
# (O):
# - whether we should warn when several hosting nodes are found: true|false

sub warnOnMultipleHostingNodes {
	my ( $self ) = @_;
	
	my $warn = $self->var([ 'warnOnMultipleHostingNodes' ]);
	$warn = true if !defined $warn;

	return $warn;
}

### Class methods

# -------------------------------------------------------------------------------------------------
# Enumerate the services defined on the node
# - in ascii-sorted order [0-9A-Za-z]
# - considering and honoring the 'hidden' and 'enabled' options
# - and call the provided sub for each found
# (I):
# - an optional arguments hash with following keys:
#   > node, the node name or the TTP::Node instance on which the enumeration must be done, defaulting to current execution node
#   > cb, a code reference to be called on each enumerated service with:
#     - the TTP::Service instance (remind: it may have not been jsonLoaded)
#     - this same arguments object
#   > hidden, whether to also return hidden services, defaulting to false
#   > disabled: whether to also return the disabled services, defaulting to false
# (O):
# - returns a count of enumerated services

sub enum {
	my ( $class, $args ) = @_;
	$args //= {};
	my $count = 0;
	my $withHiddens = false;
	$withHiddens = $args->{hidden} if defined $args->{hidden};
	my $withDisabled = false;
	$withDisabled = $args->{disabled} if defined $args->{disabled};
	my $node = $ep->node();
	if( defined( $args->{node} )){
		my $ref = ref( $args->{node} );
		if( $ref ){
			if( $ref eq 'TTP::Node' ){
				$node = $args->{node};
			} else {
				msgErr( __PACKAGE__."::enumerate() expects a 'TTP::Node', found '$ref'" );
			}
		} else {
			$node = TTP::Node->new( $ep, { node => $args->{node}, abortOnError => false });
			$node = $ep->node() if !$node;
		}
	}
	if( !TTP::errs()){
		my $cb = $args->{cb};
		if( $cb && ref( $cb ) eq 'CODE' ){
			# these are the services defined on this node
			# via the 'services' property
			my $services = $node->var([ 'services' ]) || {};
			my @keys = keys %{$services};
			foreach my $it ( @keys ){
				my $service = TTP::Service->new( $ep, { service => $it, quiet => true });
				if( $service && ( !$service->hidden() || $withHiddens ) && ( $service->enabled() || $withDisabled )){
					$cb->( $service, $args );
					$count += 1;
				}
			}
			# via the (deprecated in v4.10) 'Services' property
			$services = $node->var([ 'Services' ]) || {};
			@keys = keys %{$services};
			my $deprecated = 0;
			foreach my $it ( @keys ){
				my $service = TTP::Service->new( $ep, { service => $it, quiet => true });
				if( $service && ( !$service->hidden() || $withHiddens ) && ( $service->enabled() || $withDisabled )){
					$cb->( $service, $args );
					$count += 1;
					$deprecated += 1;
				}
			}
			if( $deprecated && !$ep->{_warnings}{services} ){
				msgWarn( "'Services' property is deprecated in favor of 'services' since v4.10. You should update your code and/or your configurations." );
				$ep->{_warnings}{services} = true;
			}
		} else {
			msgErr( __PACKAGE__."::enumerate() expects a 'cb' callback code ref, not found" );
		}
	}
	return $count;
}

# -------------------------------------------------------------------------------------------------
# Returns the list of dirs where services JSON configurations are to be found
# (I):
# - none
# (O):
# - returns a ref to the finder, honoring 'services.confDirs' variable if any

sub finder {
	my ( $class ) = @_;

	my %finder = %{$Const->{finder}};
	my $dirs = $ep->var([ 'services', 'confDirs' ]);
	if( !$dirs ){
		$dirs = $ep->var( 'servicesDirs' );
		if( $dirs ){
			msgWarn( "'servicesDirs' property is deprecated in favor of 'services.confDirs' since v4.10. You should update your code and/or your configurations." );
		}
	}
	$finder{dirs} = $dirs if $dirs;

	return \%finder;
}

# -------------------------------------------------------------------------------------------------
# Returns the ordered list of services defined on the specified node
# (I):
# - an optional arguments hash with following keys:
#   > hidden: whether to also return the hidden services, defaulting to false
#   > disabled: whether to also return the disabled services, defaulting to false
#   > node: the node to be search the services in, either as a string (the node name) or a TTP::Node ref
# (O):
# - returns the list of (maybe hidden) services for the node

sub list {
	my ( $class, $args ) = @_;
	$args //= {};

	my $list = [];
	$args->{cb} = \&_list_cb;
	$args->{result} = $list;
	$class->enum( $args ); # ignore returned count

	return $list;
}

sub _list_cb {
	my ( $service, $args ) = @_;
	push( @{$args->{result}}, $service->name());
}

# -------------------------------------------------------------------------------------------------
# Constructor
# (I):
# - the TTP EP entry point ref
# - an arguments hash with following keys:
#   > service: the service name to be initialized
#   > quiet: whether be quiet about no JSON found, defaulting to false
# (O):
# - this object, may or may not have been jsonLoaded()

sub new {
	my ( $class, $ep, $args ) = @_;
	$class = ref( $class ) || $class;
	$args //= {};
	my $self = $class->SUPER::new( $ep, $args );
	bless $self, $class;

	if( $args->{service} ){

		# keep the service name
		$self->{_name} = $args->{service};

		# allowed services.confDirs are configured at site-level
		my $finder = $class->finder();
		my $findable = {
			dirs => [ $finder->{dirs}, $args->{service}.$finder->{suffix} ],
			wantsAll => false
		};
		my $acceptable = {
			accept => sub { return $self->enabled( @_ ); },
			opts => {
				type => 'JSON'
			}
		};
		if( $self->jsonLoad({ findable => $findable, acceptable => $acceptable })){
			$self->evaluate();

		} else {
			my $quiet = false;
			$quiet = $args->{quiet} if defined $args->{quiet};
			msgVerbose( "service '$args->{service}' is not defined as an autonomous JSON" ) if !$quiet;
		}

	} else {
		msgErr( __PACKAGE__."::new() expects an 'args->{service}' key, which has not been found" );
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
# Because the service.schema.json specifies that some service key can be defined at the site level,
# we must have this global function in case no service is requested.
# Order of precedence is:
#  1. node.services.<service>.key	if a service is requested
#  2. node.key
#  3. service.key					if a service is requested
#  4. site.key
# (I):
# - either a single string or a reference to an array of keys to be read from (e.g. [ 'moveDir', 'byOS', 'MSWin32' ])
#   each key can be itself an array ref of potential candidates for this level
# - an optional options hash with following keys:
#   > service: the TTP::Service object we are specifically requesting, defaulting to none
#   > node: the TTP::Node object to be searched, defaulting to current execution node
# (O):
# - the evaluated value of this variable, which may be undef

sub serviceVar {
	my ( $keys, $opts ) = @_;
	$opts //= {};
	msgDebug( __PACKAGE__."::serviceVar() keys=".( ref( $keys ) eq 'ARRAY' ? ( "[ ".join( ', ', @{$keys} )." ]" ) : "'$keys'" ));

	my $value = undef;
		
	# if we have a service, check the reference
	if( $opts->{service} ){
		my $ref = ref( $opts->{service} );
		if( $ref ne 'TTP::Service' ){
			msgErr( __PACKAGE__."::serviceVar() expects a 'TTP::Service', got '$ref'" );
			return $value;
		}
	}
	my $jsonable = $opts->{node} || $ep->node();
	my $ref = ref( $jsonable );
	if( $ref ne 'TTP::Node' ){
		msgErr( __PACKAGE__."::serviceVar() expects being able to search into a 'TTP::Node', got '$ref'" );
		return $value;
	}

	# first order of precedence is the service definition inside of the node if a service is specified
	if( $opts->{service} ){
		my @first_keys = ( 'services', $opts->{service}->name(), @{$keys} );
		$value = $jsonable->TTP::IJSONable::var( \@first_keys );
		if( !defined( $value )){
			@first_keys = ( 'Services', $opts->{service}->name(), @{$keys} );
			$value = $jsonable->TTP::IJSONable::var( \@first_keys );
			if( defined( $value ) && !$ep->{_warnings}{services} ){
				msgWarn( "'Services' property is deprecated in favor of 'services' since v4.10. You should update your code and/or your configurations." );
				$ep->{_warnings}{services} = true;
			}
		}
		return $value if defined $value;
	}

	# second order of precedence is the node-level key
	$value = $jsonable->TTP::IJSONable::var( $keys );
	return $value if defined $value;

	# third order of precedence is the service-level key if a service is specified
	if( $opts->{service} && $opts->{service}->jsonLoaded()){
		$value = $opts->{service}->TTP::IJSONable::var( $keys );
		return $value if defined $value;
	}

	# last search at the site global level
	$value = TTP::var( $keys );

	return $value;
}

1;

__END__
