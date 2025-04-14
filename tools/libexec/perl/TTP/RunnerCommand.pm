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
# In the command 'ttp.pl' in the 'ttp.pl vars --logsRoot', we call:
# - a 'command' the first executed word, here: 'ttp.pl'
# - a 'verb' the second word, here 'vars'.
#
# Verbs are executed in this RunnerCommand context.

package TTP::RunnerCommand;

use base qw( TTP::Runner );
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

with 'TTP::IFindable';

use TTP;
use TTP::Constants qw( :all );
use TTP::Message qw( :all );

my $Const = {
	# the minimal count of arguments to trigger the help display
	minArgsCount => 2,
	# reserved words: the commands must be named outside of this array
	#  because they are current or historic folders of the TTP installation tree
	reservedWords => [
		'bin',
		'libexec',
		'Mods',
		'TTP',
		'TTP'
	],
	verbSed => '\.do\.pl$|\.do\.ksh$',
	verbSufixes => {
		perl => '.do.pl',
		sh => '.do.ksh'
	},
	# these constants are needed to 'ttp.pl list --commands'
	finder => {
		dirs => [
			'bin'
		],
		suffix => '.pl'
	}
};

### Private methods

# -------------------------------------------------------------------------------------------------
# Command help
# Display the command help as:
# - a one-liner from the command itself
# - and the one-liner help of each available verb
# Verbs are displayed as an ASCII-sorted (i.e. in [0-9A-Za-z] order) list
# (I):
# - none
# (O):
# - this object

sub _commandHelp {
	my ( $self ) = @_;

	# display the command one-line help
	$self->helpableOneLine( $self->runnablePath());

	# display each verb one-line help
	my @verbs = $self->_getVerbs();
	my $verbsHelp = {};
	foreach my $it ( @verbs ){
		my @fullHelp = $self->helpablePre( $it, { warnIfSeveral => false });
		my ( $volume, $directories, $file ) = File::Spec->splitpath( $it );
		my $verb = $file;
		$verb =~ s/$Const->{verbSed}$//;
		$verbsHelp->{$verb} = $fullHelp[0];
	}

	# verbs are displayed alpha sorted
	foreach my $it ( sort keys %{$verbsHelp} ){
		print "  $it: $verbsHelp->{$it}".EOL;
	}

	return $self;
}

# -------------------------------------------------------------------------------------------------
# returns the available verbs for the current command
# (O):
# - a ref to an array of full paths of available verbs for the current command

sub _getVerbs {
	my ( $self ) = @_;
	# get all available verbs
	my $findable = {
		dirs => [ $self->runnableBNameShort() ],
		glob => '*'.$Const->{verbSufixes}{$self->runnableRunMode()}
	};
	my $verbs = $self->find( $findable );
	# get only unique available verbs
	my $uniqs = {};
	foreach my $it ( @{$verbs} ){
		my ( $vol, $dirs, $file ) = File::Spec->splitpath( $it );
		$uniqs->{$file} = $it if !exists( $uniqs->{$file} );
	}
	my @verbs = ();
	# and display them in ascii order
	foreach my $it ( sort keys %{$uniqs} ){
		push( @verbs, $uniqs->{$it} );
	}

	return @verbs;
}

### Public methods

# -------------------------------------------------------------------------------------------------
# Verb help
# Display the full verb help
# - the one-liner help of the command
# - the full help of the verb as:
#   > a pre-usage help
#   > the usage of the verb
#   > a post-usage help
# (I):
# - a hash which contains default values
# (O):
# - this object

sub displayHelp {
	my ( $self, $defaults ) = @_;

	# display the command one-line help
	$self->helpableOneLine( $self->runnablePath());

	# verb pre-usage
	my @displayHelp = $self->helpablePre( $self->{_verb}{path}, { warnIfSeveral => false });
	my $verbInline = '';
	if( scalar @displayHelp ){
		$verbInline = shift @displayHelp;
	}
	print "  ".$self->verb().": $verbInline".EOL;
	foreach my $line ( @displayHelp ){
		print "    $line".EOL;
	}

	# verb usage
	@displayHelp = $self->helpableUsage( $self->{_verb}{path}, { warnIfSeveral => false });
	if( scalar @displayHelp ){
		print "    Usage: ".$self->command()." ".$self->verb()." [options]".EOL;
		print "    where available options are:".EOL;
		foreach my $line ( @displayHelp ){
			$line =~ s/\$\{?(\w+)}?/$defaults->{$1}/e;
			print "      $line".EOL;
		}
	}

	# verb post-usage
	@displayHelp = $self->helpablePost( $self->{_verb}{path}, { warnIfNone => false, warnIfSeveral => false });
	foreach my $line ( @displayHelp ){
		print "    $line".EOL;
	}

	return $self;
}

# -------------------------------------------------------------------------------------------------
# Returns the minimal count of arguments needed by the running executable
# Below this minimal count, we automatically display the runner's help
# (I):
# - the TTP EP entry point
# (O):
# - this object

sub minArgsCount {
	my ( $self ) = @_;

	return $Const->{minArgsCount};
}

# -------------------------------------------------------------------------------------------------
# run the command
# (I):
# - none
# (O):
# - this object

sub run {
	my ( $self ) = @_;
	print STDERR __PACKAGE__."::run() self=".ref( $self ).EOL if $ENV{TTP_DEBUG};

	try {
		# first argument is supposed to be the verb
		my @command_args = @ARGV;
		$self->{_verb} = {};
		if( scalar @command_args ){
			my $verb = shift( @command_args );
			$self->{_verb}{args} = \@command_args;

			# search for the verb
			my $findable = {
				dirs => [ $self->runnableBNameShort(), $verb.$Const->{verbSufixes}{$self->runnableRunMode()} ],
				wantsAll => false
			};
			$self->{_verb}{path} = $self->find( $findable );

			# if found, then execute it with our global variables
			if( $self->{_verb}{path} ){
				$self->runnableQualifier( $verb );

				# as verbs are written as Perl scripts, they are dynamically ran from here in the context of 'self'
				# + have direct access to '$ep' entry point
				local @ARGV = @command_args;
				unless( defined do $self->{_verb}{path} ){
					msgErr( "do $self->{_verb}{path}: ".( $! || $@ ));
				}
			} else {
				msgErr( "script not found or not readable in [$ENV{TTP_ROOTS}]: '$verb$Const->{verbSufix}'" );
				msgErr( "is it possible that '$verb' be not a valid verb ?" );
			}
		} else {
			$self->_commandHelp();
			TTP::exit();
		}
	} catch {
		msgVerbose( "catching exit" );
		TTP::exit();
	};

	TTP::exit();
	return $self;
}

# -------------------------------------------------------------------------------------------------
# Getter
# Returns the verb name
# (I):
# - none
# (O):
# - the verb, e.g. 'vars'

sub verb {
	my ( $self ) = @_;

	return $self->runnableQualifier();
}

### Class methods

# -------------------------------------------------------------------------------------------------
# Returns const needed by 'ttp.pl list --commands'

sub finder {
	return $Const->{finder};
}

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

	# make sure the command is not a reserved word
	my $command = $self->runnableBNameShort();
	if( grep( /^$command$/, @{$Const->{reservedWords}} )){
		msgErr( "command '$command' is a TTP reserved word. Aborting." );
		TTP::exit();
	}

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
# instanciates and run the command
# (I):
# - the TTP EntryPoint
# (O):
# - the newly instanciated RunnerCommand

sub runCommand {
	my ( $ep ) = @_;
	print STDERR __PACKAGE__."::run() ep=".ref( $ep ).EOL if $ENV{TTP_DEBUG};

	my $command = TTP::RunnerCommand->new( $ep );
	$command->run();
}

1;

__END__
