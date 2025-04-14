# @(#) switch an IP service to another server
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --service=<service>     the relevant applicative service [${service}]
# @(-) --ipfo=<name>           the IP OVH service name [${ipfo}]
# @(-) --to=<server>           the target server OVH service name [${to}]
# @(-) --[no]wait              wait until the IP is said routed [${wait}]
# @(-) --url=<url>             the URL to be tested for X-Sent-By header [${url}]
# @(-) --sender=<sender>       the expected sender searched in X-Sent-By header [${sender}]
# @(-) --timeout=<seconds>     wait timeout [${timeout}]
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

use URI::Escape;
use Time::Moment;

use TTP::Ovh;
use TTP::Service;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	service => '',
	ipfo => '',
	to => '',
	wait => 'no',
	url => '',
	sender => '',
	timeout => 300
};

my $opt_service = $defaults->{service};
my $opt_ipfo = $defaults->{ip};
my $opt_to = $defaults->{to};
my $opt_wait = false;
my $opt_url = $defaults->{url};
my $opt_sender = $defaults->{sender};
my $opt_timeout = $defaults->{timeout};

# -------------------------------------------------------------------------------------------------
# display the server the service IP is attached to
# the service must be configured with a 'ovh' entry with 'ip' and 'server' OVH service names

sub doSwitchIP {
	msgOut( "switching '$opt_ipfo' FO IP to '$opt_to' host..." );
	my $res = false;
	my $dummy = $ep->runner()->dummy() ? "-dummy" : "-nodummy";
	my $verbose = $ep->runner()->verbose() ? "-verbose" : "-noverbose";

	# check that the requested desired server is not already the routed one
	my $command = "ovh.pl ipget -ipfo $opt_ipfo -routed -nocolored $dummy $verbose";
	my $stdout = TTP::filter( `$command` );
	my @words = split( /\s+/, $stdout->[0] );
	my $current = $words[1];
	if( $current eq $opt_to ){
		msgWarn( "the specified '$opt_ipfo' is already routed to '$opt_to'" );
		$res = true;
	} else {
		msgVerbose( "current routed server is '$current'" );
		my $api = TTP::Ovh::connect();
		if( $api ){
			# we need the IP block
			$command = "ovh.pl ipget -ip $opt_ipfo -address -nocolored $dummy $verbose";
			$stdout = TTP::filter( `$command` );
			@words = split( /\s+/, $stdout->[0] );
			my $ipAddress = $words[1];
			msgVerbose( "IP address is '$ipAddress'" );
			# check that the requested target server is willing to accept this IP - answer is empty if ok
			my $url = "/dedicated/server/$opt_to/ipCanBeMovedTo?ip=".uri_escape( $ipAddress );
			my $answer = TTP::Ovh::getAnswerByPath( $api, $url );
			# ask for the move
			if( $answer->status() == 200 && !$answer->content()){
				$url = "/dedicated/server/$opt_to/ipMove";
				if( $ep->runner()->dummy()){
					msgDummy( "considering '$url' done and successful" );
					$res = true;
				} else {
					$res = _switchAndWait( $api, $url, $ipAddress );
				}
			} else {
				msgErr( "the target server is not willing to get the '$opt_ipfo' address service" );
			}
		}
	}
	if( $res ){
		msgOut( "successfully switched to $opt_to" );
	} else {
		msgErr( "NOT OK" );
	}
}

# -------------------------------------------------------------------------------------------------
# display the server the service IP is attached to
# the service must be configured with a 'ovh' entry with 'ip' and 'server' OVH service names

sub _switchAndWait {
	my ( $api, $url, $ip ) = @_;
	my $res = false;
	my $answer = TTP::Ovh::postByPath( $api, $url, { ip => $ip });
	my $dummy = $ep->runner()->dummy() ? "-dummy" : "-nodummy";
	my $verbose = $ep->runner()->verbose() ? "-verbose" : "-noverbose";
	if( $answer->status() == 200 ){
		if( $opt_wait ){
			my $start = Time::Moment->now->epoch;
			my $end = false;
			my $timeout = false;
			print "waiting for IP move";
			do {
				print ".";
				sleep 1;
				my $command = "ovh.pl ipget -ip $opt_ipfo -routed -nocolored $dummy $verbose";
				my $stdout = TTP::filter( `$command` );
				msgLog( "filter() returns: '".Dumper( $stdout )."'" );
				my @words = split( /\s+/, $stdout->[0] );
				my $current = $words[1];
				if( $current eq $opt_to ){
					$end = true;
				} elsif( Time::Moment->now->epoch - $start > $opt_timeout ){
					$timeout = true;
				}
			} while( !$end && !$timeout );
			print EOL;
			if( $end ){
				msgOut( "OVH API says that IP is switched after ".( Time::Moment->now->epoch - $start )." sec." );
				if( $opt_url ){
					print "waiting for target machine answer";
					$end = false;
					do {
						print ".";
						sleep 1;
						my $command = "http.pl get -url $opt_url -header X-Sent-By -accept [1-3].. -nocolored $dummy $verbose";
						my $stdout = TTP::filter( `$command` );
						msgLog( "filter() returns: '".Dumper( $stdout )."'" );
						my @words = split( /\s+/, $stdout->[0] );
						my $line = $words[1];
						if( $line eq $opt_sender ){
							$end = true;
						} elsif( Time::Moment->now->epoch - $start > $opt_timeout ){
							$timeout = true;
						}
					} while( !$end && !$timeout );
					print EOL;
					if( $end ){
						msgOut( "URL is actually switched after ".( Time::Moment->now->epoch - $start )." sec." );
					}
				}
				$res = true;
			}
			if( $timeout ){
				msgWarn( "timeout ($opt_timeout sec.) while waiting for actual move, still setting result='true'" );
				$res = true;
			}
		} else {
			msgVerbose( "do not wait for actual move" );
			$res = true;
		}
	} else {
		msgErr( "an error occurred when requesting the move: ".$answer->error());
	}
	return $res;
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> sub { $ep->runner()->help( @_ ); },
	"colored!"			=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"			=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"			=> sub { $ep->runner()->verbose( @_ ); },
	"service=s"			=> \$opt_service,
	"ipfo=s"			=> \$opt_ipfo,
	"to=s"				=> \$opt_to,
	"wait!"				=> \$opt_wait,
	"url=s"				=> \$opt_url,
	"sender=s"			=> \$opt_sender,
	"timeout=i"			=> \$opt_timeout )){

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
msgVerbose( "got service='$opt_service'" );
msgVerbose( "got ipfo='$opt_ipfo'" );
msgVerbose( "got to='$opt_to'" );
msgVerbose( "got wait='".( $opt_wait ? 'true':'false' )."'" );
msgVerbose( "got url='$opt_url'" );
msgVerbose( "got sender='$opt_sender'" );
msgVerbose( "got timeout='$opt_timeout'" );

# either the OVH IP FO service name is provided, or it can be found as part of an applicative service definition
if( $opt_service ){
	if( $opt_ipfo ){
		msgErr( "only one of '--service' or '--ip' must be specified, both found" );
	} else {
		my $service = TTP::Service->new( $ep, { service => $opt_service });
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

msgErr( "target server is mandatory, not specified" ) if !$opt_to;
msgWarn( "waiting for an URL doesn't have sense without an expected sender" ) if $opt_wait && $opt_url && !$opt_sender;
msgWarn( "specifying an expected sender doesn't have sense if we do not wait for and URL" ) if $opt_wait && $opt_sender && !$opt_url;
msgWarn( "specifying an expected sender or an URL doesn't have sense without waiting for them" ) if ( $opt_sender || $opt_url ) && !$opt_wait;

if( !TTP::errs()){
	doSwitchIP();
}

TTP::exit();
