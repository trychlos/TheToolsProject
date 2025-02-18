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
# The Tools Project: a Tools System and Paradigm for IT Production
# Copyright (©) 1998-2023 Pierre Wieser (see AUTHORS)
# Copyright (©) 2023-2024 PWI Consulting
#
# The Tools Project is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version.
#
# The Tools Project is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with The Tools Project; see the file COPYING. If not,
# see <http://www.gnu.org/licenses/>.

use utf8;
use strict;
use warnings;

use TTP::Metric;
my $running = $ep->runner();

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	metric => '',
	value => '',
	description => '',
	type => 'untyped',
	mqtt => 'no',
	mqttPrefix => '',
	http => 'no',
	httpPrefix => '',
	text => 'no',
	textPrefix => '',
	prepend => '',
	append => ''
};

my $opt_metric = $defaults->{metric};
my $opt_value = undef;
my $opt_description = $defaults->{description};
my $opt_type = $defaults->{type};
my $opt_mqtt = TTP::var([ 'Telemetry', 'withMqtt', 'enabled' ]);
my $opt_mqttPrefix = $defaults->{mqttPrefix};
my $opt_http = TTP::var([ 'Telemetry', 'withHttp', 'enabled' ]);
my $opt_httpPrefix = $defaults->{httpPrefix};
my $opt_text = TTP::var([ 'Telemetry', 'withText', 'enabled' ]);
my $opt_textPrefix = $defaults->{textPrefix};
my @opt_prepends = ();
my @opt_appends = ();

$defaults->{mqtt} = $opt_mqtt ? 'yes' : 'no';
$defaults->{http} = $opt_http ? 'yes' : 'no';
$defaults->{text} = $opt_text ? 'yes' : 'no';

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
	"help!"				=> \$ep->{run}{help},
	"colored!"			=> \$ep->{run}{colored},
	"dummy!"			=> \$ep->{run}{dummy},
	"verbose!"			=> \$ep->{run}{verbose},
	"metric=s"			=> \$opt_metric,
	"value=s"			=> \$opt_value,
	"description=s"		=> \$opt_description,
	"type=s"			=> \$opt_type,
	"mqtt!"				=> \$opt_mqtt,
	"mqttPrefix=s"		=> \$opt_mqttPrefix,
	"http!"				=> \$opt_http,
	"httpPrefix=s"		=> \$opt_httpPrefix,
	"text!"				=> \$opt_text,
	"textPrefix=s"		=> \$opt_textPrefix,
	"prepend=s@"		=> \@opt_prepends,
	"append=s@"			=> \@opt_appends )){

		msgOut( "try '".$running->command()." ".$running->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $running->help()){
	$running->verbHelp( $defaults );
	TTP::exit();
}

msgVerbose( "got colored='".( $running->colored() ? 'true':'false' )."'" );
msgVerbose( "got dummy='".( $running->dummy() ? 'true':'false' )."'" );
msgVerbose( "got verbose='".( $running->verbose() ? 'true':'false' )."'" );
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
msgWarn( "do not publish anything as neither '--mqtt', '--http' nor '--text' are set" ) if !$opt_mqtt && !$opt_http && !$opt_text;

if( !TTP::errs()){
	doPublish() if $opt_mqtt || $opt_http || $opt_text;
}

TTP::exit();
