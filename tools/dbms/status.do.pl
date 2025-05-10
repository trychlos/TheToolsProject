# @(#) test the status of the databases of the service
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --service=<name>        acts on the named service [${service}]
# @(-) --database=<name>       database name [${database}]
# @(-) --[no]state             get state [${state}]
# @(-) --[no]mqtt              publish the metrics to the (MQTT-based) messaging system [${mqtt}]
# @(-) --[no]http              publish the metrics to the (HTTP-based) Prometheus PushGateway system [${http}]
# @(-) --[no]text              publish the metrics to the (text-based) Prometheus TextFile Collector system [${text}]
# @(-) --prepend=<name=value>  label to be appended to the telemetry metrics, may be specified several times or as a comma-separated list [${prepend}]
# @(-) --append=<name=value>   label to be appended to the telemetry metrics, may be specified several times or as a comma-separated list [${append}]
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

use Scalar::Util qw( looks_like_number );
use URI::Escape;

use TTP::Metric;
use TTP::Node;
use TTP::Service;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	service => '',
	database => '',
	state => 'no',
	mqtt => 'no',
	http => 'no',
	text => 'no',
	prepend => '',
	append => ''
};

my $opt_service = $defaults->{service};
my $opt_database = $defaults->{database};
my $opt_state = false;
my $opt_mqtt = false;
my $opt_http = false;
my $opt_text = false;
my @opt_prepends = ();
my @opt_appends = ();

# the node which hosts the requested service
my $objNode = undef;
# the service object
my $objService = undef;
# the DBMS object
my $objDbms = undef;

# list of databases to be checked
my $databases = [];

# -------------------------------------------------------------------------------------------------
# get the state of all databases of the specified service, or specified in the command-line
# Also publish as a labelled telemetry the list of possible values
# (same behavior than for example Prometheus windows_exporter which display the status of services)
# We so publish:
# - on MQTT, two payloads as .../state and .../state_desc
# - to HTTP, ten numerical payloads, only one having a '1' value

sub doState {
	msgOut( "get database(s) state for '$opt_service'..." );
	my $list = [];
	my $code = 0;
	my $dummy = $ep->runner()->dummy() ? "-dummy" : "-nodummy";
	my $verbose = $ep->runner()->verbose() ? "-verbose" : "-noverbose";
	my $result = undef;
	foreach my $db ( @{$databases} ){
		msgOut( "database '$db'" );
		my $result = $objDbms->databaseState( $db );
		# due to the differences between the two publications contents, publish separately
		# -> stdout
		foreach my $key ( sort keys %{$result} ){
			print " $key: $result->{$key}".EOL;
		}
		# -> mqtt: publish a single string metric
		#    e.g. state: online
		my @labels = ( @opt_prepends, "environment=".$ep->node()->environment());
		push( @labels, "service=".$opt_service );
		@labels = ( @labels, "command=".$ep->runner()->command(), "verb=".$ep->runner()->verb(), "database=$db", @opt_appends );
		TTP::Metric->new( $ep, {
			name => 'state',
			value => $result->{state_desc},
			labels => \@labels
		})->publish({
			mqtt => $opt_mqtt
		});
		# -> http/text: publish a metric per known sqlState
		#    e.g. state=emergency 0
		my $states = $objDbms->dbStatuses();
		foreach my $key ( keys( %{$states} )){
			my @labels = ( @opt_prepends, "environment=".$ep->node()->environment());
			push( @labels, "service=".$opt_service );
			@labels = ( @labels, "command=".$ep->runner()->command(), "verb=".$ep->runner()->verb(), "database=$db", "state=$states->{$key}", @opt_appends );
			TTP::Metric->new( $ep, {
				name => 'dbms_state',
				value => "$key" eq "$result->{state}" ? 1 : 0,
				type => 'gauge',
				help => 'Database status',
				labels => \@labels
			})->publish({
				http => $opt_http,
				text => $opt_text
			});
		}
	}
	if( $code ){
		msgErr( "NOT OK" );
	} else {
		msgOut( "done" );
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
	"database=s"		=> \$opt_database,
	"state!"			=> \$opt_state,
	"mqtt!"				=> \$opt_mqtt,
	"http!"				=> \$opt_http,
	"text!"				=> \$opt_text,
	"prepend=s@"		=> \@opt_prepends,
	"append=s@"			=> \@opt_appends )){

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
msgVerbose( "got database='$opt_database'" );
msgVerbose( "got state='".( $opt_state ? 'true':'false' )."'" );
msgVerbose( "got mqtt='".( $opt_mqtt ? 'true':'false' )."'" );
msgVerbose( "got http='".( $opt_http ? 'true':'false' )."'" );
msgVerbose( "got text='".( $opt_text ? 'true':'false' )."'" );
@opt_prepends = split( /,/, join( ',', @opt_prepends ));
msgVerbose( "got prepends='".join( ',', @opt_prepends )."'" );
@opt_appends = split( /,/, join( ',', @opt_appends ));
msgVerbose( "got appends='".join( ',', @opt_appends )."'" );

# must have --service option
# find the node which hosts this service in this same environment (should be at most one)
# and check that the service is DBMS-aware
if( $opt_service ){
	$objNode = TTP::Node->findByService( $ep->node()->environment(), $opt_service );
	if( $objNode ){
		msgVerbose( "got hosting node='".$objNode->name()."'" );
		$objService = TTP::Service->new( $ep, { service => $opt_service });
		$objDbms = $objService->newDbms({ node => $objNode });
	}
} else {
	msgErr( "'--service' option is mandatory, but is not specified" );
}

# database(s) can be specified in the command-line, or can come from the service
if( $opt_database ){
	push( @{$databases}, $opt_database );
} elsif( $opt_service ){
	$databases = $objDbms->getDatabases();
	msgVerbose( "setting databases='".join( ', ', @{$databases} )."'" );
}

# all databases must exist in the instance
if( scalar @{$databases} ){
	foreach my $db ( @{$databases} ){
		my $exists = $objDbms->databaseExists( $db );
		if( !$exists ){
			msgErr( "database '$db' doesn't exist in the '$opt_service' DBMS instance" );
		}
	}
} else {
	msgErr( "'--database' option is required (or '--service'), but none is specified" );
}

# if no option is given, have a warning message
msgWarn( "no status has been requested, exiting gracefully" ) if !$opt_state;

if( !TTP::errs()){
	doState() if $opt_state;
}

TTP::exit();
