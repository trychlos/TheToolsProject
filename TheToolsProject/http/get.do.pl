# @(#) run a GET on a HTTP endpoint
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --url=<url>             the URL to be requested [${url}]
# @(-) --header=<header>       output the received (case insensitive) header [${header}]
# @(-) --[no]publishHeader     publish the found header content [${publishHeader}]
# @(-) --accept=<code>         consider the return code as OK, regex, may be specified several times or as a comma-separated list [${accept}]
# @(-) --[no]response          print the received response to stdout [${response}]
# @(-) --[no]status            publish status-based (i.e. alive|not alive or 1|0) telemetry [${status}]
# @(-) --[no]epoch             publish epoch-based (or 0 if not alive) telemetry [${epoch}]
# @(-) --[no]mqtt              publish the metrics to the (MQTT-based) messaging system [${mqtt}]
# @(-) --mqttPrefix=<prefix>   prefix the metric name when publishing to the (MQTT-based) messaging system [${mqttPrefix}]
# @(-) --[no]http              publish the metrics to the (HTTP-based) Prometheus PushGateway system [${http}]
# @(-) --httpPrefix=<prefix>   prefix the metric name when publishing to the (HTTP-based) Prometheus PushGateway system [${httpPrefix}]
# @(-) --[no]text              publish the metrics to the (text-based) Prometheus TextFile Collector system [${text}]
# @(-) --textPrefix=<prefix>   prefix the metric name when publishing to the (text-based) Prometheus TextFile Collector system [${textPrefix}]
# @(-) --prepend=<name=value>  label to be prepended to the telemetry metrics, may be specified several times or as a comma-separated list [${prepend}]
# @(-) --append=<name=value>   label to be appended to the telemetry metrics, may be specified several times or as a comma-separated list [${append}]
# @(-) --service=<service>     an optional service name to be inserted in the MQTT topic [${service}]
#
# @(@) Among other uses, this verb is notably used to check which machine answers to a given URL in an architecture which wants take advantage of
# @(@) IP Failover system. But, in such a system, all physical hosts are configured with this FO IP, and so would answer to this IP is the request
# @(@) originates from this same physical host.
# @(@) In order to get accurate result, this verb must so be run from outside of the involved physical hosts.
# @(@) '--epoch' option let the verb publish an epoch-based telemetry. This is very specific to the use of the telemetry by Grafana in order
# @(@) to be able to both identify the last live node, and to set a status on this last live node to current or not.
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

use HTTP::Request;
use LWP::UserAgent;
use Time::Piece;
use URI::Escape;

use TTP::Metric;
my $running = $ep->runner();

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	url => '',
	header => '',
	publishHeader => 'no',
	response => 'no',
	accept => '200',
	status => 'no',
	epoch => 'no',
	mqtt => 'no',
	mqttPrefix => '',
	http => 'no',
	httpPrefix => '',
	text => 'no',
	textPrefix => '',
	prepend => '',
	append => '',
	service => ''
};

my $opt_url = $defaults->{url};
my $opt_header = $defaults->{header};
my $opt_publishHeader = false;
my $opt_response = false;
my $opt_ignore = false;
my $opt_accept = [ $defaults->{accept} ];
my $opt_status = false;
my $opt_epoch = false;
my $opt_mqtt = false;
my $opt_mqttPrefix = $defaults->{mqttPrefix};
my $opt_http = false;
my $opt_httpPrefix = $defaults->{httpPrefix};
my $opt_text = false;
my $opt_textPrefix = $defaults->{textPrefix};
my @opt_prepends = ();
my @opt_appends = ();
my $opt_service = $defaults->{service};

# -------------------------------------------------------------------------------------------------
# request the url

sub doGet {
	msgOut( "requesting '$opt_url'..." );
	my $res = false;
	my $header = undef;
	my $response = undef;
	my $status = undef;
	if( $running->dummy()){
		msgDummy( "considering successful with status='200' sent from this node" );
		$res = true;
		$header = "DUMMY_".$ep->node()->name();
	} else {
		my $ua = LWP::UserAgent->new();
		$ua->timeout( 5 );
		my $req = HTTP::Request->new( GET => $opt_url );
		$response = $ua->request( $req );
		$res = $response->is_success;
		$status = $response->code;
		if( $res ){
			msgVerbose( "receiving HTTP status='$status', success='true'" );
			msgLog( "content='".$response->decoded_content."'" );
		} else {
			msgErr( "received HTTP status='$status', success='false'" );
			$status = $response->status_line;
			msgLog( "additional status: '$status'" );
			my $acceptedRegex = undef;
			foreach my $regex ( @{$opt_accept} ){
				$acceptedRegex = $regex if ( $response->code =~ /$regex/ );
				last if defined $acceptedRegex;
			}
			if( defined $acceptedRegex ){
				msgOut( "status code match '$acceptedRegex' accepted regex, forcing result to true" );
				$res = true;
			}
		}
		# find the header if asked for
		if( $res && $opt_header ){
			$header = $response->header( $opt_header );
		}
	}
	# print the header if asked for
	if( $res && $opt_header ){
		print "  $opt_header: $header".EOL;
	}
	# test
	#$res = false;
	# and send the telemetry if opt-ed in
	_telemetry( $res ? 1 : 0, $header, 'gauge' ) if $opt_status;
	_telemetry( $res ? localtime->epoch : 0, $header, 'counter', '_epoch' ) if $opt_epoch;
	if( $res ){
		if( $opt_response ){
			print Dumper( $response );
		}
		msgOut( "success" );
	} else {
		msgLog( Dumper( $response ));
		msgErr( "NOT OK: $status", { incErr => false });
	}
}

# -------------------------------------------------------------------------------------------------
# publish the telemetry, either with a status value, or with the epoch

sub _telemetry {
	my ( $value, $header, $type, $sufix ) = @_;
	$sufix //= '';
	if( $opt_mqtt || $opt_http || $opt_text ){
		my ( $proto, $path ) = split( /:\/\//, $opt_url );
		my @labels = @opt_prepends;
		push( @labels, "environment=".$ep->node()->environment());
		push( @labels, "service=".$opt_service ) if $opt_service;
		push( @labels, "command=".$running->command());
		push( @labels, "verb=".$running->verb());
		push( @labels, "proto=$proto" );
		push( @labels, "path=$path" );
		if( $opt_header && $header && $opt_publishHeader ){
			my $header_label = $opt_header;
			$header_label =~ s/[^a-zA-Z0-9_]//g;
			push( @labels, "$header_label=$header" );
		}
		push( @labels, @opt_appends );
		msgVerbose( "added labels [".join( ',', @labels )."]" );

		TTP::Metric->new( $ep, {
			name => "url_status$sufix",
			value => $value,
			type => $type,
			help => 'The last time the url has been seen alive',
			labels => \@labels
		})->publish({
			mqtt => $opt_mqtt,
			mqttPrefix => $opt_mqttPrefix,
			http => $opt_http,
			httpPrefix => $opt_httpPrefix,
			text => $opt_text,
			textPrefix => $opt_textPrefix
		});
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
	"url=s"				=> \$opt_url,
	"header=s"			=> \$opt_header,
	"publishHeader!"	=> \$opt_publishHeader,
	"response!"			=> \$opt_response,
	"ignore!"			=> \$opt_ignore,
	"accept=s@"			=> \$opt_accept,
	"status!"			=> \$opt_status,
	"epoch!"			=> \$opt_epoch,
	"mqtt!"				=> \$opt_mqtt,
	"mqttPrefix=s"		=> \$opt_mqttPrefix,
	"http!"				=> \$opt_http,
	"httpPrefix=s"		=> \$opt_httpPrefix,
	"text!"				=> \$opt_text,
	"textPrefix=s"		=> \$opt_textPrefix,
	"prepend=s@"		=> \@opt_prepends,
	"append=s@"			=> \@opt_appends,
	"service=s"			=> \$opt_service )){

		msgOut( "try '".$running->command()." ".$running->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $running->help()){
	$running->verbHelp( $defaults );
	TTP::exit();
}

msgVerbose( "found colored='".( $running->colored() ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $running->dummy() ? 'true':'false' )."'" );
msgVerbose( "found verbose='".( $running->verbose() ? 'true':'false' )."'" );
msgVerbose( "found url='$opt_url'" );
msgVerbose( "found header='$opt_header'" );
msgVerbose( "found publishHeader='".( $opt_publishHeader ? 'true':'false' )."'" );
msgVerbose( "found response='".( $opt_response ? 'true':'false' )."'" );
msgVerbose( "found ignore='".( $opt_ignore ? 'true':'false' )."'" );
msgVerbose( "found accept='".join( ',', @{$opt_accept} )."'" );
msgVerbose( "found status='".( $opt_status ? 'true':'false' )."'" );
msgVerbose( "found epoch='".( $opt_epoch ? 'true':'false' )."'" );
msgVerbose( "found mqtt='".( $opt_mqtt ? 'true':'false' )."'" );
msgVerbose( "found mqttPrefix='$opt_mqttPrefix'" );
msgVerbose( "found http='".( $opt_http ? 'true':'false' )."'" );
msgVerbose( "found httpPrefix='$opt_httpPrefix'" );
msgVerbose( "found text='".( $opt_text ? 'true':'false' )."'" );
msgVerbose( "found textPrefix='$opt_textPrefix'" );
@opt_prepends = split( /,/, join( ',', @opt_prepends ));
msgVerbose( "found prepends='".join( ',', @opt_prepends )."'" );
@opt_appends = split( /,/, join( ',', @opt_appends ));
msgVerbose( "found appends='".join( ',', @opt_appends )."'" );
msgVerbose( "found service='$opt_service'" );

# url is mandatory
msgErr( "url is required, but is not specified" ) if !$opt_url;

# requesting the header publication without any header has no sense
if( $opt_publishHeader ){
	msgWarn( "asking to publish a header without providing it has no sense, will be ignored" ) if !$opt_header;
	msgWarn( "asking to publish a header without publishing any telemetry it has no sense, will be ignored" ) if !$opt_mqtt && !$opt_http;
}

if( !TTP::errs()){
	doGet() if $opt_url;
}

TTP::exit();
