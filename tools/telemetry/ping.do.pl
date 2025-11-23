# @(#) ping a device and publish the telemetry
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --device=<name>         the device to be pinged [${device}]
# @(-) --metric=<name>         the metric to be published [${metric}]
# @(-) --description=<string>  a one-line help description [${description}]
# @(-) --type=<type>           the metric type [${type}]
# @(-) --[no]mqtt              publish the metrics to the (MQTT-based) messaging system [${mqtt}]
# @(-) --mqttPrefix=<prefix>   prefix the metric name when publishing to the (MQTT-based) messaging system [${mqttPrefix}]
# @(-) --[no]http              publish the metrics to the (HTTP-based) Prometheus PushGateway system [${http}]
# @(-) --httpPrefix=<prefix>   prefix the metric name when publishing to the (HTTP-based) Prometheus PushGateway system [${httpPrefix}]
# @(-) --[no]text              publish the metrics to the (text-based) Prometheus TextFile Collector system [${text}]
# @(-) --textPrefix=<prefix>   prefix the metric name when publishing to the (text-based) Prometheus TextFile Collector system [${textPrefix}]
# @(-) --prepend=<name=value>  label to be prepended to the telemetry metrics, may be specified several times or as a comma-separated list [${prepend}]
# @(-) --append=<name=value>   label to be appended to the telemetry metrics, may be specified several times or as a comma-separated list [${append}]
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

use Data::Dumper;
use File::Spec;
use Path::Tiny qw( path );

use TTP::Metric;
use TTP::Telemetry::Http;
use TTP::Telemetry::Mqtt;
use TTP::Telemetry::Text;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	device => '',
	metric => '',
	description => '',
	type => 'untyped',
	mqttPrefix => '',
	httpPrefix => '',
	textPrefix => '',
	prepend => '',
	append => ''
};

my $opt_device = $defaults->{device};
my $opt_metric = $defaults->{metric};
my $opt_description = $defaults->{description};
my $opt_type = $defaults->{type};
my $opt_mqttPrefix = $defaults->{mqttPrefix};
my $opt_httpPrefix = $defaults->{httpPrefix};
my $opt_textPrefix = $defaults->{textPrefix};
my @opt_prepends = ();
my @opt_appends = ();

my $opt_mqtt = TTP::Telemetry::Mqtt::getDefault();
$defaults->{mqtt} = $opt_mqtt ? 'yes' : 'no';
my $opt_mqtt_set = false;

my $opt_http = TTP::Telemetry::Http::getDefault();
$defaults->{http} = $opt_http ? 'yes' : 'no';
my $opt_http_set = false;

my $opt_text = TTP::Telemetry::Text::getDefault();
$defaults->{text} = $opt_text ? 'yes' : 'no';
my $opt_text_set = false;

# some default constants
my $Const = {
	errors => {
		threshold => 2
	},
	latency => {
		threshold => 1000
	}
};

# -------------------------------------------------------------------------------------------------
# Giving the output of the publication, manage the alert
# Alert media are not overridable on the command-line

sub alert {
	my ( $res, $which ) = @_;

	# do we have alerts ?
	my $enabled = TTP::Telemetry::var([ 'ping', $which, 'alert', 'enabled' ]) // true;
	if( $enabled ){
		my $threshold = TTP::Telemetry::var([ 'ping', $which, 'alert', 'threshold' ]) // $Const->{$which}{threshold};
		if( $res->{value} > $threshold ){
			my $media = TTP::Telemetry::var([ 'ping', $which, 'alert', 'media' ]) // 'all';
			$media = [ $media ] if ref( $media ) ne 'ARRAY';
			my $mms = grep( /mms|all/i, @{$media} ) ? "--mms" : "";
			my $mqtt = grep( /mqtt|all/i, @{$media} ) ? "--mqtt" : "";
			my $sms = grep( /sms|all/i, @{$media} ) ? "--sms" : "";
			my $smtp = grep( /smtp|all/i, @{$media} ) ? "--smtp" : "";
			my $tts = grep( /tts|all/i, @{$media} ) ? "--tts" : "";
			my $title = $which eq "errors" ? "$opt_device doesn't answer to ping (errors count=$res->{value})" : "$opt_device exhibits high $res->{value} ms latency";
			my $command = "ttp.pl alert -title $title $mms $mqtt $sms $smtp $tts";
			TTP::commandExec( $command );
		} else {
			msgVerbose( "value='$res->{value}' less than threshold='$threshold', do not alert" );
		}
	} else {
		msgVerbose( "$which alert is disabled by configuration" );
	}
}

# -------------------------------------------------------------------------------------------------
# create and publish the desired metric

sub doPing {
	msgOut( "pinging '$opt_device' device..." );

	my $result = TTP::commandExec( "ping -c1 $opt_device" );

	#print "result ". Dumper( $result );
	#$result->{success} = false;

	# we only have a latency when success
	if( $result->{success} ){
		my $res = latency_publish( $result );
		latency_alert( $res );
	}

	# but always have to manage an errors count
	my $res = errors_publish( $result );
	errors_alert( $res );

	if( TTP::errs()){
		msgErr( "NOT OK", { incErr => false });
	} else {
		msgOut( "done" );
	}
}

# -------------------------------------------------------------------------------------------------
# Giving the output of the publication, manage the errors count alert

sub errors_alert {
	my ( $res ) = @_;
	alert( $res, "errors" );
}

# -------------------------------------------------------------------------------------------------
# Giving the result of the 'ping' command, maybe publish the errors count
# Returns enough to manage the alert, i.e. a hash with following keys:
# - value: the errors count value
# - dropDir: the drop directory for Text telemetry
# NB: the last errors count for the device is stored as a particular file in the Text drop directory

sub errors_publish {
	my ( $res ) = @_;
	my $out = {
		dropDir => TTP::Telemetry::Text::dropDir()
	};

	# first get the previous errors count
	my $qualifiers = $ep->runner()->runnableQualifiers();
	shift @{$qualifiers};
	my $fname = File::Spec->catfile( $out->{dropDir}, sprintf( "%s_%s_%s.errors_count", $ep->runner()->runnableBNameShort(), join( '_', @{$qualifiers} ), $opt_device ));
	if( -r $fname ){
		$out->{value} = path( $fname )->slurp_utf8 || 0;
	} else {
		$out->{value} = 0;
	}
	# increment on error, or reset on success
	if( $res->{success} ){
		$out->{value} = 0;
	} else {
		$out->{value} += 1;
	}
	# and write
	path( $fname )->spew_utf8([ $out->{value} ]);

	# and then see if we want publish
	publish_metric( "errors", $out->{value} );

	return $out;
}

# -------------------------------------------------------------------------------------------------
# Giving the output of the publication, manage the latency alert

sub latency_alert {
	my ( $res ) = @_;
	alert( $res, "latency" );
}

# -------------------------------------------------------------------------------------------------
# Giving the result of the 'ping' command, maybe publish the latency
# Returns enough to manage the alert, i.e. a hash with following keys:
# - value: the latency value

sub latency_publish {
	my ( $res ) = @_;
	my $out = { value => undef };

	# grep and interpret the 'rtt min/avg/max/mdev = 66.384/66.384/66.384/0.000 ms' line
	my @lines = grep( /rtt min/, @{$res->{stdouts}} );
	my @words = split( /\s+/, $lines[0] // '' );
	my @measures = split( /\//, $words[3] // '' );
	$out->{value} = $measures[0] // -1;

	# and then see if we want publish
	publish_metric( "latency", $out->{value} );

	return $out;
}

# -------------------------------------------------------------------------------------------------
# Publish a metric
# (I):
# - the concerned metric ('errors' or 'latency')
# - the to-be-published value

sub publish_metric {
	my ( $which, $value ) = @_;

	my $enabled = TTP::Telemetry::var([ 'ping', $which, 'publish', 'enabled' ]) // true;
	if( $enabled ){
		my $media = TTP::Telemetry::var([ 'ping', $which, 'publish', 'media' ]) // 'all';
		$media = [ $media ] if ref( $media ) ne 'ARRAY';
		my $suffix = TTP::Telemetry::var([ 'ping', $which, 'publish', 'suffix' ]) // $which;

		my $metric_name = $opt_metric || TTP::Telemetry::var([ 'ping', $which, 'publish', 'name' ]) || "ttp_ping_<DEVICE>_<SUFFIX>";
		my $metric_description = $opt_description || TTP::Telemetry::var([ 'ping', $which, 'publish', 'description' ]) || "ttp_ping_<DEVICE>_<SUFFIX>";

		my $metric = {
			name => $metric_name,
			value => $value,
			help => $metric_description,
			type => 'gauge',
			additionals => {
				DEVICE => $opt_device,
				SUFFIX => $suffix
			}
		};
		my @labels = ( @opt_prepends, @opt_appends );
		$metric->{labels} = \@labels if scalar @labels;

		# default is to publish to all media
		my $to_http = true if grep( /all|http/i, @{$media} );
		my $to_mqtt = true if grep( /all|mqtt/i, @{$media} );
		my $to_text = true if grep( /all|text/i, @{$media} );
		$to_http = $opt_http if $opt_http_set;
		$to_mqtt = $opt_mqtt if $opt_mqtt_set;
		$to_text = $opt_text if $opt_text_set;

		TTP::Metric->new( $ep, $metric )->publish({
			mqtt => $to_mqtt,
			mqttPrefix => $opt_mqttPrefix,
			http => $to_http,
			httpPrefix => $opt_httpPrefix,
			text => $to_text,
			textPrefix => $opt_textPrefix
		});
	} else {
		msgVerbose( "$which publish is disabled by configuration" );
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
	"device=s"			=> \$opt_device,
	"metric=s"			=> \$opt_metric,
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
msgVerbose( "got device='$opt_device'" );
msgVerbose( "got metric='$opt_metric'" );
msgVerbose( "got description='$opt_description'" );
msgVerbose( "got type='$opt_type'" );
msgVerbose( "got mqtt='".( $opt_mqtt ? 'true':'false' )."'" );
msgVerbose( "got mqttPrefix='$opt_mqttPrefix'" );
msgVerbose( "got http='".( $opt_http ? 'true':'false' )."'" );
msgVerbose( "got httpPrefix='$opt_httpPrefix'" );
msgVerbose( "got text='".( $opt_text ? 'true':'false' )."'" );
msgVerbose( "got textPrefix='$opt_textPrefix'" );
@opt_prepends = split( /,/, join( ',', @opt_prepends ));
msgVerbose( "got prepends=[".join( ',', @opt_prepends )."]" );
@opt_appends = split( /,/, join( ',', @opt_appends ));
msgVerbose( "got appends=[".join( ',', @opt_appends )."]" );

# device is mandatory
msgErr( "'--device' option is required, but is not specified" ) if !$opt_device;

# disabled media are just ignored (or refused if option was explicit)
if( $opt_mqtt ){
	my $enabled = TTP::Telemetry::Mqtt::isEnabled();
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
	my $enabled = TTP::Telemetry::Http::isEnabled();
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
	my $enabled = TTP::Telemetry::Text::isEnabled();
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

if( !TTP::errs()){
	doPing();
}

TTP::exit();
