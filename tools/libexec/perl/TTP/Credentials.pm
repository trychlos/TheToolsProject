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
# Credentials

package TTP::Credentials;

use strict;
use utf8;
use warnings;

use Data::Dumper;
use File::Spec;
use vars::global qw( $ep );

use TTP;
use TTP::Constants qw( :all );
use TTP::Finder;
use TTP::Message qw( :all );

my $Const = {
	# default subpaths to find the credentials files
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
	my $credentialsFinder = TTP::Credentials::finder();
	my $res = $finder->find({ dirs => [ $credentialsFinder->{dirs}, $file ]});
	return $res && ref( $res ) eq 'ARRAY' ? $res->[0] : undef;
}

# ------------------------------------------------------------------------------------------------
# Returns the full specifications to find the credentials configuration files
# It is dynamically updated with 'credentials.dirs' variable if any.
# (I):
# - none
# (O):
# - returns a ref to the finder, honoring 'credentials.dirs' variable if any

sub finder {
	my %finder = %{$Const->{finder}};
	my $dirs = $ep->var([ 'credentials', 'dirs' ]);
	if( !$dirs ){
		$dirs = $ep->var( 'credentialsDirs' );
		if( $dirs ){
			msgWarn( "'credentialsDirs' property is deprecated in favor of 'credentials.dirs'. You should update your configurations." );
		}
	}
	$finder{dirs} = $dirs if $dirs;

	return \%finder;
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
	my $credentialsFinder = TTP::Credentials::finder();
	return getWithFiles( $keys, $credentialsFinder->{files} );
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

		# first look in the TTP/host configurations
		$res = $ep->var( $keys );

		# prepare a finder for the credentials
		my $credentialsFinder = TTP::Credentials::finder();

		# if not found, looks at credentialsDirs/credentialsFiles
		if( !defined( $res )){
			if( $finder->jsonLoad({ findable => {
				dirs => [ $credentialsFinder->{dirs}, $credentialsFinder->{files} ],
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
				dirs => [ $credentialsFinder->{dirs}, "$node.json" ],
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
