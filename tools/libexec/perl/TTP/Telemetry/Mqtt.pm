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
# MQTT-based telemetry.

package TTP::Telemetry::Mqtt;
die __PACKAGE__ . " must be loaded as TTP::Telemetry::Mqtt\n" unless __PACKAGE__ eq 'TTP::Telemetry::Mqtt';

use strict;
use utf8;
use warnings;

use Data::Dumper;

use TTP;
use TTP::Constants qw( :all );
use TTP::Message qw( :all );
use TTP::Telemetry;

use constant {
	# the publication error codes
	MQTT_DISABLED_BY_CONFIGURATION => 1,
	MQTT_COMMAND_ERROR => 2
};

my $Const = {
	# the error codes as labels
	errorLabels => [
		'OK',
		'MQTT_DISABLED_BY_CONFIGURATION',
		'MQTT_COMMAND_ERROR'
	]
};

# -------------------------------------------------------------------------------------------------
# Determines if MQTT-based telemetry is a site default, defaulting to false
# (I):
# - none
# (O):
# - whether MQTT-based telemetry is a default of the site

sub getDefault {
	my ( $class ) = @_;

	my $default = TTP::Telemetry::var([ 'withMqtt', 'default' ]);
	$default = false if !defined $default;

	return $default;
}

# -------------------------------------------------------------------------------------------------
# Whether MQTT-based telemetry is allowed in the site, defaulting to true
# (I):
# - none
# (O):
# - whether MQTT-based telemetry is allowed in the site

sub isEnabled {
	my ( $class ) = @_;

	my $enabled = TTP::Telemetry::var([ 'withMqtt', 'enabled' ]);
	$enabled = true if !defined $enabled;

	return $enabled;
}

# -------------------------------------------------------------------------------------------------
# publish a metric to MQTT bus
# unless otherwise specified, topic defaults to be NODE/telemetry/<label_values>/metric
# (I):
# - the metric
# - an optional options hash with following keys:
#   > prefix: a prefix to the metric name, defaulting to none
# (O):
# - returns either zero if the metric has been actually and successfully published, or the reason code

sub publish {
	my ( $metric, $opts ) = @_;
	$opts //= {};
	my $res = 0;

	if( isEnabled()){
		# get the command
		my $commands = TTP::commandByOS([ 'telemetry', 'withMqtt' ]);
		if( !$commands || !scalar( @{$commands} )){
			$commands = TTP::commandByOS([ 'Telemetry', 'withMqtt' ]);
			if( $commands && scalar( @{$commands} )){
				msgWarn( "'Telemetry' property is deprecated is favor of 'telemetry'. You should update your configurations" );
			} else {
				$commands = [ "mqtt.pl publish -topic <TOPIC> -payload \"<VALUE>\"" ];
			}
		}
		# get and maybe prefix the name
		my $name = $metric->name();
		my $prefix = $opts->{prefix};
		if( $prefix ){
			$name = "$prefix$name";
		}
		# build the topic
		my $topic = TTP::Telemetry::var([ 'withMqtt', 'topic' ]);
		if( !$topic ){
			$topic = "<NODE>/telemetry/<LABEL_VALUES>/<NAME>";
		}
		# when substituting the macros to build the topic, replace commas (',') with slashes ('/')
		# making sure we do not have any empty level (thus replacing all '//' with single '/')
		my $macros = $metric->macros();
		$macros->{NAME} = $name;
		$topic = TTP::substituteMacros( $topic, $macros );
		$topic =~ s/,/\//g;
		$topic =~ s/\/+/\//g;
		$macros->{TOPIC} = $topic;
		# when running the command, takes care that the provided command may not honor nor even accept standard options - do not modify it
		foreach my $cmd ( @{$commands} ){
			my $result = TTP::commandExec( $cmd, {
				macros => $macros
			});
			$res = $result->{success} ? 0 : MQTT_COMMAND_ERROR if !$res;
		}
	} else {
		$res = MQTT_DISABLED_BY_CONFIGURATION;
	}

	msgVerbose( __PACKAGE__."::publish() returning res='$res' ($Const->{errorLabels}[$res])" );
	return $res;
}

1;

__END__
