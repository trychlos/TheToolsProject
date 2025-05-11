# @(#) display the machine which holds the live production of this service
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --service=<name>        the named service [${service}]
# @(-) --environment=<type>    the searched for environment [${environment}]
# @(-) --[no]next              also search for next machine(s) [${next}]
# @(-) --[no]mqtt              publish MQTT telemetry [${mqtt}]
# @(-) --[no]http              publish HTTP telemetry [${http}]
#
# @(@) This script relies on the 'status/live' entry in the JSON configuration file.
# @(@) *All* machines of the environment are scanned until a 'status/live' command has been found for the service.
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

use TTP::Service;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	service => '',
	environment => 'X',
	next => 'no',
	mqtt => 'no',
	http => 'no'
};

my $opt_service = $defaults->{service};
my $opt_environment = $defaults->{environment};
my $opt_next = false;
my $opt_mqtt = false;
my $opt_http = false;

# -------------------------------------------------------------------------------------------------
# Display the 'live' machine for a service
# If asked for, also display the next one
# and publish a telemetry if opted for

sub getLive {
	msgOut( "displaying live '$opt_environment' machine for '$opt_service' service..." );
	my $dummy = $ep->runner()->dummy() ? "-dummy" : "-nodummy";
	my $verbose = $ep->runner()->verbose() ? "-verbose" : "-noverbose";
	my $service = TTP::Service->new( $ep, { service => $opt_service });
	my $command;
	if( $service ){
		$command = $service->var([ 'status', 'live' ]);
	}
	if( $command ){
		my $stdout = TTP::filter( $command );
		if( !scalar( @{$stdout} )){
			msgWarn( "the service seems unable to identify its own live machine, saying there is none (maybe is it dead ?)" );
		} else {
			my @live = grep( /X-Sent-By/, @{$stdout} );
			my $live = $live[0];
			$live =~ s/^\s*X-Sent-By:\s*//;
			print "  live: $live".EOL;
			# get all hosts for this service and this environment
			my @hosts = ();
			my @nexts;
			$command = "services.pl list -service $opt_service -identifier $opt_environment -machines -nocolored $dummy $verbose";
			$stdout = TTP::filter( $command );
			foreach my $it ( @{$stdout} ){
				my @words = split( /\s+/, $it );
				push( @hosts, $words[scalar( @words )-1] );
			}
			# compute next hosts
			if( $opt_next ){
				@nexts = $live ? grep( !/$live/, @hosts ) : @hosts;
				foreach my $next ( @nexts ){
					print "  next: $next".EOL;
				}
			}
			# telemetry
			my $labels = "-append environment=$opt_environment -append service=$opt_service -append command=".$ep->runner()->command()." -append verb=".$ep->runner()->verb();
			my $next = join( ',', @nexts );
			if( $opt_mqtt ){
				# topic is HOST/telemetry/environment/<ENVIRONMENT>/service/<SERVICE>/command/<COMMAND>/verb/<VERB>/machine/live=live
				# topic is HOST/telemetry/environment/<ENVIRONMENT>/service/<SERVICE>/command/<COMMAND>/verb/<VERB>/machine/backup=next
				my $mqtt_live = $live || 'none';
				$command = "telemetry.pl publish -metric live $labels -value=$mqtt_live -mqtt -mqttPrefix machine/ -nohttp $dummy $verbose";
				TTP::commandExec( $command );
				if( $opt_next && scalar @nexts ){
					$command = "telemetry.pl publish -metric backup $labels -value=$next -mqtt -mqttPrefix machine/ -nohttp $dummy $verbose";
					TTP::commandExec( $command );
				}
			}
			if( $opt_http ){
				# set the value "1" on the live metric when we have found one (i.e. is not undef)
				# we publish here one metric per host for the service and the environment with
				# - either a 'live' label if the host if the live host
				# - or a 'backup' label if the host is a backup host
				my $runningHost = TTP::nodeName();
				msgVerbose( "runningHost is '$runningHost'" );
				foreach my $host ( @hosts ){
					my $value = ( $live && $live eq $host ) ? "1" : "0";
					my $httpLabels = $labels;
					my $http_live = $live || 'none';
					$httpLabels .= " -append live=$host" if $value eq "1";
					$httpLabels .= " -append backup=$host" if grep( /$host/, @nexts );
					$command = "telemetry.pl publish -metric ttp_service_machine $httpLabels -value=$value -nomqtt -http -type gauge $dummy $verbose";
					TTP::commandExec( $command );
				}
			}
			msgOut( "done" );
		}
	} else {
		msgErr( "the service doesn't define any 'status/live' command" );
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
	"service=s"			=> \$opt_service,
	"environment=s"		=> \$opt_environment,
	"next!"				=> \$opt_next,
	"mqtt!"				=> \$opt_mqtt,
	"http!"				=> \$opt_http )){

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
msgVerbose( "got environment='$opt_environment'" );
msgVerbose( "got next='".( $opt_next ? 'true':'false' )."'" );
msgVerbose( "got mqtt='".( $opt_mqtt ? 'true':'false' )."'" );
msgVerbose( "got http='".( $opt_http ? 'true':'false' )."'" );

msgErr( "'--service' service name must be specified, but is not found" ) if !$opt_service;
msgErr( "'--environment' environment type must be specified, but is not found" ) if !$opt_environment;

if( !TTP::errs()){
	getLive();
}

TTP::exit();
