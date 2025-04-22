# Copyright (@) 2023-2025 PWI Consulting
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

sub getConfigurationValue {
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
