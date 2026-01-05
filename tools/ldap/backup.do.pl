# @(#) backup a LDAP directory server
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --service=<name>        service name [${service}]
# @(-) --target=<name>         target node [${target}]
# @(-) --output=<filename>     target filename [${output}]
# @(-) --[no]file              whether an execution report should be provided by file [${file}]
# @(-) --[no]mqtt              whether an execution report should be published to MQTT [${mqtt}]
#
# @(@) Note 1: The default output filename is computed as: '<backupsPeriodicDir>/<node>-<service>-<database>-<yymmdd>-<hhmiss>.ldif'.
#
# TheToolsProject - Tools System and Working Paradigm for IT Production
# Copyright (©) 1998-2023 Pierre Wieser (see AUTHORS)
# Copyright (©) 2023-2026 PWI Consulting
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

use TTP::Node;
use TTP::Service;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	service => '',
	target => '',
	output => 'DEFAUT'
};

my $opt_service = $defaults->{service};
my $opt_target = $defaults->{target};
my $opt_output = '';

my $opt_file = TTP::var([ 'executionReports', 'withFile', 'default' ]);
$opt_file = false if !defined $opt_file;
my $file_enabled = TTP::var([ 'executionReports', 'withFile', 'enabled' ]);
$file_enabled = true if !defined $file_enabled;
msgErr( "executionReports.withFile.default=true while executionReports.withFile.enabled=false which is not consistent" ) if $opt_file && !$file_enabled;
$defaults->{file} = $opt_file && $file_enabled ? 'yes' : 'no';
my $opt_file_set = false;

my $opt_mqtt = TTP::var([ 'executionReports', 'withMqtt', 'default' ]);
$opt_mqtt = false if !defined $opt_mqtt;
my $mqtt_enabled = TTP::var([ 'executionReports', 'withMqtt', 'enabled' ]);
$mqtt_enabled = true if !defined $mqtt_enabled;
msgErr( "executionReports.withMqtt.default=true while executionReports.withMqtt.enabled=false which is not consistent" ) if $opt_mqtt && !$mqtt_enabled;
$defaults->{mqtt} = $opt_mqtt && $mqtt_enabled ? 'yes' : 'no';
my $opt_mqtt_set = false;

# the node which hosts the requested service
my $objNode = undef;
# the service object
my $objService = undef;
# the LDAP object
my $objLdap = undef;

# ------------------------------------------------------------------------------------------------
# compute the default backup output filename for the current machine/service/database
# making sure the output directory exists
# (I):
# - none
# (O):
# - the default output full filename

sub _computeDefaultBackupFilename {
	my $output = undef;
	# compute the dir and make sure it exists
	my $node = $objNode->name();
	my $backupDir = TTP::dbmsBackupsPeriodic();
	TTP::Path::makeDirExist( $backupDir );
	# compute the filename
	my $fname = $node."-".$objService->name()."-".( Time::Moment->now->strftime( '%y%m%d-%H%M%S' ));
	$output = File::Spec->catdir( $backupDir, $fname );
	msgVerbose( "_computeDefaultBackupFilename() computing output default as '$output'" );
	return $output;
}

# -------------------------------------------------------------------------------------------------
# backup the LDAP directory server to the target backup file

sub doBackup {
	msgOut( "backuping LDAP directory server '$opt_service'..." );
	my $commands = TTP::commandByOS([ 'LDAP', 'backups' ], { jsonable => $objService });
	my $count = 0;
	my $ok = 0;
	if( $commands && scalar( @{$commands} )){
		my $output = $opt_output || _computeDefaultBackupFilename();
		# print the output file if not provided as a command-line argument
		msgOut( "output is '$output'" ) if !$opt_output;
		my $macros = $objLdap->macros();
		$macros->{OUTPUT} = $output;
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
			output => $output
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
		msgWarn( "no commands have been found for LDAP.backups" );
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
	"output=s"			=> \$opt_output,
	"file!"				=> sub {
		my( $name, $value ) = @_;
		$opt_file = $value;
		$opt_file_set = true;
	},
	"mqtt!"				=> sub {
		my( $name, $value ) = @_;
		$opt_mqtt = $value;
		$opt_mqtt_set = true;
	} )){

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
msgVerbose( "got output='$opt_output'" );
msgVerbose( "got file='".( $opt_file ? 'true':'false' )."'" );
msgVerbose( "got mqtt='".( $opt_mqtt ? 'true':'false' )."'" );

# must have --service option
# find the node which hosts this service in this same environment
if( $opt_service ){
	$objNode = TTP::Node->findByService( $ep->node()->environment(), $opt_service, { target => $opt_target });
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

if( !$opt_output ){
	msgVerbose( "'--output' option not specified, will use the computed default" );
}

# disabled media are just ignored (or refused if option was explicit)
if( $opt_file ){
	if( !$file_enabled ){
		if( $opt_file_set ){
			msgErr( "File medium is disabled, --file option is not valid" );
		} else {
			msgWarn( "File medium is disabled and thus ignored" );
			$opt_file = false;
		}
	}
}
if( $opt_mqtt ){
	if( !$mqtt_enabled ){
		if( $opt_mqtt_set ){
			msgErr( "MQTT medium is disabled, --mqtt option is not valid" );
		} else {
			msgWarn( "MQTT medium is disabled and thus ignored" );
			$opt_mqtt = false;
		}
	}
}

if( !TTP::errs()){
	doBackup();
}

TTP::exit();
