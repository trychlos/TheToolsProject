# @(#) list OVH services
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]services          list subscribed services [${services}]
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

use TTP::Ovh;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	services => 'no'
};

my $opt_services = false;

# -------------------------------------------------------------------------------------------------
# list all the subscribed services

sub listServices {
	msgOut( "displaying subscribed services..." );
	my $api = TTP::Ovh::connect();
	if( $api ){
		# full identity
		#my $list = TTP::Ovh::get( $api, "/me" );
		#print "me".EOL.Dumper( $list );

		# three dedicated servers at that time
		#my $list = TTP::Ovh::get( $api, "/dedicated/server" );
		#print "dedicated/server".EOL.Dumper( $list );

		# all used ipv4+ipv6 addresses
		#my $list = TTP::Ovh::get( $api, "/ip" );
		#print "ip".EOL.Dumper( $list );

		# a list of services ids
		my $count = 0;
		my @missingName = ();
		my @missingRouteUrl = ();
		my $services = TTP::Ovh::getServices( $api );
		# build an array of just to-be-displayed fields
		my $array = [];
		foreach my $it ( @{$services} ){
			my $hash = {};
			$hash->{id} = $it->{id};
			if( $it->{resource}{name} ){
				$hash->{resource_name} = $it->{resource}{name};
			} else {
				push( @missingName, $it->{id} );
			}
			if( $it->{route}{url} ){
				$hash->{route_URL} = $it->{route}{url};
			} else {
				push( @missingRouteUrl, $it->{id} );
			}
			$hash->{creationDate} = $it->{creationDate};
			push( @{$array}, $hash );
			$count += 1;
		}
		TTP::displayTabular( $array );
		msgOut( "$count found subscribed service(s) (".scalar @missingName." missing display name(s), ".scalar @missingRouteUrl." missing route URL(s))" );
	} else {
		msgErr( "NOT OK" );
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
	"services!"			=> \$opt_services )){

		msgOut( "try '".$ep->runner()->command()." ".$ep->runner()->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $ep->runner()->help()){
	$ep->runner()->verbHelp( $defaults );
	TTP::exit();
}

msgVerbose( "got colored='".( $ep->runner()->colored() ? 'true':'false' )."'" );
msgVerbose( "got dummy='".( $ep->runner()->dummy() ? 'true':'false' )."'" );
msgVerbose( "got verbose='".( $ep->runner()->verbose() ? 'true':'false' )."'" );
msgVerbose( "got services='".( $opt_services ? 'true':'false' )."'" );

if( !TTP::errs()){
	listServices() if $opt_services;
}

TTP::exit();
