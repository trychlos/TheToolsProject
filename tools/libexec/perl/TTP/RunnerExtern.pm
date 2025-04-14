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

package TTP::RunnerExtern;

use base qw( TTP::Runner );
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Carp;
use Config;
use Data::Dumper;
use Getopt::Long;
use Try::Tiny;
use vars::global qw( $ep );

use TTP;
use TTP::Constants qw( :all );
use TTP::EP;
use TTP::Message qw( :all );

my $Const = {
};

### Private methods

### Public methods

# -------------------------------------------------------------------------------------------------
# Display an external command help
# This is a one-shot help: all the help content is printed here
# (I):
# - a hash which contains default values

sub displayHelp {
	my ( $self, $defaults ) = @_;

	# pre-usage
	my @help = $self->helpablePre( $self->runnablePath(), { warnIfSeveral => false });
	foreach my $it ( @help ){
		print " $it".EOL;
	}

	# usage
	@help = $self->helpableUsage( $self->runnablePath(), { warnIfSeveral => false });
	if( scalar @help ){
		print "   Usage: ".$self->runnableBNameFull()." [options]".EOL;
		print "   where available options are:".EOL;
		foreach my $it ( @help ){
			$it =~ s/\$\{?(\w+)}?/$defaults->{$1}/e;
			print "     $it".EOL;
		}
	}

	# post-usage
	@help = $self->helpablePost( $self->runnablePath(), { warnIfNone => false, warnIfSeveral => false });
	foreach my $it ( @help ){
		print " $it".EOL;
	}
}

### Class methods

# -------------------------------------------------------------------------------------------------
# Constructor
# To be called at the very early run of an external program.
# (I):
# - the TTP EntryPoint
# (O):
# - this object, or undef

sub new {
	my ( $class, $ep ) = @_;
	$class = ref( $class ) || $class;
	my $self = $class->SUPER::new( $ep );
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
	$self->SUPER::DESTROY();
	return;
}

### Global functions
### Note for the developer: while a global function doesn't take any argument, it can be called both
### as a class method 'TTP::Package->method()' or as a global function 'TTP::Package::method()',
### the former being preferred (hence the writing inside of the 'Class methods' block which brings
### the class as first argument).

# -------------------------------------------------------------------------------------------------
# instanciates and run the external command
# (I):
# - the TTP EntryPoint
# (O):
# - the newly instanciated RunnerExtern

sub runCommand {
	my ( $ep ) = @_;
	print STDERR __PACKAGE__."::run() ep=".ref( $ep ).EOL if $ENV{TTP_DEBUG};

	my $command = TTP::RunnerExtern->new( $ep );
	$command->run();

	return $command;
}

1;

__END__
