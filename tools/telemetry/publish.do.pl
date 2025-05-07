# @(#) publish a metric
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --metric=<name>         the metric to be published [${metric}]
# @(-) --value=<value>         the metric's value [${value}]
# @(-) --description=<string>  a one-line help description [${description}]
# @(-) --type=<type>           the metric type [${type}]
# @(-) --[no]mqtt              publish the metrics to the (MQTT-based) messaging system [${mqtt}]
# @(-) --mqttPrefix=<prefix>   prefix the metric name when publishing to the (MQTT-based) messaging system [${mqttPrefix}]
# @(-) --[no]http              publish the metrics to the (HTTP-based) Prometheus PushGateway system [${http}]
# @(-) --httpPrefix=<prefix>   prefix the metric name when publishing to the (HTTP-based) Prometheus PushGateway system [${httpPrefix}]
# @(-) --[no]text              publish the metrics to the (text-based) Prometheus TextFile Collector system [${text}]
# @(-) --textPrefix=<prefix>   prefix the metric name when publishing to the (text-based) Prometheus TextFile Collector system [${textPrefix}]
# @(-) --prepend=<name=value>  label to be appended to the telemetry metrics, may be specified several times or as a comma-separated list [${prepend}]
# @(-) --append=<name=value>   label to be appended to the telemetry metrics, may be specified several times or as a comma-separated list [${append}]
#
# @(@) This verb let you publish a metric to any enabled medium, among (MQTT-based) messaging system, or (http-based) Prometheus PushGateway or
# @(@) (text-based) Prometheus TextFile Collector.
#
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

use strict;
use utf8;
use warnings;

use TTP::Metric;
use TTP::Telemetry;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	metric => '',
	value => '',
	description => '',
	type => 'untyped',
	mqttPrefix => '',
	httpPrefix => '',
	textPrefix => '',
	prepend => '',
	append => ''
};

my $opt_metric = $defaults->{metric};
my $opt_value = undef;
my $opt_description = $defaults->{description};
my $opt_type = $defaults->{type};
my $opt_mqttPrefix = $defaults->{mqttPrefix};
my $opt_httpPrefix = $defaults->{httpPrefix};
my $opt_textPrefix = $defaults->{textPrefix};
my @opt_prepends = ();
my @opt_appends = ();

my $opt_mqtt = TTP::Telemetry::getConfigurationValue([ 'withMqtt', 'default' ]);
$opt_mqtt = false if !defined $opt_mqtt;
$defaults->{mqtt} = $opt_mqtt ? 'yes' : 'no';
my $opt_mqtt_set = false;

my $opt_http = TTP::Telemetry::getConfigurationValue([ 'withHttp', 'default' ]);
$opt_http = false if !defined $opt_http;
$defaults->{http} = $opt_http ? 'yes' : 'no';
my $opt_http_set = false;

my $opt_text = TTP::Telemetry::getConfigurationValue([ 'withText', 'default' ]);
$opt_text = false if !defined $opt_text;
$defaults->{text} = $opt_text ? 'yes' : 'no';
my $opt_text_set = false;

# -------------------------------------------------------------------------------------------------
# create and publish the desired metric

sub doPublish {
	msgOut( "publishing '$opt_metric' metric..." );
	my $metric = {
		name => $opt_metric,
		value => $opt_value
	};
	$metric->{help} = $opt_description if $opt_description;
	$metric->{type} = $opt_type if $opt_type;
	my @labels = ( @opt_prepends, @opt_appends );
	$metric->{labels} = \@labels if scalar @labels;
	TTP::Metric->new( $ep, $metric )->publish({
		mqtt => $opt_mqtt,
		mqttPrefix => $opt_mqttPrefix,
		http => $opt_http,
		httpPrefix => $opt_httpPrefix,
		text => $opt_text,
		textPrefix => $opt_textPrefix
	});
	if( TTP::errs()){
		msgErr( "NOT OK", { incErr => false });
	} else {
		msgOut( "done" );
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> sub { $ep->runner()->help( @_ ); },
	"colored!"			=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"			=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"			=> sub { $ep->runner()->verbose( @_ ); },
	"metric=s"			=> \$opt_metric,
	"value=s"			=> \$opt_value,
	"description=s"		=> \$opt_description,
	"type=s"			=> \$opt_type,
	"mqtt!"				=> sub {
		my ( $name, $value ) = @_;
		$opt_mqtt = $value;
		$opt_mqtt_set = true;
	},
	"mqttPrefix=s"		=> \$opt_mqttPrefix,
	"http!"				=> sub {
		my ( $name, $value ) = @_;
		$opt_http = $value;
		$opt_http_set = true;
	},
	"httpPrefix=s"		=> \$opt_httpPrefix,
	"text!"				=> sub {
		my ( $name, $value ) = @_;
		$opt_text = $value;
		$opt_text_set = true;
	},
	"textPrefix=s"		=> \$opt_textPrefix,
	"prepend=s@"		=> \@opt_prepends,
	"append=s@"			=> \@opt_appends )){

		msgOut( "try '".$ep->runner()->command()." ".$ep->runner()->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $ep->runner()->help()){
	$ep->runner()->displayHelp( $defaults );
	TTP::exit();
}

msgVerbose( "got colored='".( $ep->runner()->colored() ? 'true':'false' )."'" );
msgVerbose( "got dummy='".( $ep->runner()->dummy() ? 'true':'false' )."'" );
msgVerbose( "got verbose='".( $ep->runner()->verbose() ? 'true':'false' )."'" );
msgVerbose( "got metric='$opt_metric'" );
msgVerbose( "got value='".( defined $opt_value ? $opt_value : '(undef)' )."'" );
msgVerbose( "got description='$opt_description'" );
msgVerbose( "got type='$opt_type'" );
msgVerbose( "got mqtt='".( $opt_mqtt ? 'true':'false' )."'" );
msgVerbose( "got mqttPrefix='$opt_mqttPrefix'" );
msgVerbose( "got http='".( $opt_http ? 'true':'false' )."'" );
msgVerbose( "got httpPrefix='$opt_httpPrefix'" );
msgVerbose( "got text='".( $opt_text ? 'true':'false' )."'" );
msgVerbose( "got textPrefix='$opt_textPrefix'" );
@opt_prepends = split( /,/, join( ',', @opt_prepends ));
msgVerbose( "got prepends='".join( ',', @opt_prepends )."'" );
@opt_appends = split( /,/, join( ',', @opt_appends ));
msgVerbose( "got appends='".join( ',', @opt_appends )."'" );

# metric and values are mandatory
msgErr( "'--metric' option is required, but is not specified" ) if !$opt_metric;
msgErr( "'--value' option is required, but is not specified" ) if !defined $opt_value;

# disabled media are just ignored (or refused if option was explicit)
if( $opt_mqtt ){
	my $enabled = TTP::Telemetry::getConfigurationValue([ 'withMqtt', 'enabled' ]);
	$enabled = true if !defined $enabled;
	if( !$enabled ){
		if( $opt_mqtt_set ){
			msgErr( "MQTT telemetry is disabled, --mqtt option is not valid" );
		} else {
			msgWarn( "MQTT telemetry is disabled and thus ignored" );
			$opt_mqtt = false;
		}
	}
}
if( $opt_http ){
	my $enabled = TTP::Telemetry::getConfigurationValue([ 'withHttp', 'enabled' ]);
	$enabled = true if !defined $enabled;
	if( !$enabled ){
		if( $opt_http_set ){
			msgErr( "HTTP PushGateway telemetry is disabled, --http option is not valid" );
		} else {
			msgWarn( "HTTP PushGateway telemetry is disabled and thus ignored" );
			$opt_http = false;
		}
	}
}
if( $opt_text ){
	my $enabled = TTP::Telemetry::getConfigurationValue([ 'withText', 'enabled' ]);
	$enabled = true if !defined $enabled;
	if( !$enabled ){
		if( $opt_text_set ){
			msgErr( "TextFile Collector telemetry is disabled, --text option is not valid" );
		} else {
			msgWarn( "TextFile Collector telemetry is disabled and thus ignored" );
			$opt_text = false;
		}
	}
}

# if labels are specified, check that each one is of the 'name=value' form
foreach my $label ( @opt_prepends ){
	my @words = split( /=/, $label );
	if( scalar @words != 2 || !$words[0] || !$words[1] ){
		msgErr( "label '$label' doesn't appear of the 'name=value' form" );
	}
}
foreach my $label ( @opt_appends ){
	my @words = split( /=/, $label );
	if( scalar @words != 2 || !$words[0] || !$words[1] ){
		msgErr( "label '$label' doesn't appear of the 'name=value' form" );
	}
}

msgWarn( "at least one of '--mqtt', '--http' or '--text' options should be specified" ) if !$opt_mqtt && !$opt_http && !$opt_text;

if( !TTP::errs()){
	doPublish() if $opt_mqtt || $opt_http || $opt_text;
}

TTP::exit();
