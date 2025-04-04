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
# Commands which are extern to TheToolsProject.

package TTP::Extern;

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
use vars::global qw( $ep );

with 'TTP::IHelpable', 'TTP::IOptionable', 'TTP::IRunnable';

use TTP;
use TTP::Constants qw( :all );
use TTP::EP;
use TTP::Message qw( :all );

my $Const = {
};

### Private methods

# -------------------------------------------------------------------------------------------------
# command initialization
# (I):
# - none
# (O):
# - this object

sub _init {
	my ( $self ) = @_;

	# bootstrap TTP
	$ep->bootstrap();

	return $self;
}

### Public methods

### Class methods

# -------------------------------------------------------------------------------------------------
# Constructor
# To be called at the very early run of an external program.
# (I):
# - none
# (O):
# - this object, or undef

sub new {
	my ( $class ) = @_;
	$class = ref( $class ) || $class;
	$ep = TTP::EP->new();
	my $self = $class->SUPER::new( $ep );
	bless $self, $class;

	# command initialization
	$self->_init();
	$self->run();

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
