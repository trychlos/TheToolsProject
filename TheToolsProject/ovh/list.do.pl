# @(#) list OVH services
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]services          list subscribed services [${services}]
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
		my @missingDisplayName = ();
		my @routeUrl = ();
		my $services = TTP::Ovh::getServices( $api );
		foreach my $key ( keys %{$services} ){
			my $first = true;
			if( $services->{$key}{resource}{displayName} ){
				if( $first ){
					print "+ ";
					$first = false;
				} else {
					print "  ";
				}
				print "$key: resource.displayName: $services->{$key}{resource}{displayName}".EOL;
			} else {
				push( @missingDisplayName, $key );
			}
			if( $services->{$key}{route}{url} ){
				if( $first ){
					print "+ ";
					$first = false;
				} else {
					print "  ";
				}
				print "$key: route.url: $services->{$key}{route}{url}".EOL;
			} else {
				push( @missingRouteUrl, $key );
			}
			$count += 1;
		}
		msgOut( "$count found subscribed service(s) (".scalar @missingDisplayName." missing display name(s), ".scalar @missingRouteUrl." missing route URL(s))" );
	} else {
		msgErr( "NOT OK" );
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$ttp->{run}{help},
	"colored!"			=> \$ttp->{run}{colored},
	"dummy!"			=> \$ttp->{run}{dummy},
	"verbose!"			=> \$ttp->{run}{verbose},
	"services!"			=> \$opt_services )){

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
msgVerbose( "found services='".( $opt_services ? 'true':'false' )."'" );

if( !TTP::errs()){
	listServices() if $opt_services;
}

TTP::exit();
