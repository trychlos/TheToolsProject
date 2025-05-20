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
# MQTT management.

package TTP::MQTT;
die __PACKAGE__ . " must be loaded as TTP::MQTT\n" unless __PACKAGE__ eq 'TTP::MQTT';

use strict;
use utf8;
use warnings;

use Data::Dumper;
use Net::MQTT::Simple;

use TTP;
use vars::global qw( $ep );

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
		my $port = $ep->var([ 'MQTTGateway', 'port' ]);
		if( $port ){
			msgWarn( "'MQTTGateway.port' property is deprecated in favor of 'MQTTGateway.host'. You should update your configurations." );
			$broker = "$broker:$port";
		}
	}
	msgErr( __PACKAGE__."::connect() broker is not configured nor provided as an argument" ) if !$broker;

	my ( $account, $password ) = _getCredentials( $broker );
	my $wantsAccount = $ep->var([ 'MQTTGateway', 'wantsAccount' ]);
	$wantsAccount = true if !defined $wantsAccount;
	my $wantsPassword = $ep->var([ 'MQTTGateway', 'wantsPassword' ]);
	$wantsPassword = true if !defined $wantsPassword;
	if( $wantsAccount && !$account ){
		msgErr( __PACKAGE__."::connect() account not found while required by configuration" );
	}
	if( $wantsPassword && !$password ){
		msgErr( __PACKAGE__."::connect() password not found while required by the configuration" );
	}

	if( !TTP::errs()){
		$mqtt = Net::MQTT::Simple->new( $broker, $sockopts );
		if( $mqtt ){
			# define a last will if requested by the caller
			if( $args->{will} ){
				my $topic = $args->{will}{topic} || '';
				my $payload = $args->{will}{payload} || '';
				my $retain = false;
				$retain = $args->{will}{retain} if defined $args->{will}{retain};
				$mqtt->last_will( $topic, $payload, $retain );
				$mqtt->{ttpLastWill} = {
					topic => $topic,
					payload => $payload,
					retain => $retain
				}
			}
			# login
			my $logged = $mqtt->login( $account, $password );
			msgVerbose( __PACKAGE__."::connect() logged-in to '$broker' with '$logged' account" );
		} else {
			msgErr( __PACKAGE__."::connect() unable to instanciate a new connection against '".( $broker ? $broker : '(undef)' )."' broker" );
		}
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
			msgLog( __PACKAGE__."::disconnect() executing lastwill for the daemon" );
			if( $handle->{ttpLastWill}{retain} ){
				msgLog( __PACKAGE__."::disconnect() retain ".$handle->{ttpLastWill}{topic}." [".$handle->{ttpLastWill}{payload}."]" );
				$handle->retain( $handle->{ttpLastWill}{topic}, $handle->{ttpLastWill}{payload} );
			} else {
				msgLog( __PACKAGE__."::disconnect() publish ".$handle->{ttpLastWill}{topic}." [".$handle->{ttpLastWill}{payload}."]" );
				$handle->publish( $handle->{ttpLastWill}{topic}, $handle->{ttpLastWill}{payload} );
			}
		}
		msgVerbose( __PACKAGE__."::disconnect()" );
		$handle->disconnect();
	} else {
		msgErr( __PACKAGE__."::disconnect() undefined connection handle" );
		TTP::stackTrace();
	}
}

# ------------------------------------------------------------------------------------------------
# returns the first account defined for this MQTT service
# (I):
# - the host gateway as defined in the site.json
# - an optional account, defaulting to the first one found
# (O):
# - an array ( username, password )

sub _getCredentials {
	my ( $host, $account ) = @_;

	my $credentials = TTP::Credentials::get([ 'MQTTGateway', $host ]);
	my $passwd = undef;

	if( $credentials ){
		$account = ( keys %{$credentials} )[0] if !$account;
		$passwd = $credentials->{$account} || undef;
		msgVerbose( __PACKAGE__."::_getCredentials() got account='".( $account || '(undef)' )."'" );

	} else {
		msgErr( __PACKAGE__."::_getCredentials() unable to get credentials for host='$host', account=".( $account ? "'$account'" : '(undef)' ));
	}

	return ( $account, $passwd );
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
		msgVerbose( __PACKAGE__."::keepalive() setting KEEPALIVE_INTERVAL='$interval'" );
	} else {
		msgErr( __PACKAGE__."::keepalive() undefined connection handle" );
		TTP::stackTrace();
	}
}

1;
