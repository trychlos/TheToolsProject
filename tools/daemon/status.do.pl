# @(#) get the running status of a TTP daemon
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --json=<name>           the JSON file which characterizes this daemon [${json}]
# @(-) --name=<name>           the daemon name [${name}]
# @(-) --port=<port>           the port number to address [${port}]
# @(-) --[no]http              publish the metrics to the (HTTP-based) Prometheus PushGateway system [${http}]
# @(-) --metric=<metric>       the metric to be published [${metric}]
# @(-) --label=<name=value>    label(s) to be added to the published metric, may be specified several times or as comma-separated strings [${label}]
#
# @(@) Published telemetries exhibit the very same metrics than those periodically advertised by the daemon itself.
# @(@) daemon.pl command and all its verbs only work on the local node.
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

use File::Spec;

use TTP::DaemonConfig;
use TTP::Finder;
use TTP::Metric;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	json => '',
	name => '',
	port => '',
	http => 'no',
	metric => 'service_daemon',
	label => ''
};

my $opt_json = $defaults->{json};
my $opt_name = $defaults->{name};
my $opt_port = -1;
my $opt_port_set = false;
my $opt_http = false;
my $opt_metric = $defaults->{metric};
my @opt_labels = ();

# -------------------------------------------------------------------------------------------------
# get a daemon status
# (I):
# - the DaemonConfig object

sub doStatus {
	my ( $config ) = @_;
	msgOut( "requesting the daemon for its status..." );
	my $dummy = $ep->runner()->dummy() ? "-dummy" : "-nodummy";
	my $verbose = $ep->runner()->verbose() ? "-verbose" : "-noverbose";
	my $cmd = "daemon.pl command -nocolored $dummy $verbose -command status -port $opt_port";
	# TTP::commandExec() verbose-logs stdout, stderr and return code
	# TTP::filter() returns filtered stdout
	my $res = TTP::filter( $cmd );
	my $success = $res && scalar( @{$res} );
	if( $success ){
		print join( EOL, @{$res} ).EOL;
		msgOut( "done" );
	} else {
		msgWarn( "no answer from the daemon" );
		msgErr( "NOT OK" );
	}
	# publish a http telemetry if asked for
	if( $opt_http ){
		push( @opt_labels, "daemon=".$config->name());
		TTP::Metric->new( $ep, {
			name => $opt_metric,
			value => $success ? 1 : 0,
			type => 'gauge',
			help => 'Daemon status',
			labels => \@opt_labels
		})->publish({
			http => $opt_http
		});
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
	"json=s"			=> \$opt_json,
	"name=s"			=> \$opt_name,
	"port=i"			=> sub {
		my( $opt_name, $opt_value ) = @_;
		$opt_port = $opt_value;
		$opt_port_set = true;
	},
	"http!"				=> \$opt_http,
	"metric=s"			=> \$opt_metric,
	"label=s@"			=> \@opt_labels )){

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
msgVerbose( "got json='$opt_json'" );
msgVerbose( "got name='$opt_name'" );
msgVerbose( "got port='$opt_port'" );
msgVerbose( "got port_set='".( $opt_port_set ? 'true':'false' )."'" );
msgVerbose( "got http='".( $opt_http ? 'true':'false' )."'" );
msgVerbose( "got metric='$opt_metric'" );
@opt_labels = split( /,/, join( ',', @opt_labels ));
msgVerbose( "got labels='".join( ',', @opt_labels )."'" );

# either the json or the basename or the port must be specified (and not both)
my $count = 0;
$count += 1 if $opt_json;
$count += 1 if $opt_name;
$count += 1 if $opt_port != -1;
if( $count == 0 ){
	msgErr( "one of '--json' or '--name' or '--port' options must be specified, none found" );
} elsif( $count > 1 ){
	msgErr( "one of '--json' or '--name' or '--port' options must be specified, several were found" );
}
# if a daemon name is specified, find the full filename
if( $opt_name ){
	my $finder = TTP::Finder->new( $ep );
	my $confFinder = TTP::DaemonConfig->confFinder();
	$opt_json = $finder->find({ dirs => [ $confFinder->{dirs}, $opt_name ], suffix => $confFinder->{suffix}, wantsAll => false });
	msgErr( "unable to find a suitable daemon JSON configuration file for '$opt_name'" ) if !$opt_json;
}
# if a json has been specified or has been found, must have a listeningPort and get it
my $config = undef;
if( $opt_json ){
	$config = TTP::DaemonConfig->new( $ep, { jsonPath => $opt_json });
	if( $config->jsonLoaded()){
		$opt_port = $config->listeningPort();
	} else {
		msgErr( "unable to load a suitable daemon configuration for json='$opt_json'" );
	}
}
#if a port is set, must be greater than zero
msgErr( "when specified, addressed port must be greater than zero" ) if $opt_port <= 0 and $opt_port_set;

if( !TTP::errs()){
	doStatus( $config );
}

TTP::exit();
