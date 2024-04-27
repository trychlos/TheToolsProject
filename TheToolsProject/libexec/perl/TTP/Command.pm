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
# In the command 'ttp.pl' in the 'ttp.pl vars --logsRoot', we call:
# - a 'command' the first executed word, here: 'ttp.pl'
# - a 'verb' the second word, here 'vars'.
#
# Verbs are executed in this Command context.

package TTP::Command;

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use warnings;

use Carp;
use Config;
use Data::Dumper;
use Getopt::Long;
use Role::Tiny::With;
use Try::Tiny;
use vars::global qw( $ttp );

with 'TTP::Findable', 'TTP::Helpable', 'TTP::Optionable', 'TTP::Runnable';

use TTP;
use TTP::Constants qw( :all );
use TTP::Message qw( :all );

my $Const = {
	# reserved words: the commands must be named outside of this array
	#  either because they are folders of the Toops installation tree
	reservedWords => [
		'bin',
		'libexec',
		'Mods',
		'Toops',
		'TTP'
	],
	verbSed => '\.do\.pl$',
	verbSufix => '.do.pl',
	# these constants are needed to 'ttp.pl list --commands'
	finder => {
		dirs => [
			'bin'
		],
		sufix => '.pl'
	}
};

### Private methods

# -------------------------------------------------------------------------------------------------
# returns the available verbs for the current command
# (O):
# - a ref to an array of full paths of available verbs for the current command

sub _getVerbs {
	my ( $self ) = @_;
	# get all available verbs
	my $findable = {
		dirs => [ $self->runnableBNameShort() ],
		glob => '*'.$Const->{verbSufix}
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

# -------------------------------------------------------------------------------------------------
# command initialization
# (I]:
# - none
# (O):
# - this object

sub _init {
	my ( $self ) = @_;

	# make sure the command is not a reserved word
	my $command = $self->runnableBNameShort();
	if( grep( /^$command$/, @{$Const->{reservedWords}} )){
		msgErr( "command '$command' is a Toops reserved word. Aborting." );
		TTP::exit();
	}

	return $self;
}

### Public methods

# -------------------------------------------------------------------------------------------------
# Getter
# Returns the command name
# (I]:
# - none
# (O):
# - the command e.g. 'ttp.pl'

sub command {
	my ( $self ) = @_;

	return $self->runnableBNameFull();
}

# -------------------------------------------------------------------------------------------------
# Command help
# Display the command help as:
# - a one-liner from the command itself
# - and the one-liner help of each available verb
# Verbs are displayed as an ASCII-sorted (i.e. in [0-9A-Za-z] order) list
# (I]:
# - none
# (O):
# - this object

sub commandHelp {
	my ( $self ) = @_;
	msgVerbose( __PACKAGE__."::commandHelp()" );

	# display the command one-line help
	$self->helpOneline( $self->runnablePath());

	# display each verb one-line help
	my @verbs = $self->_getVerbs();
	my $verbsHelp = {};
	foreach my $it ( @verbs ){
		my @fullHelp = $self->helpPre( $it, { warnIfSeveral => false });
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
# run the command
# (I]:
# - none
# (O):
# - this object

sub run {
	my ( $self ) = @_;

	try {
		# first argument is supposed to be the verb
		my @command_args = @ARGV;
		$self->{_verb} = {};
		if( scalar @command_args ){
			my $verb = shift( @command_args );
			$self->{_verb}{args} = \@command_args;

			# search for the verb
			my $findable = {
				dirs => [ $self->runnableBNameShort(), $verb.$Const->{verbSufix} ],
				wantsAll => false
			};
			$self->{_verb}{path} = $self->find( $findable );

			# if found, then execute it with our global variables
			if( $self->{_verb}{path} ){
				$self->runnableSetQualifier( $verb );

				# as verbs are written as Perl scripts, they are dynamically ran from here in the context of 'self'
				# + have direct access to 'ttp' entry point
				local @ARGV = @command_args;
				our $running = $ttp->runner();

				unless( defined do $self->{_verb}{path} ){
					msgErr( "do $self->{_verb}{path}: ".( $! || $@ ));
				}
			} else {
				msgErr( "script not found or not readable in [$ENV{TTP_ROOTS}]: '$verb$Const->{verbSufix}'" );
				msgErr( "is it possible that '$verb' be not a valid verb ?" );
			}
		} else {
			$self->commandHelp();
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
# (I]:
# - none
# (O):
# - the verb, e.g. 'vars'

sub verb {
	my ( $self ) = @_;

	return $self->runnableQualifier();
}

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

sub verbHelp {
	my ( $self, $defaults ) = @_;

	msgVerbose( "helpVerb()" );
	# display the command one-line help
	$self->helpOneline( $self->runnablePath());
	# verb pre-usage
	my @verbHelp = $self->helpPre( $self->{_verb}{path}, { warnIfSeveral => false });
	my $verbInline = '';
	if( scalar @verbHelp ){
		$verbInline = shift @verbHelp;
	}
	print "  ".$self->verb().": $verbInline".EOL;
	foreach my $line ( @verbHelp ){
		print "    $line".EOL;
	}
	# verb usage
	@verbHelp = $self->helpUsage( $self->{_verb}{path}, { warnIfSeveral => false });
	if( scalar @verbHelp ){
		print "    Usage: ".$self->command()." ".$self->verb()." [options]".EOL;
		print "    where available options are:".EOL;
		foreach my $line ( @verbHelp ){
			$line =~ s/\$\{?(\w+)}?/$defaults->{$1}/e;
			print "      $line".EOL;
		}
	}
	# verb post-usage
	@verbHelp = $self->helpPost( $self->{_verb}{path}, { warnIfNone => false, warnIfSeveral => false });
	if( scalar @verbHelp ){
		foreach my $line ( @verbHelp ){
			print "    $line".EOL;
		}
	}

	return $self;
}

### Class methods

# -------------------------------------------------------------------------------------------------
# Returns const needed by 'ttp.pl list --commands'

sub finder {
	return $Const->{finder};
}

# -------------------------------------------------------------------------------------------------
# Constructor
# (I]:
# - the TTP EP entry point
# (O):
# - this object

sub new {
	my ( $class, $ttp ) = @_;
	$class = ref( $class ) || $class;
	my $self = $class->SUPER::new( $ttp );
	bless $self, $class;

	# command initialization
	$self->_init();

	return $self;
}

# -------------------------------------------------------------------------------------------------
# Destructor
# (I]:
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
