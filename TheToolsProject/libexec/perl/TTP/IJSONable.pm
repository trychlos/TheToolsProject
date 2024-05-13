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
our $VERSION = '1.00';

use strict;
use warnings;

use Carp;
use Config;
use Data::Dumper;
use File::Spec;
use JSON;
use Test::Deep;
use Time::Piece;

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
# (O):
# - the evaluated hash object

sub _evaluate {
	my ( $self, $value ) = @_;
	my %prev = ();
	my $result = $self->_evaluateRec( $value );
	if( $result ){
		while( !eq_deeply( $result, \%prev )){
			%prev = %{$result};
			$result = $self->_evaluateRec( $result );
		}
	}
	return $result;
}

sub _evaluateRec {
	my ( $self, $value ) = @_;
	my $result = '';
	my $ref = ref( $value );
	if( !$ref ){
		$result = $self->_evaluateScalar( $value );
	} elsif( $ref eq 'ARRAY' ){
		$result = [];
		foreach my $it ( @{$value} ){
			push( @{$result}, $self->_evaluateRec( $it ));
		}
	} elsif( $ref eq 'HASH' ){
		$result = {};
		foreach my $key ( keys %{$value} ){
			$result->{$key} = $self->_evaluateRec( $value->{$key} );
		}
	} else {
		$result = $value;
	}
	return $result;
}

sub _evaluateScalar {
	my ( $self, $value ) = @_;
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
		$result =~ s/\[eval:($re)\]/$self->_evaluatePrint( $1 )/eg;
		$result =~ s/\[_eval:/[eval:/g;
		$result =~ s/\[__eval:/[_eval:/g;
		$result =~ s/\[___eval:/[__eval:/g;
		$result =~ s/\[____eval:/[___eval:/g;
		$result =~ s/\[_____eval:/[____eval:/g;
	}
	return $result;
}

sub _evaluatePrint {
	my ( $self, $value ) = @_;
	my $result = eval $value;
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
# (I]:
# - none
# (O):
# - this same object

sub evaluate {
	my ( $self ) = @_;

	$self->{_ijsonable}{evaluated} = $self->{_ijsonable}{raw};
	$self->{_ijsonable}{evaluated} = $self->_evaluate( $self->{_ijsonable}{raw} );

	return $self;
}

# -------------------------------------------------------------------------------------------------
# Returns the evaluated data
# (I]:
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
# (I]:
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
	#print Dumper( $args );

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
# (I]:
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
	#print __PACKAGE__."::var() self=$self keys=[".( ref( $keys ) ? join( ',', @{$keys} ) : $keys )."] ".( $base || '' ).EOL;
	my $jsonData = undef;
	my $value = undef;
	if( $base ){
		my $ref = ref( $base );
		if( $ref && $ref eq 'HASH' ){
			$jsonData = $base;
		} elsif( $ref ){
			msgErr( __PACKAGE__."::var() expects base be a hash or a scalar, found '$ref'" );
		} else {
			$value = $base;
		}
	} else {
		$jsonData = $self->jsonData();
	}
	$value = $self->jsonVar_rec( $keys, $jsonData ) if !defined $value && $jsonData;
	return $value;
}

# keys is a scalar, or an array of scalars, or an array of arrays of scalars

sub jsonVar_rec {
	my ( $self, $keys, $base, $startBase ) = @_;
	print __PACKAGE__."::jsonVar_rec() entering with keys='$keys' base='".( defined $base ? $base : '(undef)' )."'".EOL if $varDebug;
	return $base if !defined( $base ) || ref( $base ) ne 'HASH';
	$startBase = $startBase || $base;
	my $ref = ref( $keys );
	#print "keys=[".( ref( $keys ) eq 'ARRAY' ? join( ',', @{$keys} ) : $keys )."] base=$base".EOL;
	if( $ref eq 'ARRAY' ){
		for( my $i=0 ; $i<scalar @{$keys} ; ++$i ){
			my $k = $keys->[$i];
			$ref = ref( $k );
			if( $ref eq 'ARRAY' ){
				my @newKeys = @{$keys};
				for( my $j=0 ; $j<scalar @{$k} ; ++$j ){
					$newKeys[$i] = $k->[$j];
					$base = $startBase;
					$base = $self->jsonVar_rec( \@newKeys, $base, $startBase );
					last if defined( $base );
				}
			} elsif( $ref ){
				msgErr( __PACKAGE__."::jsonVar_rec() unexpected intermediate ref='$ref'" );
			} else {
				#print __PACKAGE__."::jsonVar_rec() searching for '$k' key in $base".EOL;
				$base = $self->jsonVar_rec( $k, $base, $startBase );
			}
		}
	} elsif( $ref ){
		msgErr( __PACKAGE__."::jsonVar_rec() unexpected final ref='$ref'" );
	} else {
		# the key here may be empty when targeting the top of the hash
		$base = $keys ? $base->{$keys} : $base;
		#print __PACKAGE__."::jsonVar_rec() keys='$keys' found '".( defined $base ? $base : '(undef)' )."'".EOL;
	}
	print __PACKAGE__."::jsonVar_rec() returning '".( defined $base ? $base : '(undef)' )."'".EOL if $varDebug;
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
