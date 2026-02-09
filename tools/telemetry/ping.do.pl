# @(#) ping a device and publish the telemetry
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --device=<name>         the device to be pinged [${device}]
# @(-)   alert options:
# @(-) --[no]alert-file        create a JSON file alert, monitorable e.g. by the alert daemon [${alert_file}]
# @(-) --[no]alert-mms         send the alert by MMS [${alert_mms}]
# @(-) --[no]alert-mqtt        send the alert on the MQTT bus [${alert_mqtt}]
# @(-) --[no]alert-sms         send the alert by SMS [${alert_sms}]
# @(-) --[no]alert-smtp        send the alert by SMTP [${alert_smtp}]
# @(-) --[no]alert-tts         send the alert with text-to-speech [${alert_tts}]
# @(-) --errors=<count>        override the configured errors count threshold [${errors}]
# @(-)   telemetry options:
# @(-) --metric=<name>         the metric to be published [${metric}]
# @(-) --description=<string>  a one-line help description [${description}]
# @(-) --[no]publish-mqtt      publish the metrics to the (MQTT-based) messaging system [${publish_mqtt}]
# @(-) --mqttPrefix=<prefix>   prefix the metric name when publishing to the (MQTT-based) messaging system [${mqttPrefix}]
# @(-) --[no]publish-http      publish the metrics to the (HTTP-based) Prometheus PushGateway system [${publish_http}]
# @(-) --httpPrefix=<prefix>   prefix the metric name when publishing to the (HTTP-based) Prometheus PushGateway system [${httpPrefix}]
# @(-) --[no]publish-text      publish the metrics to the (text-based) Prometheus TextFile Collector system [${publish_text}]
# @(-) --textPrefix=<prefix>   prefix the metric name when publishing to the (text-based) Prometheus TextFile Collector system [${textPrefix}]
# @(-) --prepend=<name=value>  label to be prepended to the telemetry metrics, may be specified several times or as a comma-separated list [${prepend}]
# @(-) --append=<name=value>   label to be appended to the telemetry metrics, may be specified several times or as a comma-separated list [${append}]
# @(-) --latency=<latency>     override the configured latency threshold [${latency}]
#
# TheToolsProject - Tools System and Working Paradigm for IT Production
# Copyright (©) 1998-2023 Pierre Wieser (see AUTHORS)
# Copyright (©) 2023-2026 PWI Consulting
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
	mqttPrefix => '',
	httpPrefix => '',
	textPrefix => '',
	prepend => '',
	append => ''
};

my $opt_device = $defaults->{device};
my $opt_metric = $defaults->{metric};
my $opt_description = $defaults->{description};
my $opt_mqttPrefix = $defaults->{mqttPrefix};
my $opt_httpPrefix = $defaults->{httpPrefix};
my $opt_textPrefix = $defaults->{textPrefix};
my @opt_prepends = ();
my @opt_appends = ();

# some default constants
my $Const = {
	errors => {
		threshold => 2
	},
	latency => {
		threshold => 1000
	}
};

# alert options
my ( $opt_alert_file, $file_enabled ) = TTP::alertsWithFile();
$defaults->{alert_file} = $opt_alert_file && $file_enabled ? 'yes' : 'no';
my $opt_alert_file_set = false;

my ( $opt_alert_mms, $mms_enabled ) = TTP::alertsWithMms();
$defaults->{alert_mms} = $opt_alert_mms && $mms_enabled ? 'yes' : 'no';
my $opt_alert_mms_set = false;

my ( $opt_alert_mqtt, $mqtt_enabled ) = TTP::alertsWithMms();
$defaults->{alert_mqtt} = $opt_alert_mqtt && $mqtt_enabled ? 'yes' : 'no';
my $opt_alert_mqtt_set = false;

my ( $opt_alert_sms, $sms_enabled ) = TTP::alertsWithSms();
$defaults->{alert_sms} = $opt_alert_sms && $sms_enabled ? 'yes' : 'no';
my $opt_alert_sms_set = false;

my ( $opt_alert_smtp, $smtp_enabled ) = TTP::alertsWithSmtp();
$defaults->{alert_smtp} = $opt_alert_smtp && $smtp_enabled ? 'yes' : 'no';
my $opt_alert_smtp_set = false;

my ( $opt_alert_tts, $tts_enabled ) = TTP::alertsWithTts();
$defaults->{alert_tts} = $opt_alert_tts && $tts_enabled ? 'yes' : 'no';
my $opt_alert_tts_set = false;

my $opt_errors = TTP::Telemetry::var([ 'ping', 'errors', 'alert', 'threshold' ]) // $Const->{errors}{threshold};
$defaults->{errors} = $opt_errors;

# telemetry options
my $opt_publish_mqtt = TTP::Telemetry::Mqtt::getDefault();
$defaults->{publish_mqtt} = $opt_publish_mqtt ? 'yes' : 'no';
my $opt_publish_mqtt_set = false;

my $opt_publish_http = TTP::Telemetry::Http::getDefault();
$defaults->{publish_http} = $opt_publish_http ? 'yes' : 'no';
my $opt_publish_http_set = false;

my $opt_publish_text = TTP::Telemetry::Text::getDefault();
$defaults->{publish_text} = $opt_publish_text ? 'yes' : 'no';
my $opt_publish_text_set = false;

my $opt_latency = TTP::Telemetry::var([ 'ping', 'latency', 'alert', 'threshold' ]) // $Const->{latency}{threshold};
$defaults->{latency} = $opt_latency;

# -------------------------------------------------------------------------------------------------
# Giving the output of the publication, manage the alert
# Alert media are not overridable on the command-line

sub alert {
	my ( $res, $which ) = @_;

	# do we have alerts ?
	my $enabled = TTP::Telemetry::var([ 'ping', $which, 'alert', 'enabled' ]) // true;
	if( $enabled ){
		my $threshold = $which eq 'errors' ? $opt_errors : ( $which eq 'latency' ? $opt_latency : 'UNEXPECTED' );
		if( $threshold eq 'UNEXPECTED' ){
			msgWarn( "unexpected which='$which', giving up" );
		} elsif( $res->{value} >= $threshold ){
			my $file = $opt_alert_file_set && $opt_alert_file ? "--file" : "";
			my $mms = $opt_alert_mms_set && $opt_alert_mms ? "--mms" : "";
			my $mqtt = $opt_alert_mqtt_set && $opt_alert_mqtt ? "--mqtt" : "";
			my $sms = $opt_alert_sms_set && $opt_alert_sms ? "--sms" : "";
			my $smtp = $opt_alert_smtp_set && $opt_alert_smtp ? "--smtp" : "";
			my $tts = $opt_alert_tts_set && $opt_alert_tts ? "--tts" : "";
			my $title = $which eq "errors" ? "$opt_device doesn't answer to ping (errors count=$res->{value})" : "$opt_device exhibits high $res->{value} ms latency";
			my $command = "ttp.pl alert -title \"$title\" $file $mms $mqtt $sms $smtp $tts";
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
	my @qualifiers = @{ $ep->runner()->runnableQualifiers() };
	shift @qualifiers;
	my $fname = File::Spec->catfile( $out->{dropDir}, sprintf( "%s_%s_%s.errors_count", $ep->runner()->runnableBNameShort(), join( '_', @qualifiers ), $opt_device ));
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
		my $suffix = TTP::Telemetry::var([ 'ping', $which, 'publish', 'suffix' ]) // $which;
		my $metric_name = $opt_metric || TTP::Telemetry::var([ 'ping', $which, 'publish', 'name' ]) || "ttp_ping_<SUFFIX>";
		my $metric_description = $opt_description || TTP::Telemetry::var([ 'ping', $which, 'publish', 'description' ]) || "ttp_ping <SUFFIX>";

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
		my @labels = ( @opt_prepends, "device=$opt_device", @opt_appends );
		$metric->{labels} = \@labels if scalar @labels;

		# default is to publish to all default media
		my $to_http = $opt_publish_http_set ? $opt_publish_http : undef;
		my $to_mqtt = $opt_publish_mqtt_set ? $opt_publish_mqtt : undef;
		my $to_text = $opt_publish_text_set ? $opt_publish_text : undef;

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
	# alert options
	"alert-file!"		=> sub {
		my( $name, $value ) = @_;
		$opt_alert_file = $value;
		$opt_alert_file_set = true;
	},
	"alert-mms!"		=> sub {
		my( $name, $value ) = @_;
		$opt_alert_mms = $value;
		$opt_alert_mms_set = true;
	},
	"alert-mqtt!"		=> sub {
		my( $name, $value ) = @_;
		$opt_alert_mqtt = $value;
		$opt_alert_mqtt_set = true;
	},
	"alert-sms!"		=> sub {
		my( $name, $value ) = @_;
		$opt_alert_sms = $value;
		$opt_alert_sms_set = true;
	},
	"alert-smtp!"		=> sub {
		my( $name, $value ) = @_;
		$opt_alert_smtp = $value;
		$opt_alert_smtp_set = true;
	},
	"alert-tts!"		=> sub {
		my( $name, $value ) = @_;
		$opt_alert_tts = $value;
		$opt_alert_tts_set = true;
	},
	"errors=i"			=> \$opt_errors,
	# telemetry options
	"publish-mqtt!"		=> sub {
		my ( $name, $value ) = @_;
		$opt_publish_mqtt = $value;
		$opt_publish_mqtt_set = true;
	},
	"mqttPrefix=s"		=> \$opt_mqttPrefix,
	"publish-http!"		=> sub {
		my ( $name, $value ) = @_;
		$opt_publish_http = $value;
		$opt_publish_http_set = true;
	},
	"httpPrefix=s"		=> \$opt_httpPrefix,
	"publish-text!"		=> sub {
		my ( $name, $value ) = @_;
		$opt_publish_text = $value;
		$opt_publish_text_set = true;
	},
	"textPrefix=s"		=> \$opt_textPrefix,
	"prepend=s@"		=> \@opt_prepends,
	"append=s@"			=> \@opt_appends,
	"latency=i"			=> \$opt_latency )){

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
# alert options
msgVerbose( "got alert-file='".( $opt_alert_file ? 'true':'false' )."'" );
msgVerbose( "got alert-mms='".( $opt_alert_mms ? 'true':'false' )."'" );
msgVerbose( "got alert-mqtt='".( $opt_alert_mqtt ? 'true':'false' )."'" );
msgVerbose( "got alert-sms='".( $opt_alert_sms ? 'true':'false' )."'" );
msgVerbose( "got alert-smtp='".( $opt_alert_smtp ? 'true':'false' )."'" );
msgVerbose( "got alert-tts='".( $opt_alert_tts ? 'true':'false' )."'" );
msgVerbose( "got errors='$opt_errors'" );
# telemetry options
msgVerbose( "got metric='$opt_metric'" );
msgVerbose( "got description='$opt_description'" );
msgVerbose( "got publish-mqtt='".( $opt_publish_mqtt ? 'true':'false' )."'" );
msgVerbose( "got mqttPrefix='$opt_mqttPrefix'" );
msgVerbose( "got publish-http='".( $opt_publish_http ? 'true':'false' )."'" );
msgVerbose( "got httpPrefix='$opt_httpPrefix'" );
msgVerbose( "got publish-text='".( $opt_publish_text ? 'true':'false' )."'" );
msgVerbose( "got textPrefix='$opt_textPrefix'" );
@opt_prepends = split( /,/, join( ',', @opt_prepends ));
msgVerbose( "got prepends=[".join( ',', @opt_prepends )."]" );
@opt_appends = split( /,/, join( ',', @opt_appends ));
msgVerbose( "got appends=[".join( ',', @opt_appends )."]" );
msgVerbose( "got latency='$opt_latency'" );

# device is mandatory
msgErr( "'--device' option is required, but is not specified" ) if !$opt_device;

# alert options
# disabled media are just ignored (or refused if option was explicit)
if( $opt_alert_file ){
	if( !$file_enabled ){
		if( $opt_alert_file_set ){
			msgErr( "File medium is disabled, --file option is not valid" );
		} else {
			msgWarn( "File medium is disabled and thus ignored" );
			$opt_alert_file = false;
		}
	}
}
if( $opt_alert_mms ){
	if( !$mms_enabled ){
		if( $opt_alert_mms_set ){
			msgErr( "MMS medium is disabled, --mms option is not valid" );
		} else {
			msgWarn( "MMS medium is disabled and thus ignored" );
			$opt_alert_mms = false;
		}
	}
}
if( $opt_alert_mqtt ){
	if( !$mqtt_enabled ){
		if( $opt_alert_mqtt_set ){
			msgErr( "MQTT medium is disabled, --mqtt option is not valid" );
		} else {
			msgWarn( "MQTT medium is disabled and thus ignored" );
			$opt_alert_mqtt = false;
		}
	}
}
if( $opt_alert_sms ){
	if( !$sms_enabled ){
		if( $opt_alert_sms_set ){
			msgErr( "SMS medium is disabled, --sms option is not valid" );
		} else {
			msgWarn( "SMS medium is disabled and thus ignored" );
			$opt_alert_sms = false;
		}
	}
}
if( $opt_alert_smtp ){
	if( !$smtp_enabled ){
		if( $opt_alert_smtp_set ){
			msgErr( "SMTP medium is disabled, --smtp option is not valid" );
		} else {
			msgWarn( "SMTP medium is disabled and thus ignored" );
			$opt_alert_smtp = false;
		}
	}
}
if( $opt_alert_tts ){
	if( !$tts_enabled ){
		if( $opt_alert_tts_set ){
			msgErr( "Text-To-Speech medium is disabled, --tts option is not valid" );
		} else {
			msgWarn( "Text-To-Speech medium is disabled and thus ignored" );
			$opt_alert_tts = false;
		}
	}
}

# telemetry options
# disabled media are just ignored (or refused if option was explicit)
if( $opt_publish_mqtt ){
	my $enabled = TTP::Telemetry::Mqtt::isEnabled();
	if( !$enabled ){
		if( $opt_publish_mqtt_set ){
			msgErr( "MQTT telemetry is disabled, --mqtt option is not valid" );
		} else {
			msgWarn( "MQTT telemetry is disabled and thus ignored" );
			$opt_publish_mqtt = false;
		}
	}
}
if( $opt_publish_http ){
	my $enabled = TTP::Telemetry::Http::isEnabled();
	if( !$enabled ){
		if( $opt_publish_http_set ){
			msgErr( "HTTP PushGateway telemetry is disabled, --http option is not valid" );
		} else {
			msgWarn( "HTTP PushGateway telemetry is disabled and thus ignored" );
			$opt_publish_http = false;
		}
	}
}
if( $opt_publish_text ){
	my $enabled = TTP::Telemetry::Text::isEnabled();
	if( !$enabled ){
		if( $opt_publish_text_set ){
			msgErr( "TextFile Collector telemetry is disabled, --text option is not valid" );
		} else {
			msgWarn( "TextFile Collector telemetry is disabled and thus ignored" );
			$opt_publish_text = false;
		}
	}
}

# if labels are specified, check that they are all of the 'name=value' form
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

# warns if we publish both to http and text (as both go to same telemetry service)
msgWarn( "publishing telemetry to both 'http' and 'text' media is not advised and should be avoided" ) if $opt_publish_http && $opt_publish_text;

if( !TTP::errs()){
	doPing();
}

TTP::exit();
