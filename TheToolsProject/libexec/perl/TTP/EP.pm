# The Tools Project: a Tools System and Paradigm for IT Production
# Copyright (©) 1998-2023 Pierre Wieser (see AUTHORS)
# Copyright (©) 2023-2024 PWI Consulting
#
# The Tools Project is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version.
#
# The Tools Project is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with The Tools Project; see the file COPYING. If not,
# see <http://www.gnu.org/licenses/>.
#
# The TTP global Entry Point, notably usable in configuration files to get up-to-date data

package TTP::EP;

our $VERSION = '1.00';

use strict;
use warnings;

use Carp;
use Data::Dumper;
use vars::global qw( $ep );

use TTP::Command;
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

my $bootstrapDebugInstanciation = false;
my $bootstrapDebugEvaluation = false;

sub bootstrap {
	my ( $self, $args ) = @_;

	# first identify, load, evaluate the site configuration - exit if error
	# when first evaluating the site json, disable warnings so that we do not get flooded with
	# 'use of uninitialized value' message when evaluating the json (because there is no host yet)
	my $site = TTP::Site->new( $self );
	print __PACKAGE__."::bootstrap() site instanciated".EOL if $bootstrapDebugInstanciation;
	$self->{_site} = $site;
	$site->evaluate({ warnOnUninitialized => false });
	print __PACKAGE__."::bootstrap() site set and evaluated".EOL if $bootstrapDebugEvaluation;

	# identify current host (remind that there is no logical node in this Perl version) and load its configuration
	my $node = TTP::Node->new( $self );
	print __PACKAGE__."::bootstrap() node instanciated".EOL if $bootstrapDebugInstanciation;
	$self->{_node} = $node;
	$node->evaluate();
	print __PACKAGE__."::bootstrap() node set and evaluated".EOL if $bootstrapDebugEvaluation;

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
# - returns the execution node context

sub node {
	my ( $self ) = @_;
	return $self->{_node};
}

# -------------------------------------------------------------------------------------------------
# Run the current command+verb
# (I):
# - none
# (O):
# - returns this same object

sub runCommand {
	my ( $self ) = @_;

	my $command = TTP::Command->new( $self );
	$command->run();

	return $self;
}

# -------------------------------------------------------------------------------------------------
# Getter/Setter
# (I):
# - optional object to be set as the current Runnable
# (O):
# - returns the Runnable running command

sub runner {
	my ( $self, $runner ) = @_;

	$self->{_running} = $runner if defined $runner;

	return $self->{_running};
}

# -------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - returns the site context, always defined

sub site {
	my ( $self ) = @_;
	return $self->{_site};
}

# -------------------------------------------------------------------------------------------------
# returns the content of a var, read from the provided base
# (I):
# - a reference to an array of keys to be read from (e.g. [ 'moveDir', 'byOS', 'MSWin32' ])
#   each key can be itself an array ref of potential candidates for this level
# - an optional options hash with following keys:
#   > jsonable: a JSONable object to be searched for
#     defaulting for current execution node, itself defaulting to site
# (O):
# - the evaluated value of this variable, which may be undef

my $varDebug = false;

sub var {
	my ( $self, $keys, $opts ) = @_;
	$opts //= {};
	my $value = undef;
	# we may not have yet a current execution node, so accept that jsonable be undef
	my $jsonable = $opts->{jsonable} || $self->node();
	if( $jsonable && ref( $jsonable ) && $jsonable->does( 'TTP::IJSONable' )){
		$value = $jsonable->var( $keys );
	}
	return $value;
}

### Class methods

# -------------------------------------------------------------------------------------------------
# Constructor
# (I]:
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
# (I]:
# - instance
# (O):

sub DESTROY {
	my $self = shift;
	#print __PACKAGE__."::Destroy()".EOL;
	return;
}

1;

__END__
