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
# The base class of all executables either in TTP (like commands and verbs) or based on TTP (like daemons and extern, site-specific, programs).
# All these executables share some common features provided by the roles below.

package TTP::Runner;
die __PACKAGE__ . " must be loaded as TTP::Runner\n" unless __PACKAGE__ eq 'TTP::Runner';

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Carp;
use Config;
use Data::Dumper;
use Getopt::Long;
use Role::Tiny::With;
use Try::Tiny;

with 'TTP::IHelpable', 'TTP::IOptionable', 'TTP::IRunnable';

use TTP::Constants qw( :all );
use TTP::Message qw( :all );

my $Const = {
	# the minimal count of arguments to trigger the help display
	minArgsCount => 1
};

### Private methods

### Public methods

# -------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - the initial ARGV element as an array ref

sub argv {
	my ( $self ) = @_;

	return $self->{_runner}{ARGV};
}

# -------------------------------------------------------------------------------------------------
# Returns the minimal count of arguments needed by the running executable
# Below this minimal count, we automatically display the runner's help
# (I):
# - this TTP::Runner instance
# (O):
# - the minimal count of arguments needed

sub minArgsCount {
	my ( $self ) = @_;

	return $Const->{minArgsCount};
}

# -------------------------------------------------------------------------------------------------
# Just en empty run()
# (I):
# - this TTP::Runner instance
# (O):
# - this same instance

sub run {
	my ( $self ) = @_;

	TTP::Message::msgWarn( __PACKAGE__."::run() should never run here" );

	return $self;
}

### Class methods

# -------------------------------------------------------------------------------------------------
# Constructor
# (I):
# - the TTP EP entry point
# (O):
# - this object

sub new {
	my ( $class, $ep ) = @_;
	$class = ref( $class ) || $class;
	my $self = $class->SUPER::new( $ep );
	bless $self, $class;

	$self->{_runner} = {};

	# keep initial - unchanged - arguments
	my @argv = @ARGV;
	$self->{_runner}{ARGV} = \@argv;

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
### the former being preferred (hence the writing inside of the 'Class methods' block which brings
### the class as first argument).

1;

__END__
