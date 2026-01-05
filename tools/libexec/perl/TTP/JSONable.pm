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
# A class which just implements the IJSONable role.

package TTP::JSONable;
die __PACKAGE__ . " must be loaded as TTP::JSONable\n" unless __PACKAGE__ eq 'TTP::JSONable';

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Role::Tiny::With;

with 'TTP::IJSONable';

use TTP;
use TTP::Constants qw( :all );
use TTP::Message qw( :all );

### Private functions
### Must be explicitely called with $daemon as first argument

### Public methods

### Class methods

# -------------------------------------------------------------------------------------------------
# Constructor
# Instanciates the object with some data.
# (I):
# - the TTP EP entry point
# - the data to initialize the object with.
# (O):
# - this object

sub new {
	my ( $class, $ep, $data ) = @_;
	$class = ref( $class ) || $class;
	my $self = $class->SUPER::new( $ep );
	bless $self, $class;

	$self->{_ijsonable}{raw} = $data;
	$self->evaluate();

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
