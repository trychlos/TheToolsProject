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
# The options management of commands+verbs and external scripts.
#
# 'help', 'colored', 'dummy' and 'verbose' option flags are set into ttp->{run} hash both for
# historical reasons and for the ease of handlings.
# They are all initiallized to false at Optionable instanciation time.
#
# 'help' is automatically set when there the command-line only contains the command, or the command
# and the verb. After that, this is managed by GetOptions().
#
# 'colored' is message-evel dependant (see Message.pm), and defaults to be ignored for msgLog(),
# false for msgOut(), true in all other cases.
#
# After their initialization here, 'dummy' and 'verbose' flags only depend of GetOptions().

package TTP::IOptionable;
our $VERSION = '1.00';

use Carp;
use Data::Dumper;
use vars::global qw( $ttp );

use TTP::Constants qw( :all );
use TTP::Message qw( :all );

### https://metacpan.org/pod/Role::Tiny
### All subs created after importing Role::Tiny will be considered methods to be composed.
use Role::Tiny;

requires qw( _newBase run );

# -------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - whether the output should be colored: true|false

sub colored {
	my ( $self ) = @_;

	return $ttp->{run}{colored} > 0;
};

# -------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - whether the --colored option has been specified in the command-line

sub coloredSet {
	my ( $self ) = @_;

	return $ttp->{run}{colored} != -1;
};

# -------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - whether the run is dummy: true|false

sub dummy {
	my ( $self ) = @_;

	return $ttp->{run}{dummy};
};

# -------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - whether the help should be displayed: true|false

sub help {
	my ( $self ) = @_;

	return $ttp->{run}{help};
};

# -------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - whether the run is verbose: true|false

sub verbose {
	my ( $self ) = @_;

	return $ttp->{run}{verbose};
};

# -------------------------------------------------------------------------------------------------
# Optionable initialization
# Initialization of a command or of an external script
# (I):
# - none
# (O):
# -none

after _newBase => sub {
	my ( $self, $ttp, $args ) = @_;
	$args //= {};
	 #print __PACKAGE__."::new()".EOL;

	$self->{_ioptionable} //= {};

	# set these standard options in ttp->{run} both for historical reasons and for easier handlings
	if( !$ttp->runner()){
		$ttp->{run} //= {};
		$ttp->{run}{help} = false;
		$ttp->{run}{colored} = -1;
		$ttp->{run}{dummy} = false;
		$ttp->{run}{verbose} = false;
	}
};

# -------------------------------------------------------------------------------------------------
# Set the help flag to true if there is not enough arguments in the command-line
# (I):
# - none
# (O):
# -none

before run => sub {
	my ( $self ) = @_;

	$ttp->{run}{help} = true if scalar @ARGV <= 1;
};

### Global functions

1;

__END__
