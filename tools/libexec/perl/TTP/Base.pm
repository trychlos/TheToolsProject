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
# The base class for all TTP classes.
#
# The TTP EntryPoint ref is available both:
# - as a global variable created in TTP.pm and available everywhere via 'vars::global' package
# - and stored as a reference in this base class, so available through $object->ep().

package TTP::Base;
die __PACKAGE__ . " must be loaded as TTP::Base\n" unless __PACKAGE__ eq 'TTP::Base';

our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Data::Dumper;

use TTP::Constants qw( :all );

### Private methods

# -------------------------------------------------------------------------------------------------
# A placeholder so that roles can come after or before this function which is called at instanciation time
# EntryPoint is already set, so that the roles not only get the '$ep' in the arguments list, but can also
# call $self->ep() 
# (I):
# - the TTP EntryPoint ref
# (O):
# - this same object

sub _newBase {
	my ( $self, $ep, $args ) = @_;
	return $self;
}

### Public methods

# -------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none 
# (O):
# - the TheToolsProject EntryPoint ref recorded at instanciation time

sub ep {
	my ( $self ) = @_;
	return $self->{_ep};
}

### Class methods

# -------------------------------------------------------------------------------------------------
# Constructor
# (I):
# - the current TheToolsProject EntryPoint ref
# - other arguments to be passed to the derived class
# (O):
# - this object

sub new {
	my ( $class, $ep, $args ) = @_;
	$class = ref( $class ) || $class;
	$args //= {};
	my $self = {};
	bless $self, $class;

	# keep the TTP EP ref
	if( defined( $ep ) && ref( $ep ) eq 'TTP::EP' ){
		$self->{_ep} = $ep;
	} else {
		print STDERR "(ERR) ".__PACKAGE__."::new() 'ep' EntryPoint is not defined but is mandatory".EOL;
		TTP::stackTrace();
	}

	# let the roles insert their own code at that time
	$self->_newBase( $ep, $args );

	return $self;
}

# -------------------------------------------------------------------------------------------------
# Destructor
# (I):
# - instance
# (O):

sub DESTROY {
	my $self = shift;
	return;
}

### Global functions
### Note for the developer: while a global function doesn't take any argument, it can be called both
### as a class method 'TTP::Package->method()' or as a global function 'TTP::Package::method()',
### the former being preferred (hence the writing inside of the 'Class methods' block which brings
### the class as first argument).

1;

__END__
