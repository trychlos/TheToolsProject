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
# http.pl compare queue item.
# Each link or clickable is queued as a QueueItem item.

package TTP::HTTP::Compare::QueueItem;
die __PACKAGE__ . " must be loaded as TTP::HTTP::Compare::QueueItem\n" unless __PACKAGE__ eq 'TTP::HTTP::Compare::QueueItem';

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Data::Dumper;
use Scalar::Util qw( blessed );

use TTP;
use vars::global qw( $ep );

use TTP::Constants qw( :all );
use TTP::Message qw( :all );

use constant {
};

my $Const = {
};

### Private methods

# -------------------------------------------------------------------------------------------------
# Duplication and remove existing chain
# (I):
# - nothing
# (O):
# - a new QueueItem, identical to self, but without chain

sub _dup_wo_chain {
	my ( $self ) = @_;

	return TTP::HTTP::Compare::QueueItem->new( $self->ep(), $self->{_conf}, $self->hash());
}

### Public methods

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - the array of clicks or links which were current when this click or link has been discovered, maybe empty

sub chain {
	my ( $self ) = @_;

	#print STDERR "hash: ".Dumper( $self->{_hash} );
	return $self->{_hash}{chain} // [];
}

# -------------------------------------------------------------------------------------------------
# Build a chain which includes the current chain + this queue item
# (I):
# - nothing
# (O):
# - the new chain, as an array ref

sub chain_plus {
	my ( $self ) = @_;

	my @chain = @{ $self->chain() };
	#print STDERR "chain_1: ".ref( \@chain ).", scalar=".( scalar( @chain )).", dump=".Dumper( \@chain );

	push( @chain, $self->_dup_wo_chain());
	#print STDERR "chain_2: ".ref( \@chain ).", scalar=".( scalar( @chain )).", dump=".Dumper( \@chain );

	return \@chain;
}

# -------------------------------------------------------------------------------------------------
# getter/setter
# we may want register the destination state_key in the queue item
# so that initialized routes - which do not have any origin - have still a state to rely on
# (I):
# - nothing
# (O):
# - returns the dest key, may be empty

sub dest {
	my ( $self, $dest ) = @_;

	$self->{_hash}{dest} = $dest if defined $dest;

	$dest = $self->{_hash}{dest} // '';

	return $dest;
}

# -------------------------------------------------------------------------------------------------
# Dump the object
# (I):
# - an optional options hash with following keys:
#   > prefix: a prefix, defaulting to ''

sub dump {
	my ( $self, $args ) = @_;
	$args //= {};
	my $prefix = $args->{prefix} // '';

	if( $prefix ){
		print STDERR "$prefix {".EOL;
	} else {
		print STDERR "QueueItem: {".EOL;
	}
	foreach my $k ( sort keys %{ $self->{_hash} }){
		if( $k eq 'chain' ){
			print STDERR "$prefix    '$k' => [".EOL;
			foreach my $it ( @{$self->{_hash}{$k}} ){
				$it->dump({ prefix => "             " });
			}
			print STDERR "$prefix    ]".EOL;
		} else {
			print STDERR "$prefix    '$k' => $self->{_hash}{$k}".EOL;
		}
	}
	print STDERR "$prefix}".EOL;
}

# -------------------------------------------------------------------------------------------------
# Says where the queue item comes from
# (I):
# - nothing
# (O):
# - the 'from' information, either 'link' or 'click', defaulting to 'link'

sub from {
	my ( $self ) = @_;

	my $from = $self->{_hash}{from};

	if( !$from ){
		$from = 'link';
		$self->{_hash}{from} = $from;

	} elsif( $from ne 'link' && $from ne 'click' ){
		msgWarn( "unexpected from='$from', reset to 'link'" );
		$from = 'link';
		$self->{_hash}{from} = $from;
	}

	return $from;
}

# -------------------------------------------------------------------------------------------------
# Though a QueueItem class is useful when writing Perl, this is counter-productive when passing
#  data to javascript which wants just plain JS objects
# (I):
# - nothing
# (O):
# - returns: the data hash (without the chain array)

sub hash {
	my ( $self ) = @_;

	my %hash = %{ $self->{_hash} };
	delete $hash{chain};

	return \%hash;
}

# -------------------------------------------------------------------------------------------------
# Says if the queue item is a click
# (I):
# - nothing
# (O):
# - whether the item is from a click

sub isClick {
	my ( $self ) = @_;

	my $from = $self->from();

	return $from eq 'click';
}

# -------------------------------------------------------------------------------------------------
# Says if the queue item is a link
# (I):
# - nothing
# (O):
# - whether the item is from a link

sub isLink {
	my ( $self ) = @_;

	my $from = $self->from();

	return $from eq 'link';
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - the signature which identifies the current queue item (and so the targeted place)
#   this very same key is used to identify the already seen places

sub signature {
	my ( $self ) = @_;

	my $from = $self->from();
	my $add = '';

	if( $from eq 'link' ){
		$add = $self->path();

	} elsif( $from eq 'click' ){
		$add = $self->origin()."|".$self->xpath();

	} else {
		msgWarn( "key() unexpected from='$from'" );
	}

	my $key = "$from|$add";

	return $key;
}

# -------------------------------------------------------------------------------------------------
# getter/setter
# (I):
# - nothing
# (O):
# - returns the origin key which may be empty for initial routes

sub origin {
	my ( $self, $origin ) = @_;

	$self->{_hash}{origin} = $origin if defined $origin;

	$origin = $self->{_hash}{origin} // '';

	return $origin;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - returns the path, only available if from is link

sub path {
	my ( $self ) = @_;

	my $path = undef;

	if( $self->isLink()){
		$path = $self->{_hash}{path} // '/';
	}

	return $path;
}

# -------------------------------------------------------------------------------------------------
# Getter/Setter
# (I):
# - an optional counter,
#   let set the visited counter when the queue item is shifted out of the queue,
#   and after the visit counter has been incremented
# (O):
# - either the input counter, or the previously set counter, or 0

sub visited {
	my ( $self, $counter ) = @_;

	if( defined( $counter )){
		$self->{_hash}{visited} = $counter;
	}

	return $self->{_hash}{visited} // 0;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - returns the target xpath, only available if from is click

sub xpath {
	my ( $self ) = @_;

	my $xpath = undef;

	if( $self->isClick()){
		$xpath = $self->{_hash}{xpath};
	}

	return $xpath;
}

### Class methods

# -------------------------------------------------------------------------------------------------
# Constructor
# (I):
# - the TTP::EP entry point
# - the TTP::HTTP::Compare::Config configuration object
# - an arguments hash, with following keys:
#   > from='link|click', defaulting to 'link'
#   if from='link':
#   > path
#   > depth, defaulting to zero
#   if from='click':
#   > xpath
#   > origin
# (O):
# - this object

sub new {
	my ( $class, $ep, $conf, $hash ) = @_;
	$class = ref( $class ) || $class;

	if( !$ep || !blessed( $ep ) || !$ep->isa( 'TTP::EP' )){
		msgErr( "unexpected ep: ".TTP::chompDumper( $ep ));
		TTP::stackTrace();
	}
	if( !$conf || !blessed( $conf ) || !$conf->isa( 'TTP::HTTP::Compare::Config' )){
		msgErr( "unexpected conf: ".TTP::chompDumper( $conf ));
		TTP::stackTrace();
	}

	my $self = $class->SUPER::new( $ep );
	bless $self, $class;
	msgDebug( __PACKAGE__."::new()" );

	$self->{_conf} = $conf;
	$self->{_hash} = $hash;

	return $self;
}

### Global functions
### Note for the developer: while a global function doesn't take any argument, it can be called both
### as a class method 'TTP::Package->method()' or as a global function 'TTP::Package::method()',
### the former being preferred (hence the writing inside of the 'Class methods' block which brings
### the class as first argument).

1;
