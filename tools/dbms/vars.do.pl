# @(#) display internal DBMS variables
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]backupsRoot       display the root of the DBMS backups [${backupsRoot}]
# @(-) --[no]backupsPeriodic   display the periodic root of the DBMS backups [${backupsPeriodic}]
# @(-) --[no]archivesRoot      display the root (non daily) of the DBMS archive path [${archivesRoot}]
# @(-) --[no]archivesDir       display the root of the daily DBMS archive path [${archivesDir}]
# @(-) --service=<name>        optional service name [${service}]
#
# @(@) Please remind that each of these directories can be in the service definition of a node, or at the
# @(@) node level, or also as a value of the service definition, eventually defaulting to a site-level value.
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

use TTP::Service;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	backupsRoot => 'no',
	backupsPeriodic => 'no',
	archivesRoot => 'no',
	archivesDir => 'no',
	service => ''
};

my $opt_backupsRoot = false;
my $opt_backupsDir = false;
my $opt_backupsPeriodic = false;
my $opt_archivesRoot = false;
my $opt_archivesDir = false;
my $opt_service = $defaults->{service};

# may be overriden by the service if specified
my $jsonable = $ep->node();;

# -------------------------------------------------------------------------------------------------
# list archivesDir value - e.g. '\\ftpback-rbx7-618.ovh.net\ns3153065.ip-51-91-25.eu\WS12DEV1\SQLBackups\240101'

sub listArchivesdir {
	my $dir = $jsonable->var([ 'DBMS', 'archivesDir' ]) || $jsonable->var([ 'DBMS', 'archivesRoot' ]) || TTP::tempDir();
	my $str = "archivesDir: $dir";
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# list archivesRoot value - e.g. '\\ftpback-rbx7-618.ovh.net\ns3153065.ip-51-91-25.eu\WS12DEV1\SQLBackups'

sub listArchivesroot {
	my $dir = $jsonable->var([ 'DBMS', 'archivesRoot' ]) || TTP::tempDir();
	my $str = "archivesRoot: $dir";
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# list backupsDir value - e.g. 'C:\INLINGUA\SQLBackups\240101\WS12DEV1'
# obsoleted as of v4.8

sub listBackupsdir {
	my $dir = $jsonable->var([ 'DBMS', 'backupsDir' ]) || $jsonable->var([ 'DBMS', 'backupsRoot' ]) || TTP::tempDir();
	my $str = "backupsDir: $dir";
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# list backupsRoot value - e.g. 'C:\INLINGUA\SQLBackups'

sub listBackupsPeriodic {
	my $dir = TTP::dbmsBackupsPeriodic();
	my $str = "backupsPeriodic: $dir";
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# list backupsRoot value - e.g. 'C:\INLINGUA\SQLBackups'

sub listBackupsRoot {
	my $dir = TTP::dbmsBackupsRoot();
	my $str = "backupsRoot: $dir";
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> sub { $ep->runner()->help( @_ ); },
	"colored!"			=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"			=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"			=> sub { $ep->runner()->verbose( @_ ); },
	"backupsRoot!"		=> \$opt_backupsRoot,
	"backupsDir!"		=> \$opt_backupsDir,
	"backupsPeriodic!"	=> \$opt_backupsPeriodic,
	"archivesRoot!"		=> \$opt_archivesRoot,
	"archivesDir!"		=> \$opt_archivesDir,
	"service=s"			=> \$opt_service )){

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
msgVerbose( "got backupsRoot='".( $opt_backupsRoot ? 'true':'false' )."'" );
msgVerbose( "got backupsDir='".( $opt_backupsDir ? 'true':'false' )."'" );
msgVerbose( "got backupsPeriodic='".( $opt_backupsPeriodic ? 'true':'false' )."'" );
msgVerbose( "got archivesRoot='".( $opt_archivesRoot ? 'true':'false' )."'" );
msgVerbose( "got archivesDir='".( $opt_archivesDir ? 'true':'false' )."'" );
msgVerbose( "got service='$opt_service'" );

# if a service is specified, must be defined on the current node
if( $opt_service ){
	if( $jsonable->hasService( $opt_service )){
		$jsonable = TTP::Service->new( $ep, { service => $opt_service });
	} else {
		msgErr( "service '$opt_service' if not defined on current execution node" ) ;
	}
}

# warn if no option has been requested
msgWarn( "none of '--backupsRoot', '--backupsDir', '--archivesRoot' or '--archivesDir' options has been requested, nothing to do" ) if !$opt_backupsRoot && !$opt_backupsDir && !$opt_archivesRoot && !$opt_archivesDir;

# deprecated options
msgWarn( "'--backupsDir' option is deprecated in favor of '--backupsPeriodic'. You should update your configurations and/or your code." ) if $opt_backupsDir;

if( !TTP::errs()){
	listArchivesroot() if $opt_archivesRoot;
	listArchivesdir() if $opt_archivesDir;
	listBackupsRoot() if $opt_backupsRoot;
	listBackupsdir() if $opt_backupsDir;
	listBackupsPerioduic() if $opt_backupsPeriodic;
}

TTP::exit();
