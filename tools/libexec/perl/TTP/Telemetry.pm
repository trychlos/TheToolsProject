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
# Telemetry management.

package TTP::Telemetry;
die __PACKAGE__ . " must be loaded as TTP::Telemetry\n" unless __PACKAGE__ eq 'TTP::Telemetry';

use strict;
use utf8;
use warnings;

use Data::Dumper;

use TTP;
use TTP::Constants qw( :all );
use TTP::Message qw( :all );

# -------------------------------------------------------------------------------------------------
# get a configuration value
# emitting a warning when the key is found under (deprecated) 'Telemetry'
# (I):
# - the list of searched keys as an array ref, e.g. [ 'withMqtt', 'enabled' ]
# (O):
# - the found value or undef

sub var {
	my ( $keys ) = @_;
	my @newKeys = @{$keys};
	unshift( @newKeys, 'telemetry' );
	my $value = TTP::var( \@newKeys );
	if( !defined( $value )){
		@newKeys = @{$keys};
		unshift( @newKeys, 'Telemetry' );
		$value = TTP::var( \@newKeys );
		if( defined( $value )){
			msgWarn( "'Telemetry' property is deprecated in favor of 'telemetry'. You should update your configurations." );
		}
	}
	return $value;
}

1;
