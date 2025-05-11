# @(#) manage Windows services
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]list              list the managed services [${list}]
# @(-) --name=<name>           acts on the named service [${name}]
# @(-) --[no]state             query the service state [${state}]
# @(-) --[no]mqtt              publish the metrics to the (MQTT-based) messaging system [${mqtt}]
# @(-) --mqttPrefix=<prefi>    prefix the metric name when publishing to the (MQTT-based) messaging system [${mqttPrefix}]
# @(-) --[no]http              publish the metrics to the (HTTP-based) Prometheus PushGateway system [${http}]
# @(-) --httpPrefix=<prefi>    prefix the metric name when publishing to the (HTTP-based) Prometheus PushGateway system [${httpPrefix}]
# @(-) --[no]text              publish the metrics to the (text-based) Prometheus TextFile Collector system [${text}]
# @(-) --textPrefix=<prefi>    prefix the metric name when publishing to the (text-based) Prometheus TextFile Collector system [${textPrefix}]
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

use TTP::Metric;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	list => 'no',
	name => '',
	state => 'no',
	mqtt => 'no',
	mqttPrefix => '',
	http => 'no',
	httpPrefix => '',
	text => 'no',
	textPrefix => '',
	prepend => '',
	append => ''
};

my $opt_list = false;
my $opt_name = $defaults->{name};
my $opt_state = false;
my $opt_mqtt = false;
my $opt_mqttPrefix = $defaults->{mqttPrefix};
my $opt_http = false;
my $opt_httpPrefix = $defaults->{httpPrefix};
my $opt_text = false;
my $opt_textPrefix = $defaults->{textPrefix};
my @opt_prepends = ();
my @opt_appends = ();

# Source: https://learn.microsoft.com/en-us/windows/win32/services/service-status-transitions
my $serviceStates = {
	'1' => 'stopped',
	'2' => 'start_pending',
	'3' => 'stop_pending',
	'4' => 'running',
	'5' => 'continue_pending',
	'6' => 'pause_pending',
	'7' => 'paused'
};

# -------------------------------------------------------------------------------------------------
# list the managed Win32 services
# provides a case-insensitive sorted list of services

sub doServicesList {
	msgOut( "querying the services list..." );
	my $command = "sc query | find \"SERVICE_NAME:\"";
	my $res = TTP::commandExec( $command );
	my $count = 0;
	foreach my $it ( sort { "\L$a" cmp "\L$b" } @{$res->{stdout}} ){
		my @words = split( /\s+/, $it );
		print " $words[1]".EOL;
		$count += 1;
	}
	if( $res->{success} ){
		msgOut( "$count found managed service(s)" );
	} else {
		msgErr( "NOT OK" );
	}
}

# -------------------------------------------------------------------------------------------------
# query the status of a named service

sub doServiceState {
	msgOut( "querying the '$opt_name' service state..." );
	my $command = "sc query $opt_name";
	my $res = TTP::commandExec( $command );
	# note that we do not should execute directly a pipe'd command as we want the return code of the 'sc' one
	# find STATE in the line if the command has been successful
	# in case of an error we get the error message in the last non-blank line
	my $count = scalar( @{$res->{stdout}} );
	my $label = undef;
	my $value = undef;
	my $error = undef;
	if( $res->{success} ){
		my $state = undef;
		foreach my $line ( @{$res->{stdout}} ){
			if( $line =~ m/STATE/ ){
				my @words = split( /\s+/, $line );
				$label = $words[scalar( @words )-1];
				$value = "$words[scalar( @words )-2]";
				msgOut( "  $value: $label" );
			}
		}
	} else {
		my @lines = @{$res->{stdout}};
		for( my $i=$count ; $i ; --$i ){
			if( $lines[$i-1] && length $lines[$i-1] ){
				$error = $lines[$i-1];
				last;
			}
		}
		if( !defined $error ){
			$error = "Undefined error";
		}
		msgErr( $error );
	}
	# publish the result in all cases, and notably even if there was an error
	if( $opt_mqtt || $opt_http || $opt_text ){
		my @labels = ( @opt_prepends,
			"environment=".$ep->node()->environment(), "command=".$ep->runner()->command(), "verb=".$ep->runner()->verb(), "role=$opt_name",
			@opt_appends );
		TTP::Metric->new( $ep, {
			name => 'state',
			value => $res ? $label : $error,
			labels => \@labels
		})->publish({
			mqtt => $opt_mqtt,
			mqttPrefix => $opt_mqttPrefix
		});
		foreach my $key ( keys( %{$serviceStates} )){
			my @labels = ( @opt_prepends,
				"environment=".$ep->node()->environment(), "command=".$ep->runner()->command(), "verb=".$ep->runner()->verb(), 
				"role=$opt_name", "state=$serviceStates->{$key}",
				@opt_appends );
			TTP::Metric->new( $ep, {
				name => 'service_state',
				value => ( defined $value && $key eq $value ) ? '1' : '0',
				type => 'gauge',
				help => 'Win32 service status',
				labels => \@labels
			})->publish({
				http => $opt_http,
				httpPrefix => $opt_httpPrefix,
				text => $opt_text,
				textPrefix => $opt_textPrefix
			});
		}
	}
	if( $res->{success} ){
		msgOut( "success" );
	} else {
		msgErr( "NOT OK", { incErr => false });
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
	"list!"				=> \$opt_list,
	"name=s"			=> \$opt_name,
	"state!"			=> \$opt_state,
	"mqtt!"				=> \$opt_mqtt,
	"mqttPrefix=s"		=> \$opt_mqttPrefix,
	"http!"				=> \$opt_http,
	"httpPrefix=s"		=> \$opt_httpPrefix,
	"text!"				=> \$opt_text,
	"textPrefix=s"		=> \$opt_textPrefix,
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
msgVerbose( "got list='".( $opt_list ? 'true':'false' )."'" );
msgVerbose( "got name='$opt_name'" );
msgVerbose( "got state='".( $opt_state ? 'true':'false' )."'" );
msgVerbose( "got mqtt='".( $opt_mqtt ? 'true':'false' )."'" );
msgVerbose( "got mqttPrefix='$opt_mqttPrefix'" );
msgVerbose( "got http='".( $opt_http ? 'true':'false' )."'" );
msgVerbose( "got httpPrefix='$opt_httpPrefix'" );
msgVerbose( "got text='".( $opt_text ? 'true':'false' )."'" );
msgVerbose( "got textPrefix='$opt_textPrefix'" );
@opt_prepends = split( /,/, join( ',', @opt_prepends ));
msgVerbose( "got prepends='".join( ',', @opt_prepends )."'" );
@opt_appends = split( /,/, join( ',', @opt_appends ));
msgVerbose( "got appends='".join( ',', @opt_appends )."'" );

# a service name is mandatory when querying its status
msgErr( "'--name' service name is mandatory when querying for a status" ) if $opt_state && !$opt_name;

if( !TTP::errs()){
	my $count = 0;
	if( $opt_list ){
		doServicesList();
		$count += 1;
	}
	if( $opt_name && $opt_state ){
		doServiceState();
		$count += 1;
	}
	if( !$count ){
		msgWarn( "no action has been specified, doing nothing" );
	}
}

TTP::exit();
