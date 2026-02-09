# @(#) run a GET on a HTTP/HTTPS endpoint
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
# @(-) --username=<username>   an optional username [${username}]
# @(-) --password=<password>   the corresponding password [${password}]
# @(-) --pwdkeys=<pwdkeys>     a comma-separated list of the keys to get the password from credentials [${pwdkeys}]
#
# @(@) Note 1: Among other uses, this verb is notably used to check which machine answers to a given URL in an architecture which wants take advantage of
# @(@)         IP Failover system. But, in such a system, all physical hosts are configured with this FO IP, and so answers are seen as originating from
# @(@)         this same physical host. In order to get accurate result in such a case, this verb must so be run from outside of the involved physical hosts.
# @(@) Note 2: '--epoch' option let the verb publish an epoch-based telemetry. This is very specific to the use of the telemetry by Grafana in order
# @(@)         to be able to both identify the last live node, and to set a status on this last live node to current or not.
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

use LWP::UserAgent;
use Time::Moment;

use TTP::Metric;

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
	service => '',
	username => '',
	password => '',
	pwdkeys => ''
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
my $opt_username = $defaults->{username};
my $opt_password = $defaults->{password};
my $opt_pwdkeys = $defaults->{pwdkeys};

# -------------------------------------------------------------------------------------------------
# request the url

sub doGet {
	msgOut( "requesting '$opt_url'..." );
	my $res = false;
	my $header = undef;
	my $response = undef;
	my $status = undef;
	if( $ep->runner()->dummy()){
		msgDummy( "considering successful with status='200' sent from this node" );
		$res = true;
		$header = "DUMMY_".$ep->node()->name();
	} else {
		my $ua = LWP::UserAgent->new();
		$ua->timeout( 5 );
		$response = $ua->get( $opt_url );
		$res = $response->is_success;
		$status = $response->code;
		if( $res ){
			msgVerbose( "receiving HTTP status='$status', success='true'" );
			msgLog( "content='".$response->decoded_content."'" );
		} else {
			msgErr( "received HTTP status='$status', success='false' for '$opt_url'" );
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
	_telemetry( $res ? Time::Moment->now->epoch : 0, $header, 'counter', '_epoch' ) if $opt_epoch;
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
	my ( $value, $header, $type, $suffix ) = @_;
	$suffix //= '';
	if( $opt_mqtt || $opt_http || $opt_text ){
		my ( $proto, $path ) = split( /:\/\//, $opt_url );
		my @labels = @opt_prepends;
		push( @labels, "environment=".( $ep->node()->environment() || '' ));
		push( @labels, "service=".$opt_service ) if $opt_service;
		push( @labels, "command=".$ep->runner()->command());
		push( @labels, "verb=".$ep->runner()->verb());
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
			name => "url_status$suffix",
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
	"help!"				=> sub { $ep->runner()->help( @_ ); },
	"colored!"			=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"			=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"			=> sub { $ep->runner()->verbose( @_ ); },
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
	"service=s"			=> \$opt_service,
	"username=s"		=> \$opt_username,
	"password=s"		=> \$opt_password,
	"pwdkeys=s"			=> \$opt_pwdkeys )){

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
msgVerbose( "got url='$opt_url'" );
msgVerbose( "got header='$opt_header'" );
msgVerbose( "got publishHeader='".( $opt_publishHeader ? 'true':'false' )."'" );
msgVerbose( "got response='".( $opt_response ? 'true':'false' )."'" );
msgVerbose( "got ignore='".( $opt_ignore ? 'true':'false' )."'" );
msgVerbose( "got accept='".join( ',', @{$opt_accept} )."'" );
msgVerbose( "got status='".( $opt_status ? 'true':'false' )."'" );
msgVerbose( "got epoch='".( $opt_epoch ? 'true':'false' )."'" );
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
msgVerbose( "got service='$opt_service'" );
msgVerbose( "got username='$opt_username'" );
msgVerbose( "got password='$opt_password'" );
msgVerbose( "got pwdkeys='$opt_pwdkeys'" );

# url is mandatory
msgErr( "url is required, but is not specified" ) if !$opt_url;

# requesting the header publication without any header has no sense
if( $opt_publishHeader ){
	msgWarn( "asking to publish a header without providing it has no sense, will be ignored" ) if !$opt_header;
	msgWarn( "asking to publish a header without publishing any telemetry it has no sense, will be ignored" ) if !$opt_mqtt && !$opt_http;
}

# warns if we publish both to http and text (as both go to same telemetry service)
msgWarn( "publishing telemetry to both 'http' and 'text' media is not advised and should be avoided" ) if $opt_http && $opt_text;

if( !TTP::errs()){
	doGet() if $opt_url;
}

TTP::exit();
