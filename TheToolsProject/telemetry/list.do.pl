# @(#) list published metrics
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]pushgateway       list metrics published on the PushGateway [${push}]
# @(-) --limit=<limit>         only list first <limit> metric [${limit}]
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

use HTML::Parser;
use HTTP::Request;
use LWP::UserAgent;
use URI::Split qw( uri_split uri_join );

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	push => 'no',
	limit => -1
};

my $opt_push = false;
my $opt_limit = $defaults->{limit};

# -------------------------------------------------------------------------------------------------
# list metrics published on the PushGateway

sub doListPush {
	msgOut( "listing metrics published on the PushGateway..." );
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
			$request->content( $body );
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
				return if scalar keys %{$attr} != 2;
				return if $attr->{id} !~ m/^group-panel-/;
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

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$ep->{run}{help},
	"colored!"			=> \$ep->{run}{colored},
	"dummy!"			=> \$ep->{run}{dummy},
	"verbose!"			=> \$ep->{run}{verbose},
	"push!"				=> \$opt_push,
	"limit=i"			=> \$opt_limit )){

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
msgVerbose( "found push='".( $opt_push ? 'true':'false' )."'" );
msgVerbose( "found limit='$opt_limit'" );

msgWarn( "will not list anything as '--push' option is not set" ) if !$opt_push;

if( !TTP::errs()){
	doListPush() if $opt_push;
}

TTP::exit();
