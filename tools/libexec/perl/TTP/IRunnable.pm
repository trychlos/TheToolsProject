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
# A role to be composed by both commands+verbs and external commands.
# Take care of initializing to-be-logged words said as qualifiers
# - name, e.g. 'ttp.pl'
# - qualifier, e.g. 'vars'
# 

package TTP::IRunnable;
die __PACKAGE__ . " must be loaded as TTP::IRunnable\n" unless __PACKAGE__ eq 'TTP::IRunnable';

our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Data::Dumper;
use File::Spec;
use Time::Moment;

use TTP;
use TTP::Constants qw( :all );
use TTP::Message qw( :all );

### https://metacpan.org/pod/Role::Tiny
### All subs created after importing Role::Tiny will be considered methods to be composed.
use Role::Tiny;

requires qw( _newBase );

# -------------------------------------------------------------------------------------------------
# Getter
# Returns the IRunnable name
# (I):
# - none
# (O):
# - the command e.g. 'ttp.pl'

sub command {
	my ( $self ) = @_;

	return $self->runnableBNameFull();
}

# -------------------------------------------------------------------------------------------------
# Getter
# Returns the IRunnable command-line arguments
# (I):
# - none
# (O):
# - the arguments as an array ref

sub runnableArgs {
	my ( $self ) = @_;

	return \@{$self->{_irunnable}{argv}};
}

# -------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - returns the computed basename of the runnable (e.g. 'ttp.pl')

sub runnableBNameFull {
	my ( $self ) = @_;

	return $self->{_irunnable}{basename};
};

# -------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# -returns the computed name (without extension) of the runnable (e.g. 'ttp')

sub runnableBNameShort {
	my ( $self ) = @_;

	return $self->{_irunnable}{namewoext};
};

# -------------------------------------------------------------------------------------------------
# Getter/Setter
# (I):
# - an optional error code to be set
# (O):
# - returns the current count of errors

sub runnableErrs {
	my ( $self, $code ) = @_;

	$self->{_irunnable}{errs} = $code if defined $code;

	return $self->{_irunnable}{errs};
};

# -------------------------------------------------------------------------------------------------
# Increment the errors count
# (I):
# - none
# (O):
# - returns the current count of errors

sub runnableErrInc {
	my ( $self ) = @_;

	$self->{_irunnable}{errs} += 1;

	return $self->runnableErrs();
};

# -------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - returns the full path of the runnable

sub runnablePath {
	my ( $self ) = @_;

	return $self->{_irunnable}{me};
};

# -------------------------------------------------------------------------------------------------
# Setter
# (I):
# - push a new qualifier to this runner
# (O):
# - returns the new list of qualifiers as an array ref

sub runnablePushQualifier {
	my ( $self, $qualifier ) = @_;
	msgDebug( __PACKAGE__."::runnablePushQualifier() '$qualifier'" );

	push( @{$self->{_irunnable}{qualifiers}}, $qualifier );

	return $self->runnableQualifiers();
};

# -------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - returns the list of qualifiers as an array ref

sub runnableQualifiers {
	my ( $self ) = @_;

	return $self->{_irunnable}{qualifiers};
};

# -------------------------------------------------------------------------------------------------
# Getter
# Returns the run mode of this command, e.g. 'sh' or 'perl'
# (I):
# - none
# (O):
# -returns the run mode

sub runnableRunMode {
	my ( $self ) = @_;

	return $self->{_irunnable}{runMode};
};

# -------------------------------------------------------------------------------------------------
# Getter
# Returns the start time of this runnable
# (I):
# - none
# (O):
# -returns the start time

sub runnableStarted {
	my ( $self ) = @_;

	return $self->{_irunnable}{started};
};

# -------------------------------------------------------------------------------------------------
# IRunnable initialization
# Initialization of a command or of an external script
# (I):
# - this TTP::IRunnable (self)
# - the TTP EntryPoint
# - other args as provided to the constructor
# (O):
# -none

after _newBase => sub {
	my ( $self, $ep, $args ) = @_;
	$args //= {};
	$self->{_irunnable} //= {};
	msgDebug( __PACKAGE__."::after_newBase() ttp_me='".( $ENV{ttp_me} || "" )."' \$0='$0' \@ARGV=[".join( ',', @ARGV )."]" );

	# Starting with v4, TheToolsProject is merged with the sh version. If a 'ttp_me' environment variable
	#  exists, then this perl is embedded into a sh run. So shift the command-line arguments
	$self->{_irunnable}{me} = $0;
	if( $ENV{ttp_me} ){
		$self->{_irunnable}{me} = shift @ARGV;
		if( $ENV{ttp_me} eq "sh/ttpf_main" ){
			$self->{_irunnable}{runMode} = "sh";
		} else {
			msgErr( __PACKAGE__."::after_newBase() $ENV{ttp_me}='".$ENV{ttp_me}." which is not managed" );
			TTP::stackTrace();
		}
	} else {
			$self->{_irunnable}{runMode} = "perl";
	}

	my @argv = @ARGV;
	$self->{_irunnable}{argv} = \@argv;
	$self->{_irunnable}{started} = Time::Moment->now;
	$self->{_irunnable}{errs} = 0;

	my( $vol, $dirs, $file ) = File::Spec->splitpath( $self->{_irunnable}{me} );
	$self->{_irunnable}{basename} = $file;
	$file =~ s/\.[^\.]+$//;
	$self->{_irunnable}{namewoext} = $file;

	# starting with v4.7 we prefer manage a list of qualifiers which are logged as the program name and its main component, but is not limited to
	# here the first qualifier is set as soon as runner instanciation
	$self->{_irunnable}{qualifiers} = [];
	$self->runnablePushQualifier( $self->runnableBNameFull());

	msgLog( "[] executing $self->{_irunnable}{me} ".join( ' ', @ARGV ));
	$ep->runner( $self );
	$SIG{INT} = sub {
		msgVerbose( "quitting on Ctrl+C keyboard interrupt" );
		TTP::exit();
	}
};

### Global functions
### Note for the developer: while a global function doesn't take any argument, it can be called both
### as a class method 'TTP::Package->method()' or as a global function 'TTP::Package::method()',
### the former being preferred (hence the writing inside of the 'Class methods' block which brings
### the class as first argument).

1;

__END__
