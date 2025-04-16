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
# The TTP global Entry Point, notably usable in configuration files to get up-to-date data
# The global '$ep' let the caller access TTP modules, functions and variables.
# Through its defined methods, '$ep' let the caller access:
# - the current execution node with $ep->node()
# - the site instance with $ep->site()
# - the current runner with $ep->runner()
# - any var defined in the underlying JSON configurations with $ep->var().

package TTP::EP;

our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Carp;
use Data::Dumper;
use Scalar::Util qw( blessed );
use vars::global qw( $ep );

use TTP;
use TTP::Constants qw( :all );
use TTP::Message qw( :all );
use TTP::Node;
use TTP::Site;

### Private methods

### Public methods

# -------------------------------------------------------------------------------------------------
# TheToolsProject bootstrap process
# In this Perl version, we are unable to update the user environment with such things as TTP_ROOTS
# or TTP_NODE. So no logical machine paradigm and we stay stuck with current hostname.
# - read the toops+site and host configuration files and evaluate them before first use
# - initialize the logs internal variables
# (O):
# - returns this same object

sub bootstrap {
	my ( $self, $args ) = @_;

	# first identify, load, evaluate the site configuration - exit if error
	# when first evaluating the site json, disable warnings so that we do not get flooded with
	# 'use of uninitialized value' message when evaluating the json (because there is no host yet)
	my $site = TTP::Site->new( $self );
	print STDERR __PACKAGE__."::bootstrap() site instanciated".EOL if $ENV{TTP_DEBUG};
	$self->{_site} = $site;
	$site->evaluate({ warnOnUninitialized => false });
	print STDERR __PACKAGE__."::bootstrap() site set and evaluated".EOL if $ENV{TTP_DEBUG};

	# identify current host and load its configuration
	my $node = TTP::Node->new( $self );
	print STDERR __PACKAGE__."::bootstrap() node instanciated".EOL if $ENV{TTP_DEBUG};
	$self->{_node} = $node;
	$node->evaluate();
	print STDERR __PACKAGE__."::bootstrap() node set and evaluated".EOL if $ENV{TTP_DEBUG};

	# reevaluate the site when the node is set
	$site->evaluate();
	# and reevaluate the node
	$node->evaluate();

	return  $self;
}

# -------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - returns the execution node instance

sub node {
	my ( $self ) = @_;
	return $self->{_node};
}

# -------------------------------------------------------------------------------------------------
# Getter/Setter
# (I):
# - optional object to be set as the current IRunnable
# (O):
# - returns the IRunnable running command

sub runner {
	my ( $self, $runner ) = @_;

	if( defined( $runner )){
		if( $runner->does( 'TTP::IRunnable' ) && $runner->does( 'TTP::IOptionable' )){
			print STDERR __PACKAGE__."::runner() setting runner=".ref( $runner ).EOL if $ENV{TTP_DEBUG};
			$self->{_running} = $runner;
		} else {
			msgErr( __PACKAGE__."::runner() expects both TTP::IRunnable and TTP::IOptionable" );
			TTP::stackTrace();
		}
	}

	return $self->{_running};
}

# -------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - returns the site instance, always defined

sub site {
	my ( $self ) = @_;
	return $self->{_site};
}

# -------------------------------------------------------------------------------------------------
# returns the content of a var, read from the provided base
# (I):
# - either a single string or a reference to an array of keys to be read from (e.g. [ 'moveDir', 'byOS', 'MSWin32' ])
#   each key can be itself an array ref of potential candidates for this level
# - an optional options hash with following keys:
#   > jsonable: a JSONable object to be searched for
#     defaulting to current execution node, itself defaulting to site
# (O):
# - the evaluated value of this variable, which may be undef

sub var {
	my ( $self, $keys, $opts ) = @_;
	$opts //= {};
	print STDERR __PACKAGE__."::var() keys=".( ref( $keys ) eq 'ARRAY' ? ( "[ ".join( ', ', @{$keys} )." ]" ) : "'$keys'" ).", opts=".Dumper( $opts ) if $ENV{TTP_DEBUG};
	my $value = undef;
	# we may not have yet a current execution node, so accept that jsonable be undef
	my $jsonable = $opts->{jsonable} || $self->node();
	if( $jsonable ){
		if( ref( $jsonable )){
			if( blessed( $jsonable )){
				if( $jsonable->does( 'TTP::IJSONable' )){
					$value = $jsonable->var( $keys );
				}
			} else {
				msgErr( __PACKAGE__."::var() can't call method 'does' on unblessed reference" );
				TTP::stackTrace();
			}
		}
	}
	return $value;
}

### Class methods

# -------------------------------------------------------------------------------------------------
# Constructor
# (I):
# - none
# (O):
# - this object

sub new {
	my ( $class ) = @_;
	$class = ref( $class ) || $class;
	my $self = {};
	bless $self, $class;

	return $self;
}

# -------------------------------------------------------------------------------------------------
# Destructor
# (I):
# - instance
# (O):

sub DESTROY {
	my $self = shift;
	#print __PACKAGE__."::Destroy()".EOL;
	return;
}

### Global functions
### Note for the developer: while a global function doesn't take any argument, it can be called both
### as a class method 'TTP::Package->method()' or as a global function 'TTP::Package::method()',
### the former being preferred (hence the writing inside of the 'Class methods' block which brings
### the class as first argument).

1;

__END__
