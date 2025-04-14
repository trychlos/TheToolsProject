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
# The options management of commands+verbs, daemons and external scripts.
#
# 'help', 'colored', 'dummy' and 'verbose' option flags are set into ttp->{run} hash both for
# historical reasons and for the ease of handlings.
# They are all initialized to false at IOptionable instanciation time.
#
# 'help' is automatically set when there the command-line only contains the command, or the command
# and the verb. After that, this is managed by GetOptions().
#
# 'colored' is message-level dependant (see Message.pm), and defaults to be ignored for msgLog(),
# false for msgOut(), true in all other cases.
#
# After their initialization here, 'dummy' and 'verbose' flags only depend of GetOptions().

package TTP::IOptionable;
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Data::Dumper;
use vars::global qw( $ep );

use TTP;
use TTP::Constants qw( :all );
use TTP::Message qw( :all );

### https://metacpan.org/pod/Role::Tiny
### All subs created after importing Role::Tiny will be considered methods to be composed.
use Role::Tiny;

requires qw( _newBase );

# -------------------------------------------------------------------------------------------------
# Getter/Setter
# (I):
# - this TTP::IOptionable (self)
# - when called by GetOptions(), the option name
# - when called by GetOptions(), the option value
# (O):
# - whether the output should be colored: true|false

sub colored {
	my ( $self, $name, $value ) = @_;

	if( scalar( @_ ) > 1 ){
		$self->{_ioptionable}{$name} = $value;
		$self->{_ioptionable}{$name.'_set'} = true;
	}

	return $self->{_ioptionable}{colored};
};

# -------------------------------------------------------------------------------------------------
# Getter
# (I):
# - this TTP::IOptionable (self)
# (O):
# - whether the --colored option has been specified in the command-line

sub coloredSet {
	my ( $self ) = @_;

	return $self->{_ioptionable}{colored_set};
};

# -------------------------------------------------------------------------------------------------
# Getter/Setter
# (I):
# - this TTP::IOptionable (self)
# - when called by GetOptions(), the option name
# - when called by GetOptions(), the option value
# (O):
# - whether the run is dummy: true|false

sub dummy {
	my ( $self, $name, $value ) = @_;

	if( scalar( @_ ) > 1 ){
		$self->{_ioptionable}{$name} = $value;
		$self->{_ioptionable}{$name.'_set'} = true;
	}

	return $self->{_ioptionable}{dummy};
};

# -------------------------------------------------------------------------------------------------
# Getter/Setter
# (I):
# - this TTP::IOptionable (self)
# - when called by GetOptions(), the option name
# - when called by GetOptions(), the option value
# (O):
# - whether the help should be displayed: true|false

sub help {
	my ( $self, $name, $value ) = @_;

	if( scalar( @_ ) > 1 ){
		$self->{_ioptionable}{$name} = $value;
		$self->{_ioptionable}{$name.'_set'} = true;
	}

	return $self->{_ioptionable}{help};
};

# -------------------------------------------------------------------------------------------------
# Getter/Setter
# (I):
# - this TTP::IOptionable (self)
# - when called by GetOptions(), the option name
# - when called by GetOptions(), the option value
# (O):
# - whether the run is verbose: true|false

sub verbose {
	my ( $self, $name, $value ) = @_;

	if( scalar( @_ ) > 1 ){
		$self->{_ioptionable}{$name} = $value;
		$self->{_ioptionable}{$name.'_set'} = true;
	}

	return $self->{_ioptionable}{verbose};
};

# -------------------------------------------------------------------------------------------------
# IOptionable initialization
# Initialization of a command or of an external script
# (I):
# - this TTP::IOptionable (self)
# - the TTP EntryPoint
# - other args as provided to the constructor
# (O):
# -none

after _newBase => sub {
	my ( $self, $ep, $args ) = @_;
	$args //= {};

	$self->{_ioptionable} //= {};

	# initialize the standard options
	if( $ep->runner()){
		msgErr( "unexpected runner alreay set when instanciating IOptionable self=".ref( $self ));
		TTP::stackTrace();
	} else {
		$self->{_ioptionable}{help} = false;
		$self->{_ioptionable}{help_set} = false;
		$self->{_ioptionable}{colored} = false;
		$self->{_ioptionable}{colored_set} = false;
		$self->{_ioptionable}{dummy} = false;
		$self->{_ioptionable}{dummy_set} = false;
		$self->{_ioptionable}{verbose} = false;
		$self->{_ioptionable}{verbose_set} = false;
		print STDERR __PACKAGE__."::after_newBase() self=".ref( $self )." initialize IOptionable options to false".EOL if $ENV{TTP_DEBUG};
	}

	# Set the help flag to true if there are not enough arguments in the command-line
	# the minimum count of arguments MUST be defined by the implementation class
	print STDERR __PACKAGE__."::after_newBase() self=".ref( $self )." scalar \@ARGV=".( scalar( @ARGV )) if $ENV{TTP_DEBUG};
	if( scalar( @ARGV ) < $self->minArgsCount()){
		$self->{_ioptionable}{help} = true;
		print STDERR " set help=true" if $ENV{TTP_DEBUG};
	}
	print STDERR EOL if $ENV{TTP_DEBUG};
};

### Global functions
### Note for the developer: while a global function doesn't take any argument, it can be called both
### as a class method 'TTP::Package->method()' or as a global function 'TTP::Package::method()',
### the former being preferred (hence the writing inside of the 'Class methods' block which brings
### the class as first argument).

1;

__END__
