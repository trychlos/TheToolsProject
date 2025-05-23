# @(#) restore a LDAP directory server
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --service=<name>        acts of this service [${service}]
# @(-) --target=<name>         target node [${target}]
# @(-) --config=<filename>     restore config from this file [${config}]
# @(-) --data=<filename>       restore data from this file [${data}]
# @(-) --[no]mqtt              whether an execution report should be published to MQTT [${mqtt}]
# @(-) --[no]file              whether an execution report should be provided by file [${file}]
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

use TTP::Node;
use TTP::Service;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	service => '',
	target => '',
	config => '',
	data => ''
};

my $opt_service = $defaults->{service};
my $opt_target = $defaults->{target};
my $opt_config = $defaults->{config};
my $opt_data = $defaults->{data};

my $opt_mqtt = TTP::var([ 'executionReports', 'withMqtt', 'default' ]);
$opt_mqtt = false if !defined $opt_mqtt;
$defaults->{mqtt} = $opt_mqtt ? 'yes' : 'no';

my $opt_file = TTP::var([ 'executionReports', 'withFile', 'default' ]);
$opt_file = false if !defined $opt_file;
$defaults->{file} = $opt_file ? 'yes' : 'no';

# the node which hosts the requested service
my $objNode = undef;
# the service object
my $objService = undef;
# the LDAP object
my $objLdap = undef;

# -------------------------------------------------------------------------------------------------
# restore the provided backup file

sub doRestore {
	msgOut( "restoring LDAP directory server '$opt_service'..." );
	my $commands = TTP::commandByOS([ 'LDAP', 'restores' ], { jsonable => $objService });
	my $count = 0;
	my $ok = 0;
	if( $commands && scalar( @{$commands} )){
		my $macros = $objLdap->macros();
		$macros->{CONFIG} = $$opt_config if $opt_config;
		$macros->{DATA} = $$opt_data if $opt_data;
		foreach my $cmd ( @{$commands} ){
			$count += 1;
			my $res = TTP::commandExec( $cmd, {
				macros => $macros
			});
			if( scalar( $res->{stdout} )){
				msgOut( $res->{stdout} );
			}
			if( $res->{success} ){
				$ok += 1;
				if( scalar( $res->{stderr} )){
					msgWarn( $res->{stderr} );
				}
			} else {
				msgErr( $res->{stderr} );
				last;
			}
		}
		# retain last full and last diff
		my $data = {
			service => $opt_service,
			config => $opt_config,
			data => $opt_data
		};
		# honors --mqtt option
		if( $opt_mqtt ){
			TTP::executionReport({
				mqtt => {
					topic => $objNode->name()."/executionReport/".$ep->runner()->command().'/'.$ep->runner()->verb()."/$opt_service",
					data => $data,
					options => "-retain",
					excludes => [
						'service',
						'cmdline',
						'command',
						'verb',
						'node'
					]
				}
			});
		}
		# honors --file option
		if( $opt_file ){
			TTP::executionReport({
				file => {
					data => $data
				}
			});
		}
	} else {
		msgWarn( "no commands have been found for LDAP.restores" );
	}
	my $str = "$ok/$count successfully executed commands(s)";
	if( $ok == $count ){
		msgOut( "success: $str" );
	} else {
		msgErr( "NOT OK: $str" );
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
	"target=s"			=> \$opt_target,
	"config=s"			=> \$opt_config,
	"data=s"			=> \$opt_data,
	"mqtt!"				=> \$opt_mqtt,
	"file!"				=> \$opt_file )){

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
msgVerbose( "got target='$opt_target'" );
msgVerbose( "got config='$opt_config'" );
msgVerbose( "got data='$opt_data'" );
msgVerbose( "got mqtt='".( $opt_mqtt ? 'true':'false' )."'" );
msgVerbose( "got file='".( $opt_file ? 'true':'false' )."'" );

# must have --service option
# find the node which hosts this service in this same environment (should be at most one)
# and check that the service is DBMS-aware
if( $opt_service ){
	$objNode = TTP::Node->findByService( $ep->node()->environment(), $opt_service, {
		target => $opt_target
	});
	if( $objNode ){
		msgVerbose( "got hosting node='".$objNode->name()."'" );
		$objService = TTP::Service->new( $ep, { service => $opt_service });
		if( $objService->wantsLocal() && $objNode->name() ne $ep->node()->name()){
			TTP::execRemote( $objNode->name());
			TTP::exit();
		}
		$objLdap = $objService->newLdap({ node => $objNode });
	}
} else {
	msgErr( "'--service' option is mandatory, but is not specified" );
}

# at least --config or --data should be provided
msgWarn( "at least '--config' or '--data' should have been provided, none found" ) if !$opt_config && !$opt_data;

# provided files must exist
msgErr( "config='$opt_config' doesn't exist or is not readable" ) if $opt_config && ! -r $opt_config;
msgErr( "data='$opt_data' doesn't exist or is not readable" ) if $opt_data && ! -r $opt_data;

if( !TTP::errs()){
	doRestore();
}

TTP::exit();
