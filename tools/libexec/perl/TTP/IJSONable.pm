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
# A role for classes which have a JSON configuration file.
#
# The jsonLoad() method is expected to be called at instanciation time with arguments:
# - json specifications
#   either as a 'finder' object to be provided to the Findable::find() method
#      in this case, find() will examine all specified files until having found an
#      accepted one (or none)
#   or as a 'path' object
#      in which case, this single object must also be an accepted one.
#
# Note: JSON configuration files are allowed to embed some dynamically evaluated Perl code.
# As the evaluation is executed here, this module may have to 'use' the needed Perl packages
# which are not yet in the running context.

package TTP::IJSONable;
die __PACKAGE__ . " must be loaded as TTP::IJSONable\n" unless __PACKAGE__ eq 'TTP::IJSONable';

our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Data::Dumper;
use File::Spec;
use JSON;
use Test::Deep;

use TTP::Constants qw( :all );
use TTP::Message qw( :all );

### https://metacpan.org/pod/Role::Tiny
### All subs created after importing Role::Tiny will be considered methods to be composed.
use Role::Tiny;

requires qw( _newBase );

# -------------------------------------------------------------------------------------------------
# recursively interpret the provided data for variables and computings
#  and restart until all references have been replaced
# (I):
# - a hash object to be evaluated
# - an optional options hash with following keys:
#   > warnOnUninitialized, defaulting to true
# (O):
# - the evaluated hash object

sub _evaluate {
	my ( $self, $value, $opts ) = @_;
	$opts //= {};
	my %prev = ();
	my $result = $self->_evaluateRec( $value, $opts );
	if( $result ){
		while( !eq_deeply( $result, \%prev )){
			%prev = %{$result};
			$result = $self->_evaluateRec( $result, $opts );
		}
	}
	return $result;
}

sub _evaluateRec {
	my ( $self, $value, $opts ) = @_;
	my $result = '';
	my $ref = ref( $value );
	if( !$ref ){
		$result = $self->_evaluateScalar( $value, $opts );
	} elsif( $ref eq 'ARRAY' ){
		$result = [];
		foreach my $it ( @{$value} ){
			push( @{$result}, $self->_evaluateRec( $it, $opts ));
		}
	} elsif( $ref eq 'HASH' ){
		$result = {};
		foreach my $key ( keys %{$value} ){
			$result->{$key} = $self->_evaluateRec( $value->{$key}, $opts );
		}
	} else {
		$result = $value;
	}
	return $result;
}

sub _evaluateScalar {
	my ( $self, $value, $opts ) = @_;
	$opts //= {};
	my $ref = ref( $value );
	my $evaluate = true;
	if( $ref ){
		msgErr( __PACKAGE__."::_evaluateScalar() scalar expected, but '$ref' found" );
		$evaluate = false;
	}
	my $result = $value || '';
	if( $evaluate ){
		my $re = qr/
			[^\[]*	# anything which doesn't contain any '['
			|
			[^\[]* \[(?>[^\[\]]|(?R))*\] [^\[]*
		/x;

		# debug code
		if( false ){
			my @matches = $result =~ /\[eval:($re)\]/g;
			print "line='$result'".EOL;
			print Dumper( @matches );
		}

		# this weird code to let us manage some level of pseudo recursivity
		$result =~ s/\[eval:($re)\]/$self->_evaluatePrint( $1, $opts )/eg;
		$result =~ s/\[_eval:/[eval:/g;
		$result =~ s/\[__eval:/[_eval:/g;
		$result =~ s/\[___eval:/[__eval:/g;
		$result =~ s/\[____eval:/[___eval:/g;
		$result =~ s/\[_____eval:/[____eval:/g;
	}
	return $result;
}

sub _evaluatePrint {
	my ( $self, $value, $opts ) = @_;
	$opts //= {};
	my $result = undef;
	
	# warnings pragma acts on its own block so have to eval in the two cases
	# https://perldoc.perl.org/warnings
	my $warnOnUninitialized = true;
	$warnOnUninitialized = $opts->{warnOnUninitialized} if exists $opts->{warnOnUninitialized};
	if( $warnOnUninitialized ){
		$result = eval $value;
	} else {
		no warnings 'uninitialized';
		$result = eval $value;
		use warnings 'uninitialized';
	}

	# we cannot really emit a warning here as it is possible that we are in the way of resolving
	# a still-undefined value. so have to wait until the end to resolve all values, but too late
	# to emit a warning ?
	#msgWarn( "something is wrong with '$value' as evaluation result is undefined" ) if !defined $result;
	$result = $result || '(undef)';
	#print __PACKAGE__."::_evaluatePrint() value='$value' result='$result'".EOL;
	return $result;
}

### Public methods

# -------------------------------------------------------------------------------------------------
# Evaluates the raw data in this Perl context
# (I):
# - an optional options hash with following keys:
#   > warnOnUninitialized, defaulting to true
# (O):
# - this same object

sub evaluate {
	my ( $self, $opts ) = @_;
	$opts //= {};
	print STDERR __PACKAGE__."::evaluate() self='".ref( $self )."'".EOL if $ENV{TTP_DEBUG};

	$self->{_ijsonable}{evaluated} = $self->{_ijsonable}{raw};
	$self->{_ijsonable}{evaluated} = $self->_evaluate( $self->{_ijsonable}{raw}, $opts );

	return $self;
}

# -------------------------------------------------------------------------------------------------
# Returns the evaluated data
# (I):
# - none
# (O):
# - the evaluated data

sub jsonData {
	my ( $self, $args ) = @_;

	return $self->{_ijsonable}{evaluated};
}

# -------------------------------------------------------------------------------------------------
# Load the specified JSON configuration file
# This method is expected to be called at instanciation time.
#
# (I):
# - an argument object with following keys:

#	> path: the path as a string
#     in which case, this single object must also be an accepted one
#   or
#   > findable: an arguments object to be passed to Findable::find() method
#     in this case, find() will examine all specified files until having found an accepted one (or none)
#   This is an unrecoverable error to have both 'findable' and 'path' in the arguments object
#   or to have none of these keys.
#
#   > acceptable: an arguments object to be passed to Acceptable::accept() method
#
# (O):
# - true if a file or the specified file has been found and successfully loaded
# 

sub jsonLoad {
	my ( $self, $args ) = @_;
	$args //= {};
	print STDERR __PACKAGE__."::jsonLoad() self='".ref( $self )."' args=".TTP::chompDumper( $args ).EOL if $ENV{TTP_DEBUG};

	# keep the passed-in args
	$self->{_ijsonable}{args} = \%{$args};

	# if a path is specified, the we want this one absolutely
	# load it and see if it is accepted
	if( $args->{path} ){
		$self->{_ijsonable}{json} = File::Spec->rel2abs( $args->{path} );
		if( $self->{_ijsonable}{json} ){
			$self->{_ijsonable}{raw} = TTP::jsonRead( $self->{_ijsonable}{json} );
			if( $self->{_ijsonable}{raw} ){
				if( $self->does( 'TTP::IAcceptable' ) && $args->{acceptable} ){
					$args->{acceptable}{object} = $self->{_ijsonable}{raw};
					if( !$self->accept( $args->{acceptable} )){
						$self->{_ijsonable}{raw} = undef;
					}
				}
			}
		}

	# else hope that the class is also a Findable
	# if a Findable, it will itself manages the Acceptable role
	} elsif( $self->does( 'TTP::IFindable' ) && $args->{findable} ){
		my $res = $self->find( $args->{findable}, $args );
		if( $res ){
			my $ref = ref( $res );
			if( $ref eq 'ARRAY' ){
				$self->{_ijsonable}{json} = $res->[0] if scalar @{$res};
			} elsif( !$ref ){
				$self->{_ijsonable}{json} = $res;
			} else {
				msgErr( __PACKAGE__."::jsonLoad() expects scalar of array from Findable::find(), received '$ref'" );
			}
			if( $self->{_ijsonable}{json} ){
				$self->{_ijsonable}{raw} = TTP::jsonRead( $self->{_ijsonable}{json} );
			}
		}

	# else we have no way to find the file: this is an unrecoverable error
	} else {
		msgErr( __PACKAGE__."::jsonLoad() must have 'path' argument, or be a 'Findable' and have a 'findable' argument" );
	}

	# if the raw data has been successfully loaded (no JSON syntax error) and content has been accepted
	# then initialize the evaluated part, even if not actually evaluated, so that jsonData()
	# can at least returns raw - unevaluated - data
	if( $self->{_ijsonable}{raw} ){
		$self->{_ijsonable}{loaded} = true;
		$self->{_ijsonable}{evaluated} = $self->{_ijsonable}{raw};
	}

	my $loaded = $self->jsonLoaded();
	msgVerbose( __PACKAGE__."::jsonLoad() returning loaded='$loaded'" );
	return $loaded;
}

# -------------------------------------------------------------------------------------------------
# Getter/Setter
# Says if the JSON raw data has been successfully loaded
# (I):
# - optional boolean to set the 'loaded' status
# (O):
# - true|false

sub jsonLoaded {
	my ( $self, $loaded ) = @_;

	$self->{_ijsonable}{loaded} = $loaded if defined $loaded;

	return $self->{_ijsonable}{loaded};
}

# -------------------------------------------------------------------------------------------------
# Returns the full path to the JSON file
# (I):
# - none
# (O):
# returns the path

sub jsonPath {
	my ( $self ) = @_;

	return $self->{_ijsonable}{json};
}

# -------------------------------------------------------------------------------------------------
# returns the content of a var read from the evaluated JSON
# (I):
# - a reference to an array of keys to be read from (e.g. [ 'moveDir', 'byOS', 'MSWin32' ])
#   each key can be itself an array ref of potential candidates for this level
# - the hash ref to be searched for,
#   defaulting to this json evaluated data
# (O):
# - the evaluated value of this variable, which may be undef

my $varDebug = false;

sub var {
	my ( $self, $keys, $base ) = @_;
	# keys cannot be empty
	if( !$keys || ( ref( $keys ) eq 'ARRAY' ) && !scalar( @{$keys} )){
		msgErr( __PACKAGE__."::var() expects keys be a scalar, or an array of scalars, or an array of arrays of scalars, found empty" );
		return undef;
	}
	#$varDebug = ref( $keys ) eq 'ARRAY' && scalar( @{$keys} ) >= 3 && $keys->[1] eq 'logs' && $keys->[2] eq 'rootDir';
	print STDERR __PACKAGE__."::var() self=".ref( $self )." keys=".Dumper( $keys )." searching in ".ref( $base || $self ).EOL if $varDebug;
	#if( $varDebug ){
	#	print STDERR __PACKAGE__."::var() self ".ref( $self ).EOL;
	#	print STDERR __PACKAGE__."::var() self ".Dumper( $self );
	#	print STDERR __PACKAGE__."::var() jsonData ".Dumper( $self->jsonData());
	#}
	# if provided, base must be a HASH
	my $jsonData = undef;
	if( $base ){
		my $ref = ref( $base );
		if( $ref eq 'HASH' ){
			$jsonData = $base;
		} else {
			msgErr( __PACKAGE__."::var() expects base be a hash, found '$ref'" );
			return undef;
		}
	} else {
		$jsonData = $self->jsonData();
	}
	my $level = 0;
	my $value = $self->jsonVar_rec( $keys, $jsonData, $jsonData, $level );
	print STDERR __PACKAGE__."::var() (rec=$level) eventually returns ".Dumper( $value ) if $varDebug;
	return $value;
}

# keys is a scalar, or an array of scalars, or an array of arrays of scalars

sub jsonVar_rec {
	my ( $self, $keys, $base, $initialBase, $level ) = @_;
	print STDERR __PACKAGE__."::jsonVar_rec() entering (level=$level) with keys=".Dumper( $keys )." base=".Dumper( $base ) if $varDebug;
	my $ref = ref( $keys );
	if( $ref eq 'ARRAY' ){
EXT:	for( my $i=0 ; $i<scalar @{$keys} ; ++$i ){
			my $k = $keys->[$i];
			$ref = ref( $k );
			if( $ref eq 'ARRAY' ){
				my @newKeys = @{$keys};
				for( my $j=0 ; $j<scalar @{$k} ; ++$j ){
					$newKeys[$i] = $k->[$j];
					$base = $initialBase;
					$base = $self->jsonVar_rec( \@newKeys, $base, $initialBase, $level+1 );
					last EXT if defined( $base );
				}
				if( !defined( $base )){
					print STDERR __PACKAGE__."::jsonVar_rec() (level=$level) returns undef as no key has been found among [ ".join( ', ', @{$keys} )." ]".EOL if $varDebug;
				}
			} elsif( $ref ){
				msgErr( __PACKAGE__."::jsonVar_rec() unexpected intermediate ref='$ref'" );
			} else {
				print STDERR __PACKAGE__."::jsonVar_rec() (level=$level) will search for '$k' key in ".Dumper( $base ) if $varDebug;
				my $prevbase = $base;
				$base = $self->jsonVar_rec( $k, $base, $initialBase, $level+1 );
				if( !defined( $base )){
					print STDERR __PACKAGE__."::jsonVar_rec() (level=$level) returns undef as key='$k' has not been found in ".Dumper( $prevbase ) if $varDebug;
					last;
				}
			}
		}
	} elsif( $ref ){
		msgErr( __PACKAGE__."::jsonVar_rec() unexpected final ref='$ref'" );
		return undef;
	} else {
		# the key here may be empty when targeting the top of the hash, if so, then just return the hash
		print STDERR __PACKAGE__."::jsonVar_rec() (level=$level) searching for '$keys' key in ".Dumper( $base ) if $varDebug;
		if( $keys ){
			if( defined( $base )){
				if( ref( $base ) eq 'HASH' ){
					if( exists( $base->{$keys} )){
						$base = $base->{$keys};
					} else {
						$base = undef;
					}
				} else {
					$base = undef;
				}
			}
		}
	}
	print STDERR __PACKAGE__."::jsonVar_rec() (level=$level) returning ".Dumper( $base ) if $varDebug;
	return $base;
}

# -------------------------------------------------------------------------------------------------
# JSONable initialization
# Initialization of a command or of an external script
# (I):
# - the TTP EntryPoint ref
# (O):
# -none

after _newBase => sub {
	my ( $self, $ep ) = @_;

	$self->{_ijsonable} //= {};
	$self->{_ijsonable}{loadable} = false;
	$self->{_ijsonable}{json} = undef;
	$self->{_ijsonable}{loaded} = false;
};

### Global functions

1;

__END__
