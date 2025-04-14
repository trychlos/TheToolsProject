# The Tools Project - Tools System and Working Paradigm for IT Production
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
# Manage the service configurations.
#
# A service:
# - can be configured in an optional <service>.json file
# - must at least be mentionned in each and every <node>.json which manage or participate to the service.
# Note:
# - Even if the node doesn't want override any service key, it still MUST define the service in the
#   'Services' object of its own configuration file

package TTP::Service;

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Carp;
use Config;
use Data::Dumper;
use Role::Tiny::With;
use vars::global qw( $ep );

with 'TTP::IEnableable', 'TTP::IFindable', 'TTP::IJSONable';

use TTP::Constants qw( :all );
use TTP::Message qw( :all );
use TTP::Node;

my $Const = {
	# hardcoded subpaths to find the <service>.json files
	# even if this not too sexy in Win32, this is a standard and a common usage on Unix/Darwin platforms
	finder => {
		dirs => [
			'etc/services',
			'services'
		],
		suffix => '.json'
	}
};

### Private methods

### Public methods

# ------------------------------------------------------------------------------------------------
# Override the 'IJSONable::evaluate()' method to manage the macros substitutions
# (I):
# -none
# (O):
# - this same object

sub evaluate {
	my ( $self ) = @_;

	$self->TTP::IJSONable::evaluate();

	TTP::substituteMacros( $self->jsonData(), {
		'<NODE>' => $self->ep()->node()->name(),
		'<SERVICE>' => $self->name()
	});

	return $self;
}

# ------------------------------------------------------------------------------------------------
# Getter
# (I):
# -none
# (O):
# - returns true|false, whether the service is hidden, defaulting to false

sub hidden {
	my ( $self ) = @_;

	my $hidden = $self->var([ 'hidden' ]);
	$hidden = false if !defined $hidden;

	return $hidden;
}

# ------------------------------------------------------------------------------------------------
# Returns the name of the service
# (I):
# -none
# (O):
# - returns the name of the service, or undef

sub name {
	my ( $self ) = @_;

	return $self->{_name};
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
	# keep a copy of the provided arguments
	my @args = @{$args};
	my $name = $self->name();
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
			my $nodeObj = TTP::Node->new( $ep, { node => $node });
			if( $nodeObj->loaded()){
				$jsonable = $nodeObj;
			}
		}
	} else {
		$jsonable = $ep->node();
	}
	if( $jsonable ){
		# search for the service definition in the node
		unshift( @{$args}, 'Services', $name );
		$value = $jsonable->var( $args );
		# search as the value general to the node
		if( !defined( $value )){
			$value = $jsonable->var( \@args );
		}
		# search in this service definition
		if( !defined( $value )){
			$value = $self->TTP::IJSONable::var( \@args ) if $self->jsonLoaded();
		}
		# last search for a default value at site level
		if( !defined( $value )){
			$value = $ep->site()->var( \@args );
		}
	}
	return $value;
}

### Class methods

# ------------------------------------------------------------------------------------------------
# Returns the list of subdirectories of TTP_ROOTS in which we may find services configuration files
# (I):
# - none
# (O):
# - returns the list of subdirectories which may contain the JSON services configuration files as
#   an array ref

sub dirs {
	my ( $class ) = @_;
	$class = ref( $class ) || $class;

	my $dirs = $ep->var( 'servicesDirs' ) || $class->finder()->{dirs};

	return $dirs;
}

# -------------------------------------------------------------------------------------------------
# Enumerate the services defined on the node
# - in ascii-sorted order [0-9A-Za-z]
# - considering the 'hidden' option
# - and call the provided sub for each found
# (I):
# - an arguments hash with following keys:
#   > node, the node name or the TTP::Node instance on which the enumeration must be done, defaulting to current execution node
#   > cb, a code reference to be called on each enumerated service with:
#     - the TTP::Service instance (remind: it may have not been jsonLoaded)
#     - this same arguments object
#   > hidden, whether to also return hidden services, defaulting to false
# (O):
# - returns a count of enumerated services

sub enumerate {
	my ( $class, $args ) = @_;
	$args //= {};
	my $count = 0;
	my $withHiddens = false;
	$withHiddens = $args->{hidden} if exists $args->{hidden};
	my $node = $ep->node();
	if( exists( $args->{node} )){
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
	my $cb = $args->{cb};
	if( $cb && ref( $cb ) eq 'CODE' ){
		# these are the services defined on this node
		my $services = $node->var([ 'Services' ]);
		my @list = sort keys %{$services};
		foreach my $it ( @list ){
			my $service = TTP::Service->new( $ep, { service => $it });
			if( $service && !$service->hidden() || $withHiddens ){
				$cb->( $service, $args );
				$count += 1;
			}
		}
	} else {
		msgErr( __PACKAGE__."::enumerate() expects a 'cb' callback code ref, not found" );
	}
	return $count;
}

# -------------------------------------------------------------------------------------------------
# Returns the list of dirs where nodes are to be found
# (I):
# - none
# (O):
# - Returns the Const->{finder} specification as an array ref

sub finder {
	my ( $class ) = @_;

	return $Const->{finder};
}

# -------------------------------------------------------------------------------------------------
# Constructor
# (I):
# - the TTP EP entry point ref
# - an arguments hash with following keys:
#   > service: the service name to be initialized
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

		# allowed servicesDirs are configured at site-level
		my $findable = {
			dirs => [ $class->dirs(), $args->{service}.$class->finder()->{suffix} ],
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
			msgVerbose( "service '$args->{service}' is not defined as an autonomous JSON" );
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

# -------------------------------------------------------------------------------------------------
# List the services defined a a given host
# (I):
# - an optional node name, defaulting to the current execution node
# (O):
# - a ref to an array of the defined services

1;

__END__
