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
# HTTP-based telemetry.

package TTP::Telemetry::Http;
die __PACKAGE__ . " must be loaded as TTP::Telemetry::Http\n" unless __PACKAGE__ eq 'TTP::Telemetry::Http';

use strict;
use utf8;
use warnings;

use Data::Dumper;
use HTTP::Request::Common;
use LWP::UserAgent;
use Scalar::Util qw( looks_like_number );
use URI::Escape;

use TTP;
use TTP::Constants qw( :all );
use TTP::Message qw( :all );
use TTP::Telemetry;

use constant {
	# the publication error codes
	HTTP_DISABLED_BY_CONFIGURATION => 1,
	HTTP_NOURL => 2,
	VALUE_UNSUITED => 3,
	HTTP_REQUEST_ERROR => 4
};

my $Const = {
	# by convention all Prometheus (so http-based and text-based metrics) have this same prefix
	prefix => 'ttp_',
	# the error codes as labels
	errorLabels => [
		'OK',
		'HTTP_DISABLED_BY_CONFIGURATION',
		'HTTP_NOURL',
		'VALUE_UNSUITED',
		'HTTP_REQUEST_ERROR'
	]
};

# -------------------------------------------------------------------------------------------------
# Determines if HTTP-based telemetry is a site default, defaulting to false
# (I):
# - none
# (O):
# - whether HTTP-based telemetry is a default of the site

sub getDefault {
	my ( $class ) = @_;

	my $default = TTP::Telemetry::var([ 'withHttp', 'default' ]);
	$default = false if !defined $default;

	return $default;
}

# -------------------------------------------------------------------------------------------------
# Whether HTTP-based telemetry is allowed in the site, defaulting to true
# (I):
# - none
# (O):
# - whether HTTP-based telemetry is allowed in the site

sub isEnabled {
	my ( $class ) = @_;

	my $enabled = TTP::Telemetry::var([ 'withHttp', 'enabled' ]);
	$enabled = true if !defined $enabled;

	return $enabled;
}

# -------------------------------------------------------------------------------------------------
# publish a metric to HTTP-based PushGateway
# Publishing to Prometheus:
# - the value must be numeric
# - the name is prefixed by 'ttp_'
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
		my $url = TTP::Telemetry::var([ 'withHttp', 'url' ]);
		if( $url ){
			my $name = $metric->name();
			my $value = $metric->value();
			if( looks_like_number( $value )){
				# get and maybe prefix the name
				# final metric name will "'ttp_'+<provided_prefix>+<metric_name>"
				my $name = $metric->name();
				my $prefix = $opts->{prefix};
				if( $prefix ){
					$name = "$prefix$name";
				}
				$name = "$Const->{prefix}$name" if $Const->{prefix} && $name !~ m/^$Const->{prefix}/;
				# build the url
				my $labels = $metric->labels();
				foreach my $it ( @{$labels} ){
					my @words = split( /=/, $it );
					$url .= "/$words[0]/$words[1]";
				}
				# build the request body
				my $body = "";
				my $type = $metric->type();
				$body .= "# TYPE $name $type\n" if $type;
				my $help = $metric->help();
				$body .= "# HELP $name $help\n" if $help;
				$body .= "$name $value\n";
				# and post it
				my $dummy = $metric->ep()->runner()->dummy();
				if( $dummy ){
					msgDummy( "posting '$body' to '$url'" );
				} else {
					my $ua = LWP::UserAgent->new();
					my $request = HTTP::Request->new( POST => $url );
					msgVerbose( __PACKAGE__."::publish() url='$url' body='$body'" );
					$request->content( $body );
					my $response = $ua->request( $request );
					if( !$response->is_success ){
						msgVerbose( TTP::chompDumper( $response ));
						msgWarn( __PACKAGE__."::_http_publish() Code: ".$response->code." MSG: ".$response->decoded_content );
						$res = HTTP_REQUEST_ERROR;
					}
				}
			} else {
				$res = VALUE_UNSUITED;
			}
		} else {
			$res = HTTP_NOURL;
		}
	} else {
		$res = HTTP_DISABLED_BY_CONFIGURATION;
	}

	msgVerbose( __PACKAGE__."::publish() returning res='$res' ($Const->{errorLabels}[$res])" );
	return $res;
}

1;

__END__
