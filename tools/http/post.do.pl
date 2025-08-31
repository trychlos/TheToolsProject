# @(#) run a POST on a HTTP/HTTPS endpoint
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --url=<url>             the URL to be requested [${url}]
# @(-) --field=<name=value>    a field to be posted, may be specified several times or as a comma-separated list [${field}]
# @(-) --header=<header>       output the received (case insensitive) header [${header}]
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

use LWP;

use TTP::Metric;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	url => '',
	field => '',
	header => ''
};

my $opt_url = $defaults->{url};
my @opt_fields = ();
my $opt_header = $defaults->{header};

# -------------------------------------------------------------------------------------------------
# post something to the url

sub doPost {
	msgOut( "posting to '$opt_url'..." );
	my $response = undef;
	my $status = undef;
	if( $ep->runner()->dummy()){
		msgDummy( "considering successful with status='200' sent from this node" );
		$status = '200 (dummy) successful';
	} else {
		my $ua = LWP::UserAgent->new();
		$ua->timeout( 5 );
		my $parms = {};
		foreach my $field ( @opt_fields ){
			my ( $name, $value ) = split( /=/, $field );
			$parms->{$name} = $value;
		}
		$response = $ua->post( $opt_url, $parms );
		msgVerbose( "got response: ".TTP::chompDumper( $response ));
		# find the header if asked for
		if( $opt_header ){
			my $header = $response->header( $opt_header );
			print "  $opt_header: $header".EOL;
		}
		$status = $response->status_line;
		#msgVerbose( 'is_success: '.$response->is_success());
		#msgVerbose( 'code: '.$response->code );
		#msgVerbose( 'message: '.$response->message );
		#msgVerbose( 'headers: '.TTP::chompDumper( $response->headers ));
		#msgVerbose( 'content: '.$response->decoded_content );
	}
	print "  $status".EOL;
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
	"field=s"			=> \@opt_fields,
	"header=s"			=> \$opt_header )){

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
@opt_fields = split( /,/, join( ',', @opt_fields ));
msgVerbose( "got fields=[".join( ',', @opt_fields )."]" );
msgVerbose( "got header='$opt_header'" );

# url is mandatory
msgErr( "url is required, but is not specified" ) if !$opt_url;

if( !TTP::errs()){
	doPost() if $opt_url;
}

TTP::exit();
