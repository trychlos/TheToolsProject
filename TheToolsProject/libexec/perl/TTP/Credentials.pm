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
# Credentials

package TTP::Credentials;

use utf8;
use strict;
use warnings;

use Data::Dumper;
use File::Spec;
use vars::global qw( $ep );

use TTP;
use TTP::Constants qw( :all );
use TTP::Finder;
use TTP::Message qw( :all );

my $Const = {
	# hardcoded subpaths to find the <service>.json files
	# even if this not too sexy in Win32, this is a standard and a common usage on Unix/Darwin platforms
	finder => {
		dirs => [
			'etc/credentials',
			'credentials',
			'etc/private',
			'private'
		],
		files => [
			'toops.json',
			'site.json',
			'ttp.json'
		]
	}
};

# ------------------------------------------------------------------------------------------------
# Returns the first found file in credentials directories
# (I):
# - the file specs to be searched for
# (O):
# - the object found at the given address, or undef

sub find {
	my ( $file ) = @_;
	my $finder = TTP::Finder->new( $ep );
	my $res = $finder->find({ dirs => [ $Const->{finder}{dirs}, $file ]});
	return $res && ref( $res ) eq 'ARRAY' ? $res->[0] : undef;
}

# ------------------------------------------------------------------------------------------------
# Returns the found credentials
# Note that we first search in toops/host configuration, and then in a dedicated credentials JSON file with the same key
# (I):
# - an array ref of the keys to be read
# (O):
# - the object found at the given address, or undef

sub get {
	my ( $keys ) = @_;
	return getWithFiles( $keys, $Const->{finder}{files} );
}

# ------------------------------------------------------------------------------------------------
# Returns the found credentials
# Note that we first search in toops/host configuration, and then in a dedicated credentials JSON file with the same key
# (I):
# - an array ref of the keys to be read
# - an array ref of the files to be searched for
# (O):
# - the object found at the given address, or undef

sub getWithFiles {
	my ( $keys, $files ) = @_;
	my $res = undef;
	if( ref( $keys ) ne 'ARRAY' ){
		msgErr( __PACKAGE__."::get() expects an array, found '".ref( $keys )."'" );
	} else {
		my $finder = TTP::Finder->new( $ep );

		# first look in the Toops/host configurations
		$res = $ep->var( $keys );

		# if not found, looks at credentialsDirs/credentialsFiles
		if( !defined( $res )){
			if( $finder->jsonLoad({ findable => {
				dirs => [ $Const->{finder}{dirs}, $Const->{finder}{files} ],
				wantsAll => false
			}})){
				$finder->evaluate();
				$res = $ep->var( $keys, { jsonable => $finder });
			}
		}
		# if not found, looks at credentials/<host>.json
		if( !defined( $res )){
			my $node = $ep->node()->name();
			if( $finder->jsonLoad({ findable => {
				dirs => [ $Const->{finder}{dirs}, "$node.json" ],
				wantsAll => false
			}})){
				$finder->evaluate();
				$res = $ep->var( $keys, { jsonable => $finder });
			}
		}
	}
	return $res;
}

1;
