# @(#) get and publish some databases telemetry data
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --service=<name>        acts on the named service [${service}]
# @(-) --database=<name>       database name [${database}]
# @(-) --[no]dbsize            get databases size for the specified instance [${dbsize}]
# @(-) --[no]tabcount          get tables rows count for the specified database [${tabcount}]
# @(-) --limit=<limit>         limit the count of published metrics [${limit}]
# @(-) --[no]mqtt              publish the metrics to the (MQTT-based) messaging system [${mqtt}]
# @(-) --[no]http              publish the metrics to the (HTTP-based) Prometheus PushGateway system [${http}]
# @(-) --[no]text              publish the metrics to the (text-based) Prometheus TextFile Collector system [${text}]
# @(-) --prepend=<name=value>  label to be appended to the telemetry metrics, may be specified several times or as a comma-separated list [${prepend}]
# @(-) --append=<name=value>   label to be appended to the telemetry metrics, may be specified several times or as a comma-separated list [${append}]
#
# @(@) When limiting the published messages, be conscious that the '--dbsize' option provides 6 metrics per database.
# @(@) This verb manages itself different telemetry prefixes depending of the targeted system.
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
	dbsize => 'no',
	tabcount => 'no',
	limit => -1,
	mqtt => 'no',
	http => 'no',
	text => 'no',
	prepend => '',
	append => ''
};

my $opt_service = $defaults->{service};
my $opt_database = $defaults->{database};
my $opt_dbsize = false;
my $opt_tabcount = false;
my $opt_limit = $defaults->{limit};
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
# publish the databases sizes
# if a service has been specified, only consider the databases of this service
# if only an instance has been specified, then all databases of this instance are considered

sub doDbSize {
	msgOut( "publishing databases size on '$opt_service'..." );
	my $dbcount = 0;
	my $mqttcount = 0;
	my $httpcount = 0;
	my $textcount = 0;
	my $dummy = $ep->runner()->dummy() ? "-dummy" : "-nodummy";
	my $verbose = $ep->runner()->verbose() ? "-verbose" : "-noverbose";
	foreach my $db ( @{$databases} ){
		last if $dbcount >= $opt_limit && $opt_limit >= 0;
		msgOut( "database '$db'" );
		$dbcount += 1;
		my $set = $objDbms->databaseSize( $db );
		# -> stdout
		foreach my $key ( sort keys %{$set} ){
			print " $key: $set->{$key}".EOL;
		}
		# we got several metrics per database
		# that we publish separately as mqtt-based names are slightly different from Prometheus ones
		my @labels = ( @opt_prepends,
			"environment=".( $ep->node()->environment() || '' ), "service=".$opt_service, "command=".$ep->runner()->command(), "verb=".$ep->runner()->verb(), "database=$db", @opt_appends );
		foreach my $key ( keys %{$set} ){
			TTP::Metric->new( $ep, {
				name => $key,
				value => $set->{$key},
				type => 'gauge',
				help => 'Database used space',
				labels => \@labels
			})->publish({
				mqtt => $opt_mqtt,
				mqttPrefix => 'dbsize/',
				http => $opt_http,
				httpPrefix => 'dbms_dbsize_',
				text => $opt_text,
				textPrefix => 'dbms_dbsize_'
			});
			$mqttcount += 1 if $opt_mqtt;
			$httpcount += 1 if $opt_http;
			$textcount += 1 if $opt_text;
			last if $dbcount >= $opt_limit && $opt_limit >= 0;
		}
	}
	if( TTP::errs()){
		msgErr( "NOT OK" );
	} else {
		msgOut( "got $dbcount database size(s)" );
		msgOut( "published $mqttcount metric(s) to MQTT bus, $httpcount metric(s) to HTTP gateway, $textcount metric(s) to text files" );
		msgOut( "done" );
	}
}

# -------------------------------------------------------------------------------------------------
# publish all tables rows count for the specified database(s)

sub doTablesCount {
	my $dbcount = 0;
	my $tabcount = 0;
	my $mqttcount = 0;
	my $httpcount = 0;
	my $textcount = 0;
	my $dummy = $ep->runner()->dummy() ? "-dummy" : "-nodummy";
	my $verbose = $ep->runner()->verbose() ? "-verbose" : "-noverbose";
	foreach my $db ( @{$databases} ){
		msgOut( "publishing tables rows count on '$opt_service\\$db'..." );
		$dbcount += 1;
		my $command = "dbms.pl list -service $opt_service -database $db -list-tables -nocolored $dummy $verbose";
		# TTP::commandExec() verbose-logs stdout, stderr and return code
		# TTP::filter() returns filtered stdout
		my $tables = TTP::filter( $command );
		foreach my $tab ( @{$tables} ){
			$tabcount += 1;
			msgOut( " table '$tab'" );
			my $rowscount = $objDbms->getTableRowsCount( $db, $tab );
			# mqtt and http/text have different names
			# mqtt topic: <node>/telemetry/<environment>/<service>/<command>/<verb>/<instance>/<database>/rowscount/<table>
			# mqtt value: <table_rows_count>
			if( $opt_mqtt ){
				my @labels = ( @opt_prepends,
					"environment=".( $ep->node()->environment() || '' ), "service=".$opt_service, "command=".$ep->runner()->command(), "verb=".$ep->runner()->verb(), "database=$db", @opt_appends );
				TTP::Metric->new( $ep, {
					name => $tab,
					value => $rowscount,
					labels => \@labels
				})->publish({
					mqtt => $opt_mqtt,
					mqttPrefix => 'rowscount/'
				});
				$mqttcount += 1 if $opt_mqtt;
			}
			# http labels += table=<table>
			# http value: <table_rows_count>
			if( $opt_http || $opt_text ){
				my @labels = ( @opt_prepends,
					"environment=".( $ep->node()->environment() || '' ), "service=".$opt_service, "command=".$ep->runner()->command(), "verb=".$ep->runner()->verb(), "database=$db", "table=$tab", @opt_appends );
				TTP::Metric->new( $ep, {
					name => 'rowscount',
					value => $rowscount,
					type => 'gauge',
					help => 'Table rows count',
					labels => \@labels
				})->publish({
					http => $opt_http,
					httpPrefix => 'dbms_table_',
					text => $opt_text,
					textPrefix => 'dbms_table_'
				});
				$httpcount += 1 if $opt_http;
				$textcount += 1 if $opt_text;
			}
			last if $tabcount >= $opt_limit && $opt_limit >= 0;
		}
	}
	if( TTP::errs()){
		msgErr( "NOT OK" );
	} else {
		msgOut( "got $tabcount tables rows counts for $dbcount database(s)" );
		msgOut( "published $mqttcount metric(s) to MQTT bus, $httpcount metric(s) to HTTP gateway, $textcount metric(s) to text files" );
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
	"dbsize!"			=> \$opt_dbsize,
	"tabcount!"			=> \$opt_tabcount,
	"limit=i"			=> \$opt_limit,
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
msgVerbose( "got dbsize='".( $opt_dbsize ? 'true':'false' )."'" );
msgVerbose( "got tabcount='".( $opt_tabcount ? 'true':'false' )."'" );
msgVerbose( "got limit='$opt_limit'" );
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
if( !$opt_dbsize && !$opt_tabcount ){
	msgWarn( "no measure has been requested" );

}

# also warns if no telemetry is to be published
if( !$opt_mqtt && !$opt_http && !$opt_text ){
	msgWarn( "no telemetry has been requested" );

}

if( !TTP::errs()){
	doDbSize() if $opt_dbsize;
	doTablesCount() if $opt_tabcount;
}

TTP::exit();
