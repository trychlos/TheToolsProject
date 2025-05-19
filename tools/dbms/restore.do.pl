# @(#) restore a database
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --service=<name>        acts of this service [${service}]
# @(-) --target=<name>         target node [${target}]
# @(-) --database=<name>       target database name [${database}]
# @(-) --full=<filename>       restore from this full backup [${full}]
# @(-) --diff=<filename>       restore with this differential backup [${diff}]
# @(-) --[no]verifyonly        only check the backup restorability [${verifyonly}]
# @(-) --[no]mqtt              whether an execution report should be published to MQTT [${mqtt}]
# @(-) --[no]file              whether an execution report should be provided by file [${file}]
# @(-) --inhibit=<node>        make sure to not restore on that node [${inhibit}]
#
# @(@) Note 1: you must at least provide a full backup to restore, and may also provide an additional differential backup file.
# @(@) Note 2: target database is mandatory unless you only want a backup restorability check, in which case '--dummy' option is not honored.
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
	database => '',
	full => '',
	diff => '',
	verifyonly => 'no',
	inhibit => ''
};

my $opt_service = $defaults->{service};
my $opt_target = $defaults->{target};
my $opt_database = $defaults->{database};
my $opt_full = $defaults->{full};
my $opt_diff = $defaults->{diff};
my $opt_verifyonly = false;
my $opt_inhibit = $defaults->{inhibit};

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
# the DBMS object
my $objDbms = undef;

# -------------------------------------------------------------------------------------------------
# restore the provided backup file

sub doRestore {
	if( $opt_verifyonly ){
		msgOut( "verifying the restorability of '$opt_full'".( $opt_diff ? ", with additional diff" : "" )."..." );
	} else {
		msgOut( "restoring database '$opt_service\\$opt_database' from '$opt_full'".( $opt_diff ? ", with additional diff" : "" )."..." );
	}
	my $res = $objDbms->restoreDatabase({
		database => $opt_database,
		full => $opt_full,
		diff => $opt_diff,
		verifyonly => $opt_verifyonly
	});
	if( !$opt_verifyonly ){
		# if we have restore something (not just verified the backup files), then we create an execution report
		#  with the same properties and options than dbms.pl backup
		my $mode = $opt_diff ? 'diff' : 'full';
		my $data = {
			service => $opt_service,
			database => $opt_database,
			full => $opt_full,
			mode => $mode
		};
		if( $opt_diff ){
			$data->{diff} = $opt_diff;
		} else {
			msgVerbose( "emptying '/diff' MQTT message as restored from a full backup" );
			my $cmd = 'mqtt.pl publish -topic '.$objNode->name().'/executionReport/'.$ep->runner()->command().'/'.$ep->runner()->verb()."/$opt_service/$opt_database/diff -payload \"\" -retain -nocolored";
			msgOut( "executing '$cmd'" );
			TTP::commandExec( $cmd );
		}
		# honors --mqtt option
		if( $opt_mqtt ){
			TTP::executionReport({
				mqtt => {
					data => $data,
					topic => $objNode->name().'/executionReport/'.$ep->runner()->command().'/'.$ep->runner()->verb()."/$opt_service/$opt_database",
					options => "-retain",
					excludes => [
						'service',
						'database',
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
	"help!"				=> sub { $ep->runner()->help( @_ ); },
	"colored!"			=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"			=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"			=> sub { $ep->runner()->verbose( @_ ); },
	"service=s"			=> \$opt_service,
	"target=s"			=> \$opt_target,
	"database=s"		=> \$opt_database,
	"full=s"			=> \$opt_full,
	"diff=s"			=> \$opt_diff,
	"verifyonly!"		=> \$opt_verifyonly,
	"mqtt!"				=> \$opt_mqtt,
	"file!"				=> \$opt_file,
	"inhibit=s"			=> \$opt_inhibit )){

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
msgVerbose( "got database='$opt_database'" );
msgVerbose( "got full='$opt_full'" );
msgVerbose( "got diff='$opt_diff'" );
msgVerbose( "got verifyonly='".( $opt_verifyonly ? 'true':'false' )."'" );
msgVerbose( "got mqtt='".( $opt_mqtt ? 'true':'false' )."'" );
msgVerbose( "got file='".( $opt_file ? 'true':'false' )."'" );
msgVerbose( "got inhibit='$opt_inhibit'" );

# must have --service option
# find the node which hosts this service in this same environment (should be at most one)
# and check that the service is DBMS-aware
if( $opt_service ){
	$objNode = TTP::Node->findByService( $ep->node()->environment(), $opt_service, {
		inhibit => $opt_inhibit,
		target => $opt_target
	});
	if( $objNode ){
		msgVerbose( "got hosting node='".$objNode->name()."'" );
		$objService = TTP::Service->new( $ep, { service => $opt_service });
		if( $objService->wantsLocal() && $objNode->name() ne $ep->node()->name()){
			TTP::execRemote( $objNode->name());
			TTP::exit();
		}
		$objDbms = $objService->newDbms({ node => $objNode });
	}
} else {
	msgErr( "'--service' option is mandatory, but is not specified" );
}

msgErr( "'--database' option is mandatory, but is not specified" ) if !$opt_database && !$opt_verifyonly;
msgErr( "'--full' option is mandatory, but is not specified" ) if !$opt_full;
msgErr( "$opt_diff: file not found or not readable" ) if $opt_diff && ! -f $opt_diff;

if( !TTP::errs()){
	doRestore();
}

TTP::exit();
