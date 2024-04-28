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
# A role to be composed by both commands+verbs and external commands.
# Take care of initializing to-be-logged words as:
# - name, e.g. 'ttp.pl'
# - qualifier, e.g. 'vars'

package TTP::IRunnable;
our $VERSION = '1.00';

use Carp;
use Data::Dumper;
use File::Spec;
use Time::Moment;
use vars::global qw( $ttp );

use TTP::Constants qw( :all );
use TTP::Message qw( :all );

### https://metacpan.org/pod/Role::Tiny
### All subs created after importing Role::Tiny will be considered methods to be composed.
use Role::Tiny;

requires qw( _newBase );

# -------------------------------------------------------------------------------------------------
# Getter
# Returns the Runnable name
# (I]:
# - none
# (O):
# - the command e.g. 'ttp.pl'

sub command {
	my ( $self ) = @_;

	return $self->runnableBNameFull();
}

# -------------------------------------------------------------------------------------------------
# given a command output, extracts the [command.pl verb] lines, returning the rest as an array
# (I):
# - the command output
# (O):
# - the filtered command output as an array ref

sub filter {
	my ( $self, $output ) = @_;
	my @result = ();
	my @lines = split( /[\r\n]/, $output );
	my $command = $self->command();
	foreach my $it ( @lines ){
		chomp $it;
		$it =~ s/^\s*//;
		$it =~ s/\s*$//;
		#push( @result, $it ) if !grep( /^\[|\(ERR|\(DUM|\(VER|\(WAR|^$/, $it ) && $it !~ /\(WAR\)/ && $it !~ /\(ERR\)/;
		push( @result, $it ) if $it !~ m/^\[$command/;
	}
	return \@result;
}

# -------------------------------------------------------------------------------------------------
# A placeholder run() method which does nothing but may be called even if the implementation doesn't
# need it - Let Optionable auto-initialize
# (I):
# - none
# (O):
# - nothing

sub run {
};

# -------------------------------------------------------------------------------------------------
# Getter
# Returns the Runnable command-line arguments
# (I]:
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
# Getter
# (I):
# - none
# (O):
# - returns the current count of errors

sub runnableErrs {
	my ( $self ) = @_;

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
# -returns the full path of the runnable

sub runnablePath {
	my ( $self ) = @_;

	return $self->{_irunnable}{me};
};

# -------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - returns the qualifier

sub runnableQualifier {
	my ( $self ) = @_;

	return $self->{_irunnable}{qualifier};
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
# Setter
# (I):
# - the qualifier, which is the verb for a command
# (O):
# -this same object

sub runnableSetQualifier {
	my ( $self, $qualifier ) = @_;

	$self->{_irunnable}{qualifier} = $qualifier;

	return $self;
};

# -------------------------------------------------------------------------------------------------
# Runnable initialization
# Initialization of a command or of an external script
# (I):
# - the TTP EntryPoint ref
# (O):
# -none

after _newBase => sub {
	my ( $self, $ttp, $args ) = @_;
	$args //= {};
	#print __PACKAGE__."::new()".EOL;

	$self->{_irunnable} //= {};
	$self->{_irunnable}{me} = $0;
	my @argv = @ARGV;
	$self->{_irunnable}{argv} = \@argv;
	$self->{_irunnable}{started} = Time::Moment->now;
	$self->{_irunnable}{errs} = 0;

	my( $vol, $dirs, $file ) = File::Spec->splitpath( $0 );
	$self->{_irunnable}{basename} = $file;
	$file =~ s/\.[^\.]+$//;
	$self->{_irunnable}{namewoext} = $file;

	if( !$ttp->runner()){
		msgLog( "[] executing $0 ".join( ' ', @ARGV ));
		$ttp->runner( $self );
		$SIG{INT} = sub {
			msgVerbose( "quitting on Ctrl+C keyboard interrupt" );
			TTP::exit();
		}
	}
};

### Global functions
### These can be used as such from the verbs and extern scripts

1;

__END__
