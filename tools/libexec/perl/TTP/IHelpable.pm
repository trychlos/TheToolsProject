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
die __PACKAGE__ . " must be loaded as TTP::IHelpable\n" unless __PACKAGE__ eq 'TTP::IHelpable';

our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Data::Dumper;
use Path::Tiny qw( path );

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

sub _grepFileByRegex {
	my ( $self, $filename, $regex, $opts ) = @_;
	$opts //= {};
	local $/ = "\n";
	my @content = path( $filename )->lines_utf8;
	chomp @content;
	my @grepped = grep( /$regex/, @content );
	# warn if grepped is empty ?
	my $warnIfNone = true;
	$warnIfNone = $opts->{warnIfNone} if defined $opts->{warnIfNone};
	if( scalar @grepped == 0 ){
		msgWarn( "'$filename' doesn't have any line with the searched content ('$regex')." ) if $warnIfNone;
	} else {
		# warn if there are several lines in the grepped result ?
		my $warnIfSeveral = true;
		$warnIfSeveral = $opts->{warnIfSeveral} if defined $opts->{warnIfSeveral};
		if( scalar @grepped > 1 ){
			msgWarn( "'$filename' has more than one line with the searched content ('$regex')." ) if $warnIfSeveral;
		}
	}
	# replace the regex, and, if true, with what ?
	my $replaceRegex = true;
	$replaceRegex = $opts->{replaceRegex} if defined $opts->{replaceRegex};
	if( $replaceRegex ){
		my @temp = ();
		my $replaceValue = '';
		$replaceValue = $opts->{replaceValue} if defined $opts->{replaceValue};
		foreach my $line ( @grepped ){
			$line =~ s/$regex/$replaceValue/;
			push( @temp, $line );
		}
		@grepped = @temp;
	}
	return @grepped;
}

# -------------------------------------------------------------------------------------------------
# Display the command one-liner help
# (I):
# - the full path to the command
# - an optional options hash with following keys:
#   > prefix: the line prefix, defaulting to ''

sub helpableOneLine {
	my ( $self, $command_path, $opts ) = @_;
	$opts //= {};
	my $prefix = '';
	$prefix = $opts->{prefix} if defined( $opts->{prefix} );
	my ( $vol, $dirs, $bname ) = File::Spec->splitpath( $command_path );
	my @help = $self->_grepFileByRegex( $command_path, $Const->{commentPre} );
	print "$prefix$bname: $help[0]".EOL;
}

# -------------------------------------------------------------------------------------------------
# Returns the post-usage lines of the specified file
# (I):
# - the full path to the command
# - an optional options hash to be passed to _grepFileByRegex() method

sub helpablePost {
	my ( $self, $path, $opts ) = @_;
	$opts //= {};

	return $self->_grepFileByRegex( $path, $Const->{commentPost}, $opts );
}

# -------------------------------------------------------------------------------------------------
# Returns the pre-usage lines of the specified file
# (I):
# - the full path to the command
# - an optional options hash to be passed to _grepFileByRegex() method

sub helpablePre {
	my ( $self, $path, $opts ) = @_;
	$opts //= {};

	return $self->_grepFileByRegex( $path, $Const->{commentPre}, $opts );
}

# -------------------------------------------------------------------------------------------------
# Returns the usage lines of the specified file
# (I):
# - the full path to the command
# - an optional options hash to be passed to _grepFileByRegex() method

sub helpableUsage {
	my ( $self, $path, $opts ) = @_;
	$opts //= {};

	return $self->_grepFileByRegex( $path, $Const->{commentUsage}, $opts );
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
