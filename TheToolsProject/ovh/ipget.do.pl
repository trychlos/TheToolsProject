# @(#) display the OVH server to which the IP service is attached
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --service=<service>     the relevant applicative service [${service}]
# @(-) --ipfo=<name>           the IP OVH service name [${ipfo}]
# @(-) --[no]routed            display the currently routed server [${routed}]
# @(-) --[no]address           display the address block of the IP service [${address}]
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
use TTP::Service;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	service => '',
	ipfo => '',
	routed => 'no',
	address => 'no'
};

my $opt_service = $defaults->{service};
my $opt_ipfo = $defaults->{ip};
my $opt_routed = false;
my $opt_address = false;

# -------------------------------------------------------------------------------------------------
# display the server the service IP is attached to
# the service must be configured with a 'ovh' entry with 'ip' and 'server' OVH service names

sub doGetIP {
	msgOut( "display server to which '$opt_ipfo' FO IP is attached..." );
	my $res = false;

	my $api = TTP::Ovh::connect();
	if( $api ){
		my $result = TTP::Ovh::getContentByPath( $api, "/ip/service/$opt_ipfo" );
		print " routedTo: $result->{routedTo}{serviceName}".EOL if $opt_routed;
		print " address: $result->{ip}".EOL if $opt_address;
		$res = true;
	}

	if( $res ){
		msgOut( "success" );
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
	"service=s"			=> \$opt_service,
	"ipfo=s"			=> \$opt_ipfo,
	"routed!"			=> \$opt_routed,
	"address!"			=> \$opt_address )){

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
msgVerbose( "found service='$opt_service'" );
msgVerbose( "found ipfo='$opt_ipfo'" );
msgVerbose( "found routed='".( $opt_routed ? 'true':'false' )."'" );
msgVerbose( "found address='".( $opt_address ? 'true':'false' )."'" );

# either the OVH IP FO service name is provided, or it can be found as part of an applicative service definition
if( $opt_service ){
	if( $opt_ipfo ){
		msgErr( "only one of '--service' or '--ip' must be specified, both found" );
	} else {
		my $service = TTP::Service->new( $ttp, { service => $opt_service });
		$opt_ipfo = $service->var([ 'failover', 'ovh', 'ip' ]);
		if( $opt_ipfo ){
			msgOut( "found failover IP service: $opt_ipfo" );
		} else {
			msgErr( "unable to find a failover IP in '$opt_service' configuration" );
		}
	}
} elsif( !$opt_ipfo ){
	msgErr( "either '--service' or '--ip' must be specified, none found" );
}

# at least one of -routed or -address must be asked
my $count = 0;
$count += 1 if $opt_routed;
$count += 1 if $opt_address;
msgErr( "either '--routed' or '--address' option must be specified" ) if !$count;

if( !TTP::errs()){
	doGetIP();
}

TTP::exit();
