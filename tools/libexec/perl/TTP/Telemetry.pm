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

# -------------------------------------------------------------------------------------------------
# Whether the HTTP-based telemetry is enabled in this site
# (I):
# - none
# (O):
# - true|false

sub isHttpEnabled {
	my $enabled = getConfigurationValue([ 'withHttp', 'enabled' ]);
	$enabled = true if !defined $enabled;
	return $enabled;
}

# -------------------------------------------------------------------------------------------------
# Whether the MQTT-based telemetry is enabled in this site
# (I):
# - none
# (O):
# - true|false

sub isMqttEnabled {
	my $enabled = getConfigurationValue([ 'withMqtt', 'enabled' ]);
	$enabled = true if !defined $enabled;
	return $enabled;
}

# -------------------------------------------------------------------------------------------------
# Whether the text-based telemetry is enabled in this site
# (I):
# - none
# (O):
# - true|false

sub isTextEnabled {
	my $enabled = getConfigurationValue([ 'withText', 'enabled' ]);
	$enabled = true if !defined $enabled;
	return $enabled;
}

1;
