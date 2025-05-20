# @(#) backup a LDAP directory server
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --service=<name>        service name [${service}]
# @(-) --target=<name>         target node [${target}]
# @(-) --output=<filename>     target filename [${output}]
# @(-) --[no]mqtt              whether an execution report should be published to MQTT [${mqtt}]
# @(-) --[no]file              whether an execution report should be provided by file [${file}]
#
# @(@) Note 1: the default output filename is computed as: '<backupsPeriodicDir>/<node>-<service>-<database>-<yymmdd>-<hhmiss>.ldif'.
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
	my $commands = TTP::commandByOS([ 'LDAP', 'backups' ], { withCommands => true, jsonable => $objService });
	my $count = 0;
	my $ok = 0;
	if( $commands && scalar( @{$commands} )){
		my $output = $opt_output || _computeDefaultBackupFilename();
		# print the output file if not provided as a command-line argument
		msgOut( "output is '$output'" ) if !$opt_output;
		foreach my $cmd ( @{$commands} ){
			$count += 1;
			my $res = TTP::commandExec( $cmd, {
				macros => {
					OUTPUT => $output
				}
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
						'cmdline',
						'command',
						'verb'
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
msgVerbose( "got output='$opt_output'" );
msgVerbose( "got mqtt='".( $opt_mqtt ? 'true':'false' )."'" );
msgVerbose( "got file='".( $opt_file ? 'true':'false' )."'" );

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
	}
} else {
	msgErr( "'--service' option is mandatory, but is not specified" );
}

if( !$opt_output ){
	msgVerbose( "'--output' option not specified, will use the computed default" );
}

if( !TTP::errs()){
	doBackup();
}

TTP::exit();
