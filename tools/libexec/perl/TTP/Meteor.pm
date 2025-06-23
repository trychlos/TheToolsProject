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
# A package dedicated to PostgreSQL

package TTP::Meteor;
die __PACKAGE__ . " must be loaded as TTP::Meteor\n" unless __PACKAGE__ eq 'TTP::Meteor';

use strict;
use utf8;
use warnings;

use Data::Dumper;
use File::Spec;
use JSON;
use Path::Tiny;

use TTP;
use TTP::Constants qw( :all );
use TTP::Message qw( :all );

my $Const = {
};

# ------------------------------------------------------------------------------------------------
# does the given directory host a Meteor application ?
# (I):
# - a directory path
# (O):
# - an application object with following keys:
#   > dir: the path to the application directory
#   > json: the path to the package.json file
#   > name: the name of the application
# - returns undef if not a Meteor application

sub getApplication {
	my ( $dir ) = @_;
	my $res = undef;

	if( -d $dir ){
		# must have a .meteor/ subdirectory
		my $meteor = File::Spec->catdir( $dir, '.meteor' );
		if( ! -d $meteor ){
			msgVerbose( "$meteor: directory not found or not available" );
			return undef;
		}
		# must have a package.json with 'name' and 'meteor' keys
		my $json = File::Spec->catfile( $dir, 'package.json' );
		if( -r $json ){
			my $content = decode_json( path( $json )->slurp_utf8 );
			# expect a non-empty 'name' value
			if( !$content->{name} ){
				msgVerbose( "$json: expects a 'name' key, not found" );
				return undef;
			}
			# expect a non-empty 'meteor' value
			if( !$content->{meteor} ){
				msgVerbose( "$json: expects a 'meteor' key, not found" );
				return undef;
			}
			$res = {
				dir => $dir,
				json => $json,
				name => $content->{name}
			};
		} else {
			msgVerbose( "$json: file not found or not readable" );
			return undef;
		}
	} else {
		msgVerbose( "$dir: not a directory" );
		return undef;
	}

	return $res;
}

1;

__END__
