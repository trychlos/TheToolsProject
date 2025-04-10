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
# MQTT management.

package TTP::MQTT;

use strict;
use utf8;
use warnings;

use Data::Dumper;
use Net::MQTT::Simple;
use vars::global qw( $ep );

use TTP;
use TTP::Constants qw( :all );
use TTP::Credentials;
use TTP::Message qw( :all );

$ENV{MQTT_SIMPLE_ALLOW_INSECURE_LOGIN} = 1;

# ------------------------------------------------------------------------------------------------
# connect to the configured MQTT broker, keeping the connection alive (doesn't disconnect)
# (I):
# - a hash ref with following keys:
#   > broker: the full broker address, defaulting to global/host configured
#   > username: the connection username, defaulting to global/host configured
#   > password: the connection password, defaulting to global/host configured
#   > will: an optional last will, as a hash with following keys:
#     - topic, defaulting to empty
#     - payload, defaulting to empty
#     - retain, defaulting to false
# - an optional hash which will be passed to underlying IO::Socket::IP package
# (O):
# - an opaque connection handle to be used when publishing (and disconnecting)

sub connect {
	my ( $args, $sockopts ) = @_;
	my $mqtt = undef;
	$sockopts //= {};

	my $broker = $args->{broker};
	if( !$broker ){
		$broker = $ep->var([ 'MQTTGateway', 'host' ]);
		if( !$broker ){
			$broker = $ep->var([ 'MQTTGateway', 'broker' ]);
			if( $broker ){
				msgWarn( "'MQTTGateway.broker' property is deprecated in favor of 'MQTTGateway.host'. You should update your configurations." );
			}
		}
	}
	msgErr( "MQTT::connect() broker is not configured nor provided as an argument" ) if !$broker;

	my $username = TTP::Credentials::get([ 'MQTTGateway', 'username' ]);
	$username = $args->{username} if $args->{username};
	msgErr( "MQTT::connect() username is not configured nor provided as an argument" ) if !$username;

	my $password = TTP::Credentials::get([ 'MQTTGateway', 'password' ]);
	$password = $args->{password} if $args->{password};
	msgErr( "MQTT::connect() password is not configured nor provided as an argument" ) if !$password;

	$mqtt = Net::MQTT::Simple->new( $broker, $sockopts ) if $broker;
	if( $mqtt ){
		# define a last will if requested by the caller
		if( $args->{will} ){
			my $topic = $args->{will}{topic} || '';
			my $payload = $args->{will}{payload} || '';
			my $retain = false;
			$retain = $args->{will}{retain} if exists $args->{will}{retain};
			$mqtt->last_will( $topic, $payload, $retain );
			$mqtt->{ttpLastWill} = {
				topic => $topic,
				payload => $payload,
				retain => $retain
			}
		}
		# login
		my $logged = $mqtt->login( $username, $password );
		msgVerbose( "MQTT::connect() logged-in with '$logged' account" );
	} else {
		msgErr( "MQTT::connect() unable to instanciate a new connection against '".( $broker ? $broker : '(undef)' )."' broker" );
	}
	
	return $mqtt;
}

# ------------------------------------------------------------------------------------------------
# disconnect from the specified MQTT broker
# (I):
# - opaque connection handle as returned from MQTT::connect()

sub disconnect {
	my ( $handle ) = @_;
	if( $handle ){
		if( $handle->{ttpLastWill} ){
			msgLog( "executing lastwill for the daemon" );
			if( $handle->{ttpLastWill}{retain} ){
				msgLog( "retain ".$handle->{ttpLastWill}{topic}." [".$handle->{ttpLastWill}{payload}."]" );
				$handle->retain( $handle->{ttpLastWill}{topic}, $handle->{ttpLastWill}{payload} );
			} else {
				msgLog( "publish ".$handle->{ttpLastWill}{topic}." [".$handle->{ttpLastWill}{payload}."]" );
				$handle->publish( $handle->{ttpLastWill}{topic}, $handle->{ttpLastWill}{payload} );
			}
		}
		msgVerbose( "MQTT::disconnect()" );
		$handle->disconnect();
	} else {
		msgErr( "MQTT::disconnect() undefined connection handle" );
		TTP::stackTrace();
	}
}

# ------------------------------------------------------------------------------------------------
# set the 'keepalive' interval
# (I):
# - opaque connection handle as returned from MQTT::connect()
# - keepalive interval in sec.

sub keepalive {
	my ( $handle, $interval ) = @_;
	if( $handle ){
		$Net::MQTT::Simple::KEEPALIVE_INTERVAL = $interval;
		msgVerbose( "setting KEEPALIVE_INTERVAL='$interval'" );
	} else {
		msgErr( "MQTT::keepalive() undefined connection handle" );
		TTP::stackTrace();
	}
}

1;
