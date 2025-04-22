# @(#) list the published metrics
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]mqtt              limit to metrics published on the MQTT bus [${mqtt}]
# @(-) --[no]http              limit to metrics published on the PushGateway [${http}]
# @(-) --[no]text              limit to metrics published on the TextFile collector [${text}]
# @(-) --[no]server            get metrics from the server [${server}]
# @(-) --limit=<limit>         only list first <limit> metric [${limit}]
#
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

use strict;
use utf8;
use warnings;

use Data::Dumper;
use HTML::Parser;
use HTTP::Request;
use LWP::UserAgent;
use URI::Split qw( uri_split uri_join );

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	mqtt => 'no',
	http => 'no',
	text => 'no',
	server => 'no',
	limit => -1
};

my $opt_mqtt = false;
my $opt_http = false;
my $opt_text = false;
my $opt_server = false;
my $opt_limit = $defaults->{limit};

# -------------------------------------------------------------------------------------------------
# list metrics published on the PushGateway

sub doListHttp {
	msgOut( "listing metrics published on the HTTP PushGateway..." );
	my $count = 0;
	my $groups = {};
	my $var = $ep->var([ 'Telemetry', 'withHttp', 'enabled' ]);
	my $enabled = defined( $var ) ? $var : false;
	if( $enabled ){
		$var = $ep->var([ 'Telemetry', 'withHttp', 'url' ]);
		my $url = defined( $var ) ? $var : undef;
		if( $url ){
			# get the host part only
			my ( $scheme, $auth, $path, $query, $frag ) = uri_split( $url );
			$url = uri_join( $scheme, $auth );
			msgVerbose( "requesting '$url'" );
			my $ua = LWP::UserAgent->new();
			my $request = HTTP::Request->new( GET => $url );
			#$request->content( $body );
			my $answer = $ua->request( $request );
			if( $answer->is_success ){
				$count = _parse( $answer->decoded_content, $groups );
				foreach my $id ( sort { $a <=> $b } keys %{$groups} ){
					my $labels = [];
					#print Dumper( $groups->{$id} );
					foreach my $it ( sort keys %{$groups->{$id}} ){
						push( @{$labels}, "$it=$groups->{$id}->{$it}" );
					}
					print " $id: ".join( ',', @{$labels} ).EOL;
				}
			} else {
				msgVerbose( Dumper( $answer ));
				msgErr( __PACKAGE__."::_http_publish() Code: ".$answer->code." MSG: ".$answer->decoded_content );
			}
		} else {
			msgErr( "PushGateway HTTP URL is not configured" );
		}
	} else {
		msgErr( "PushGateway is disabled by configuration" );
	}
	if( TTP::errs()){
		msgErr( "NOT OK" );
	} else {
		msgOut( "$count metric group(s) found" );
	}
}

sub _parse {
	my ( $html, $groups ) = @_;
	my $id = undef;
	my $indiv = false;
	my $inspan = false;
	my $p = HTML::Parser->new(
		start_h => [ sub {
			my ( $self, $tagname, $attr ) = @_;
			# identify the metric group
			if( $tagname eq 'div' ){
				#print Dumper( $attr );
				return if scalar keys %{$attr} != 2;
				return if !$attr->{id} or $attr->{id} !~ m/^group-panel-/;
				return if $attr->{class} ne 'card-header';
				$id = $attr->{id};
				$id =~ s/group-panel-//;
				$groups->{$id} = {};
				$indiv = true;
			# the span contains each label
			} elsif( $tagname eq 'span' ){
				return if !$indiv;
				return if scalar keys %{$attr} != 1;
				return if $attr->{class} !~ m/badge/;
				$inspan = true;
			}
		}, 'self, tagname, attr' ],

		end_h => [ sub {
			my ( $self, $tagname ) = @_;
			if( $tagname eq 'span' ){
				$inspan = false;
			} elsif( $tagname eq 'div' ){
				$indiv = false;
				$id = undef;
				$self->eof() if scalar( keys %{$groups} ) >= $opt_limit && $opt_limit >= 0;
			}
		}, 'self, tagname' ],

		text_h => [ sub {
			my ( $self, $text ) = @_;
			if( $indiv && $inspan && $id ){
				my @w = split( /=/, $text );
				my $v = $w[1];
				$v =~ s/^"//;
				$v =~ s/"$//;
				$groups->{$id}->{$w[0]} = $v;
			}
		}, 'self, text' ]
	);
	$p->parse( $html );
	return scalar( keys %{$groups} );
}

# -------------------------------------------------------------------------------------------------
# list metrics published on the MQTT bus

sub doListMqtt {
	msgOut( "listing metrics published on the MQTT bus..." );
}

# -------------------------------------------------------------------------------------------------
# get metrics from the server

sub doListServer {
	msgOut( "listing metrics published on the Prometheus server..." );
}

# -------------------------------------------------------------------------------------------------
# list metrics published through the TextFile Collector

sub doListText {
	msgOut( "listing metrics published on the MQTT bus..." );
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> sub { $ep->runner()->help( @_ ); },
	"colored!"			=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"			=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"			=> sub { $ep->runner()->verbose( @_ ); },
	"mqtt!"				=> \$opt_mqtt,
	"http!"				=> \$opt_http,
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
msgVerbose( "got mqtt='".( $opt_mqtt ? 'true':'false' )."'" );
msgVerbose( "got http='".( $opt_http ? 'true':'false' )."'" );
msgVerbose( "got text='".( $opt_text ? 'true':'false' )."'" );
msgVerbose( "got server='".( $opt_server ? 'true':'false' )."'" );
msgVerbose( "got limit='$opt_limit'" );

msgWarn( "at least one of '--mqtt', '--http', '--text' or '--server' options should be specified" ) if !$opt_mqtt && !$opt_http && !$opt_text && !$opt_server;

if( !TTP::errs()){
	doListMqtt() if $opt_mqtt;
	doListHttp() if $opt_http;
	doListText() if $opt_text;
	doListServer() if $opt_server;
}

TTP::exit();
