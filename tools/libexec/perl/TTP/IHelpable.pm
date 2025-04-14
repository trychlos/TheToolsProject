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
# Manage the helps both for commands+verbs than for external scripts.

package TTP::IHelpable;
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Data::Dumper;
use Path::Tiny qw( path );
use vars::global qw( $ep );

use TTP;
use TTP::Constants qw( :all );
use TTP::Message qw( :all );

my $Const = {
	commentPre => '^# @\(#\) ',
	commentPost => '^# @\(@\) ',
	commentUsage => '^# @\(-\) ',
};

### https://metacpan.org/pod/Role::Tiny
### All subs created after importing Role::Tiny will be considered methods to be composed.
use Role::Tiny;

requires qw( _newBase );

# -------------------------------------------------------------------------------------------------
# greps a file with a regex
# (I):
# - the filename to be grep-ed
# - the regex to apply
# - an optional options hash with following keys:
#   > warnIfNone defaulting to true
#   > warnIfSeveral defaulting to true
#   > replaceRegex defaulting to true
#   > replaceValue, defaulting to empty
# (O):
# always returns an array, maybe empty

sub grepFileByRegex {
	my ( $self, $filename, $regex, $opts ) = @_;
	$opts //= {};
	local $/ = "\n";
	my @content = path( $filename )->lines_utf8;
	chomp @content;
	my @grepped = grep( /$regex/, @content );
	# warn if grepped is empty ?
	my $warnIfNone = true;
	$warnIfNone = $opts->{warnIfNone} if exists $opts->{warnIfNone};
	if( scalar @grepped == 0 ){
		msgWarn( "'$filename' doesn't have any line with the searched content ('$regex')." ) if $warnIfNone;
	} else {
		# warn if there are several lines in the grepped result ?
		my $warnIfSeveral = true;
		$warnIfSeveral = $opts->{warnIfSeveral} if exists $opts->{warnIfSeveral};
		if( scalar @grepped > 1 ){
			msgWarn( "'$filename' has more than one line with the searched content ('$regex')." ) if $warnIfSeveral;
		}
	}
	# replace the regex, and, if true, with what ?
	my $replaceRegex = true;
	$replaceRegex = $opts->{replaceRegex} if exists $opts->{replaceRegex};
	if( $replaceRegex ){
		my @temp = ();
		my $replaceValue = '';
		$replaceValue = $opts->{replaceValue} if exists $opts->{replaceValue};
		foreach my $line ( @grepped ){
			$line =~ s/$regex/$replaceValue/;
			push( @temp, $line );
		}
		@grepped = @temp;
	}
	return @grepped;
}

# -------------------------------------------------------------------------------------------------
# Display an external command help
# This is a one-shot help: all the help content is printed here
# (I):
# - a hash which contains default values

sub helpExtern {
	my ( $self, $defaults ) = @_;

	# pre-usage
	my @help = $self->helpPre( $self->runnablePath(), { warnIfSeveral => false });
	foreach my $it ( @help ){
		print " $it".EOL;
	}

	# usage
	@help = $self->helpUsage( $self->runnablePath(), { warnIfSeveral => false });
	if( scalar @help ){
		print "   Usage: ".$self->runnableBNameFull()." [options]".EOL;
		print "   where available options are:".EOL;
		foreach my $it ( @help ){
			$it =~ s/\$\{?(\w+)}?/$defaults->{$1}/e;
			print "     $it".EOL;
		}
	}

	# post-usage
	@help = $self->helpPost( $self->runnablePath(), { warnIfNone => false, warnIfSeveral => false });
	foreach my $it ( @help ){
		print " $it".EOL;
	}
}

# -------------------------------------------------------------------------------------------------
# Display the command one-liner help
# (I):
# - the full path to the command
# - an optional options hash with following keys:
#   > prefix: the line prefix, defaulting to ''

sub helpOneline {
	my ( $self, $command_path, $opts ) = @_;
	$opts //= {};
	my $prefix = '';
	$prefix = $opts->{prefix} if exists( $opts->{prefix} );
	my ( $vol, $dirs, $bname ) = File::Spec->splitpath( $command_path );
	my @help = $self->grepFileByRegex( $command_path, $Const->{commentPre} );
	print "$prefix$bname: $help[0]".EOL;
}

# -------------------------------------------------------------------------------------------------
# Returns the post-usage lines of the specified file
# (I):
# - the full path to the command
# - an optional options hash to be passed to grepFileByRegex() method

sub helpPost {
	my ( $self, $path, $opts ) = @_;
	$opts //= {};

	return $self->grepFileByRegex( $path, $Const->{commentPost}, $opts );
}

# -------------------------------------------------------------------------------------------------
# Returns the pre-usage lines of the specified file
# (I):
# - the full path to the command
# - an optional options hash to be passed to grepFileByRegex() method

sub helpPre {
	my ( $self, $path, $opts ) = @_;
	$opts //= {};

	return $self->grepFileByRegex( $path, $Const->{commentPre}, $opts );
}

# -------------------------------------------------------------------------------------------------
# Returns the usage lines of the specified file
# (I):
# - the full path to the command
# - an optional options hash to be passed to grepFileByRegex() method

sub helpUsage {
	my ( $self, $path, $opts ) = @_;
	$opts //= {};

	return $self->grepFileByRegex( $path, $Const->{commentUsage}, $opts );
}

# -------------------------------------------------------------------------------------------------
# IHelpable initialization
# (I):
# - this TTP::IHelpable (self)
# - the TTP EntryPoint
# - other args as provided to the constructor
# (O):
# -none

after _newBase => sub {
	my ( $self, $ep, $args ) = @_;

	$self->{_ihelpable} //= {};
};

### Global functions
### Note for the developer: while a global function doesn't take any argument, it can be called both
### as a class method 'TTP::Package->method()' or as a global function 'TTP::Package::method()',
### the former being preferred (hence the writing inside of the 'Class methods' block which brings
### the class as first argument).

1;

__END__
