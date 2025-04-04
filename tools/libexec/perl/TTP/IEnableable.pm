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
# Enable a JSON file.
#
# Syntax:
#   "enabled": true|false
#
# Most of JSON configuration files can be enabled or disabled.
# The (hardcoded) default is to enable the configuration, and hence the underlying configured
# object.

package TTP::IEnableable;
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Data::Dumper;

use TTP::Constants qw( :all );
use TTP::Message qw( :all );

### https://metacpan.org/pod/Role::Tiny
### All subs created after importing Role::Tiny will be considered methods to be composed.
use Role::Tiny;

requires qw( _newBase );

# -------------------------------------------------------------------------------------------------
# Test for enable-ity
# Site, Node, Service and Daemon classes, which use JSON configuration  files, may choose to disable
# the instance in the JSON.
# This is checked here as a sub-component of file Acceptability.
# (I):
# - expects a scalar which is either the file path or the data content as a hash ref
# - expects an object which contains a 'type' key with 'JSON' value
# (O):
# - returns true|false

sub enabled {
	my ( $self, $obj, $opts ) = @_;
	$opts //= {};
	my $enabled = false;
	my $ref = ref( $obj );

	# if the object is a scalar, expects the opts specifies a type='JSON'
	if( !$ref ){
		if( $opts->{type} ){
			if( $opts->{type} eq 'JSON' ){
				$enabled = true;
				my $data = TTP::jsonRead( $obj );
				$enabled = $data->{enabled} if exists $data->{enabled};
			}
		}

	# else this a the data content as a hash ref
	} elsif( $ref eq 'HASH' ){
		$enabled = true;
		$enabled = $obj->{enabled} if exists $obj->{enabled};

	# else this is an unrecoverable error
	} else {
		msgErr( __PACKAGE__."::enabled() expects object be a hash reference or a scalar, found '$ref'" );
	}

	msgVerbose( __PACKAGE__.":enabled() returning '$enabled'" );
	return $enabled;
}

# -------------------------------------------------------------------------------------------------
# Enableable initialization
# (I):
# - none
# (O):
# -none

after _newBase => sub {
	my ( $self ) = @_;

	$self->{_ienableable} //= {};
	$self->{_ienableable}{enabled} = true;
};

1;

__END__
