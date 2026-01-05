# @(#) list the published metrics
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]http              limit to metrics published on the PushGateway [${http}]
# @(-) --[no]http-groups       group the PushGateway metrics [${httpGroups}]
# @(-) --[no]http-compare      compare the grouped and ungrouped results from the PushGateway [${httpCompare}]
# @(-) --[no]text              limit to metrics published on the local TextFile collector [${text}]
# @(-) --[no]server            get available metrics from the server [${server}]
# @(-) --limit=<limit>         only list first <limit> metric [${limit}]
#
# @(@) Note 1: Grouped PushGateway metrics exhibit the last pushed timestamp, while ungrouped don't. Both display the last pushed value.
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

use Array::Utils qw( :all );
use Data::Dumper;
use File::Basename;
use File::Spec;
use HTML::Parser;
use HTTP::Request;
use JSON;
use LWP::UserAgent;
use Path::Tiny;
use URI;
use URI::Split qw( uri_split uri_join );

use TTP::Telemetry;
use TTP::Telemetry::Http;
use TTP::Telemetry::Text;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	http => 'no',
	httpCompare => 'no',
	httpGroups => 'no',
	text => 'no',
	server => 'no',
	limit => -1
};

my $opt_http = false;
my $opt_http_compare = false;
my $opt_http_groups = false;
my $opt_text = false;
my $opt_server = false;
my $opt_limit = $defaults->{limit};

# -------------------------------------------------------------------------------------------------
# metrics got back from the PushGateway may slightly differ depending of they are got grouped or ungrouped.
# detail here the diffs

sub doCompareHttp {
	msgOut( "comparing grouped an ungrouped metrics got from the HTTP PushGateway..." );
	my $count_grouped = 0;
	my $count_raw = 0;
	my $enabled = TTP::Telemetry::Http::isEnabled();
	if( $enabled ){
		my $url = TTP::Telemetry::var([ 'withHttp', 'url' ]);
		if( $url ){
			my ( $scheme, $auth, $path, $query, $frag ) = uri_split( $url );
			# get metrics from grouped
			my $grouped = _http_get_grouped( $scheme, $auth );
			my $grouped_metrics = [];
			foreach my $id ( keys %{$grouped} ){
				my $labels = [];
				foreach my $str ( sort @{$grouped->{$id}{labels}} ){
					my @w = split( /=/, $str );
					push( @{$labels}, "$w[0]=\"$w[1]\"" );
				}
				foreach my $name ( sort keys %{$grouped->{$id}{metrics}} ){
					push( @{$grouped_metrics}, $name."{".join( ",", sort @{$labels} )."}" );
				}
			}
			msgVerbose( "got ".scalar( @{$grouped_metrics} ). " grouped metrics" );
			# get metrics from raw
			my $raw = _http_get_raw( $scheme, $auth, { removeEmptyLabels => true });
			my $raw_metrics = [];
			foreach my $name ( sort keys %{$raw} ){
				push( @{$raw_metrics}, $name );
			}
			msgVerbose( "got ".scalar( @{$raw_metrics} ). " raw metrics" );
			my $diffs = [];
			foreach my $it ( sort @{$grouped_metrics} ){
				if( !grep( /\$it/, @{$raw_metrics} )){
					print "grouped metric not found in raw: $it".EOL ;
					$count_grouped += 1;
					last if $count_grouped > $opt_limit;
				}
			}
			foreach my $it ( sort @{$raw_metrics} ){
				if( !grep( /\$it/, @{$grouped_metrics} )){
					print "raw metric not found in grouped: $it".EOL ;
					$count_raw += 1;
					last if $count_raw > $opt_limit;
				}
			}
		} else {
			msgErr( "PushGateway HTTP URL is not configured" );
		}
	} else {
		msgErr( "HTTP-based PushGateway is disabled by configuration" );
	}
	if( TTP::errs()){
		msgErr( "NOT OK" );
	} else {
		msgOut( "grouped metric(s) not found in raw: $count_grouped" );
		msgOut( "raw metric(s) not found in grouped: $count_raw" );
	}
}

# -------------------------------------------------------------------------------------------------
# list metrics published on the PushGateway
# The PushGateway can be requested:
# - either on its root url, in which case it returns a web page where metrics are grouped by labels
#   each group gathers all metrics with these same labels (and, in general, at least 3: our own metric and the Prometheus internal ones)
# - either on '/metrics' url to get rough (ungrouped) metrics

sub doListHttp {
	msgOut( "listing metrics published on the HTTP PushGateway..." );
	my $metrics = {};
	my $groups_count = 0;
	my $metrics_count = 0;
	my $enabled = TTP::Telemetry::Http::isEnabled();
	if( $enabled ){
		my $url = TTP::Telemetry::var([ 'withHttp', 'url' ]);
		if( $url ){
			# get the host part only
			my ( $scheme, $auth, $path, $query, $frag ) = uri_split( $url );
			if( $opt_http_groups ){
				$metrics = _http_get_grouped( $scheme, $auth );
				#print STDERR "got metrics ".Dumper( $metrics );
				foreach my $id ( sort { $a <=> $b } keys %{$metrics} ){
					$groups_count += 1;
					my $labels = [];
					foreach my $str ( sort @{$metrics->{$id}{labels}} ){
						my @w = split( /=/, $str );
						push( @{$labels}, "$w[0]=\"$w[1]\"" );
					}
					print " g=$groups_count: {".join( ',', @{$labels} )."}".EOL;
					foreach my $name ( sort keys %{$metrics->{$id}{metrics}} ){
						$metrics_count += 1;
						print "  m=$metrics_count: $name last_pushed=$metrics->{$id}{metrics}{$name}{stamp}, last_value=$metrics->{$id}{metrics}{$name}{value}".EOL;
					}
				}
			} else {
				$metrics = _http_get_raw( $scheme, $auth );
				#print STDERR "got metrics ".Dumper( $metrics );
				foreach my $name ( sort keys %{$metrics} ){
					$metrics_count += 1;
					print " m=$metrics_count: $name last_value=$metrics->{$name}{value}".EOL;
				}
			}
		} else {
			msgErr( "PushGateway HTTP URL is not configured" );
		}
	} else {
		msgWarn( "HTTP-based PushGateway is disabled by configuration" );
	}
	if( TTP::errs()){
		msgErr( "NOT OK" );
	} elsif( $opt_http_groups ){
		msgOut( "$metrics_count metric(s) found (in $groups_count group(s))" );
	} else {
		msgOut( "$metrics_count metric(s) found" );
	}
}

sub _http_get_grouped {
	my ( $scheme, $auth, $args ) = @_;
	my $metrics = {};
	my $url = uri_join( $scheme, $auth );
	msgVerbose( "requesting '$url'" );
	my $ua = LWP::UserAgent->new();
	my $request = HTTP::Request->new( GET => $url );
	my $answer = $ua->request( $request );
	if( $answer->is_success ){
		$metrics = _http_parse_groups( $answer->decoded_content, $args );
	} else {
		msgVerbose( TTP::chompDumper( $answer ));
		msgErr( "Code: ".$answer->code." MSG: ".$answer->decoded_content );
	}
	return $metrics;
}

sub _http_get_raw {
	my ( $scheme, $auth, $args ) = @_;
	my $metrics = {};
	my $url = uri_join( $scheme, $auth, "/metrics" );
	msgVerbose( "requesting '$url'" );
	my $ua = LWP::UserAgent->new();
	my $request = HTTP::Request->new( GET => $url );
	my $answer = $ua->request( $request );
	if( $answer->is_success ){
		$metrics = _http_parse_metrics( $answer->decoded_content, $args );
	} else {
		msgVerbose( TTP::chompDumper( $answer ));
		msgErr( "Code: ".$answer->code." MSG: ".$answer->decoded_content );
	}
}

# parse the returned web page to get the grouped metrics
# Returns:
# {
#   <group_id> => {
#     labels  => [ 'k=v', ... ],
#     metrics => {
#       <metric_name> => { stamp => <stamp>, value => <value> },
#       ...
#     },
#   },
#   ...
# }
# code by ChatGPT

sub _http_parse_groups {
    my ($html ) = @_;
    my %groups;

    # --- parser state ---
    my $cur_group_id;
    my $in_group_header = 0;
    my $in_label_span   = 0;

    my $in_metric_header_btn = 0;
    my $metric_header_text   = '';

    my $in_metric_table  = 0;
    my $in_tbody_row     = 0;
    my $in_td            = 0;
    my $td_index         = 0;

    my ($metric_name, $metric_stamp, $metric_value);

    my $p = HTML::Parser->new(
        api_version => 3,

        start_h => [ sub {
            my ($self, $tag, $attr) = @_;

            # --- Enter a group header ---
            if ($tag eq 'div' && ($attr->{class} // '') eq 'card-header'
                && defined $attr->{id} && $attr->{id} =~ /^group-panel-(\d+)/)
            {
                $cur_group_id    = $1;
                $in_group_header = 1;
                $groups{$cur_group_id} //= { labels => [], metrics => {} };
                return;
            }

            # --- Label spans ---
            if ($in_group_header && $tag eq 'span'
                && defined $attr->{class} && $attr->{class} =~ /badge/)
            {
                $in_label_span = 1;
                return;
            }

            # --- Metric header button ---
            if ($tag eq 'button' && ($attr->{class} // '') =~ /\bbtn\b/)
            {
                $in_metric_header_btn = 1;
                $metric_header_text   = '';
                $metric_name  = undef;
                $metric_stamp = undef;
                $metric_value = undef;
                return;
            }

            # --- Table for metric values ---
            if ($tag eq 'table' && ($attr->{class} // '') =~ /\btable\b/)
            {
                $in_metric_table = 1;
                return;
            }
            if ($in_metric_table && $tag eq 'tr') {
                $in_tbody_row = 1;
                $td_index     = 0;
                return;
            }
            if ($in_tbody_row && $tag eq 'td') {
                $in_td    = 1;
                $td_index += 1;
                return;
            }
        }, 'self, tagname, attr' ],

        text_h => [ sub {
            my ($self, $text) = @_;

            # --- Collect group labels ---
            if ($in_group_header && $in_label_span && defined $cur_group_id && length $text) {
                my $t = $text;
                $t =~ s/\s+//g;
                $t =~ s/^([^=]+)="(.*)"$/$1=$2/;
                push @{ $groups{$cur_group_id}{labels} }, $t if $t =~ /=/;
                return;
            }

            # --- Metric header text (contains metric name + "last pushed") ---
            if ($in_metric_header_btn && length $text) {
                $metric_header_text .= $text;
                return;
            }

            # --- Metric value (second <td>) ---
            if ($in_metric_table && $in_tbody_row && $in_td && $td_index == 2) {
                my $v = $text // '';
                $v =~ s/^\s+|\s+$//g;
                $metric_value = $v if length $v;
                return;
            }
        }, 'self, text' ],

        end_h => [ sub {
            my ($self, $tag) = @_;

            if ($tag eq 'span') {
                $in_label_span = 0;
                return;
            }

            # --- Leaving a group header ---
            if ($tag eq 'div' && $in_group_header) {
                $in_group_header = 0;
                $self->eof() if $opt_limit >= 0 && (scalar keys %groups) >= $opt_limit;
                return;
            }

            # --- End metric header button: parse name + stamp ---
            if ($tag eq 'button' && $in_metric_header_btn) {
                $in_metric_header_btn = 0;

                my $t = $metric_header_text;
                $t =~ s/\s+/ /g;
                $t =~ s/^\s+|\s+$//g;

                ($metric_name)  = $t =~ /^([^\s<]+)/;
                ($metric_stamp) = $t =~ /last pushed:\s*([0-9T:+-]+)/i;
                return;
            }

            if ($tag eq 'td') {
                $in_td = 0;
                return;
            }
            if ($tag eq 'tr') {
                $in_tbody_row = 0;
                return;
            }

            # --- End of metric table: record metric ---
            if ($tag eq 'table' && $in_metric_table) {
                $in_metric_table = 0;
                if (defined $cur_group_id && defined $metric_name) {
                    $groups{$cur_group_id}{metrics}{$metric_name} = {
                        stamp => $metric_stamp,
                        value => $metric_value,
                    };
                }
                return;
            }
        }, 'self, tagname' ],
    );

    $p->parse($html);
    $p->eof;

    return \%groups;
}

# parse the raw answer to get the (ungrouped) metrics
# (I):
# - the received answer from the push gateway server
# - an optional options hash with following keys:
#   > removeEmptyLabels, defaulting to false
# returns a hash:
#   <metric_and_labels> => { value => <value }

sub _http_parse_metrics {
	my ( $answer, $args ) = @_;
	$args //= {};
	my $removeEmptyLabels = $args->{removeEmptyLabels} // false;
	my $metrics = {};
	my @lines = split( /[\r\n]/, $answer );
	foreach my $line ( grep { !/^#/ }  @lines ){
		my @w = split( /\s+/, $line );
		msgWarn( "unexpected split count" ) if scalar( @w ) > 2;
		if( $removeEmptyLabels ){
			my @strs = split( /[{}]/, $w[0] );
			if( $strs[1] ){
				my @label_strs = split( /,/, $strs[1] );
				my @labels;
				foreach my $str ( @label_strs ){
					my @nv = split( /=/, $str );
					$nv[1] =~ s/\"//g;
					if( $nv[1] ){
						push( @labels, "$nv[0]=\"$nv[1]\"" );
					}
				}
				$w[0] = $strs[0]."{".join( ",", sort @labels )."}";
			}
		}
		$metrics->{$w[0]} = { value => $w[1] };
	}
	return $metrics;
}

# -------------------------------------------------------------------------------------------------
# get metrics from the server
# getting metrics from the server requires an authorized account

sub doListServer {
	msgOut( "listing metrics published on the Prometheus server..." );
	my $metrics_count = 0;
	my $metrics = {};
	my ( $account, $password ) = TTP::Telemetry::getCredentials();
	if( $account && $password ){
		msgVerbose( "account='$account' password is set" );
		my $url = TTP::Telemetry::var([ 'server', 'url' ]);
		if( $url ){
			# get the host and path parts, adding the query part
			my ( $scheme, $auth, $path, $query, $frag ) = uri_split( $url );
			$url = uri_join( $scheme, $auth, "$path/query" );
			my $uri = URI->new( $url );
			$uri->query_form( query => '{__name__=~".+"}' );
			my $ua = LWP::UserAgent->new();
			my $request = HTTP::Request->new( GET => $uri );
			$request->authorization_basic( $account, $password );
			msgVerbose( "requesting '$url'" );
			my $answer = $ua->request( $request );
			if( $answer->is_success ){
				$metrics = _server_parse( $answer->decoded_content );
				#print STDERR "metrics ".Dumper( $metrics );
				foreach my $name ( sort keys %{$metrics} ){
					$metrics_count += 1;
					print " m=$metrics_count: $name last_pushed=$metrics->{$name}{stamp}, last_value=$metrics->{$name}{value}".EOL;
				}
			} else {
				msgVerbose( TTP::chompDumper( $answer ));
				msgErr( "Code: ".$answer->code." MSG: ".$answer->decoded_content );
			}
		} else {
			msgErr( "telemetry server URL is not configured" );
		}
	} else {
		msgWarn( "unable to get suitable account and password to access the telemetry server" );
	}
	if( TTP::errs()){
		msgErr( "NOT OK" );
	} else {
		msgOut( "$metrics_count metric(s) found" );
	}
}

# decode the JSON answer from the server
# returns a hash:
#   <metric_name> => {
#      labels => [ name=value ],
#      value => <value>
#   }

sub _server_parse {
	my ( $answer ) = @_;
	my $json = decode_json( $answer );
	my $metrics = {};
	foreach my $it ( @{$json->{data}{result}} ){
		my $name;
		my $labels = [];
		foreach my $key ( sort keys %{$it->{metric}} ){
			if( $key eq "__name__" ){
				$name = $it->{metric}{$key};
			} else {
				my $v = $it->{metric}{$key};
				push( @{$labels}, "$key=\"$v\"" ) if $v;
			}
		}
		my $metric = $name."{".join( ",", @{$labels} )."}";
		$metrics->{$metric} = { value => $it->{value}->[1], stamp => $it->{value}->[0] };
	}
	return $metrics;
}

# -------------------------------------------------------------------------------------------------
# list metrics published through the local TextFile Collector

sub doListText {
	msgOut( "listing metrics published on the local TextFile collector..." );
	my $metrics_count = 0;
	my $enabled = TTP::Telemetry::Text::isEnabled();
	if( $enabled ){
		my $dir = TTP::Telemetry::Text::dropDir();
		if( $dir ){
			msgVerbose( "got Text-based telemetry publication drop directory '$dir'" );
			my $spec = File::Spec->catfile( $dir, "*.prom" );
			my @files = glob( $spec );
			foreach my $it ( @files ){
				my $name = basename( $it );
				$name =~ s/\.prom$//;
				my @lines = path( $it )->lines_utf8;
				# after having removed comment and empty lines, all remainings are published metrics
				foreach my $line ( grep { !/^#/ }  @lines ){
					$line =~ s/^\s*//;
					$line =~ s/\s*$//;
					if( $line ){
						$metrics_count += 1;
						my @w = split( /\s+/, $line );
						print " m=$metrics_count $w[0] last_value=$w[1]".EOL;
					}
				}
			}
		} else {
			msgErr( "unable to get the Text-based publication drop directory" );
		}
	} else {
		msgWarn( "Text-based telemetry publication is disabled by configuration" );
	}
	if( TTP::errs()){
		msgErr( "NOT OK" );
	} else {
		msgOut( "$metrics_count metric(s) found" );
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
	"http!"				=> \$opt_http,
	"http-compare!"		=> \$opt_http_compare,
	"http-groups!"		=> \$opt_http_groups,
	"text!"				=> \$opt_text,
	"server!"			=> \$opt_server,
	"limit=i"			=> \$opt_limit )){

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
msgVerbose( "got http='".( $opt_http ? 'true':'false' )."'" );
msgVerbose( "got http-compare='".( $opt_http_compare ? 'true':'false' )."'" );
msgVerbose( "got http-groups='".( $opt_http_groups ? 'true':'false' )."'" );
msgVerbose( "got text='".( $opt_text ? 'true':'false' )."'" );
msgVerbose( "got server='".( $opt_server ? 'true':'false' )."'" );
msgVerbose( "got limit='$opt_limit'" );

msgWarn( "at least one of '--http', '--http-compare', '--text' or '--server' options should be specified" ) if !$opt_http && !$opt_http_compare && !$opt_text && !$opt_server;

if( !TTP::errs()){
	doCompareHttp() if $opt_http_compare;
	doListHttp() if $opt_http;
	doListText() if $opt_text;
	doListServer() if $opt_server;
}

TTP::exit();
