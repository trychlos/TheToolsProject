# @(#) display internal DBMS variables
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]backupsRoot       display the root of the DBMS backups [${backupsRoot}]
# @(-) --[no]backupsPeriodic   display the periodic root of the DBMS backups [${backupsPeriodic}]
# @(-) --[no]archivesRoot      display the root (non daily) of the DBMS archive path [${archivesRoot}]
# @(-) --[no]archivesPeriodic  display the root of the periodic DBMS archive path [${archivesPeriodic}]
# @(-) --key=<name[,...]>      the key which addresses the desired value, may be specified several times or as a comma-separated list [${key}]
# @(-) --service=<name>        the service name to operate on when requesting by keys [${service}]
#
# @(@) Please remind that each of the above directories can be in the service definition of a node, or at the
# @(@) node level, or also as a value of the service definition, eventually defaulting to a site-level value.
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

use TTP::DBMS;
use TTP::Service;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	backupsRoot => 'no',
	backupsPeriodic => 'no',
	archivesRoot => 'no',
	archivesPeriodic => 'no',
	service => '',
	key => ''
};

my $opt_backupsRoot = false;
my $opt_backupsDir = false;
my $opt_backupsPeriodic = false;
my $opt_archivesRoot = false;
my $opt_archivesDir = false;
my $opt_archivesPeriodic = false;
my $opt_service = $defaults->{service};
my @opt_keys = ();

# -------------------------------------------------------------------------------------------------
# list archivesDir value - e.g. '\\ftpback-rbx7-618.ovh.net\ns3153065.ip-51-91-25.eu\WS12DEV1\SQLBackups\240101'
# obsoleted as of v4.10

sub listArchivesdir {
	my $dir = TTP::dbmsArchivesPeriodic();
	my $str = "archivesDir: $dir";
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# list archivesPeriodic value - e.g. '\\ftpback-rbx7-618.ovh.net\ns3153065.ip-51-91-25.eu\WS12DEV1\SQLBackups\240101'

sub listArchivesPeriodic {
	my $dir = TTP::dbmsArchivesPeriodic();
	my $str = "archivesPeriodic: $dir";
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# list archivesRoot value - e.g. '\\ftpback-rbx7-618.ovh.net\ns3153065.ip-51-91-25.eu\WS12DEV1\SQLBackups'

sub listArchivesRoot {
	my $dir = TTP::dbmsArchivesRoot();
	my $str = "archivesRoot: $dir";
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# list backupsDir value - e.g. 'C:\INLINGUA\SQLBackups\240101\WS12DEV1'
# obsoleted as of v4.8

sub listBackupsdir {
	my $dir = TTP::dbmsBackupsPeriodic();
	my $str = "backupsDir: $dir";
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# list backupsPeriodic value - e.g. 'C:\INLINGUA\SQLBackups\240101\WS12DEV1'

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

# -------------------------------------------------------------------------------------------------
# Display the value accessible through the route of the provided successive keys

sub listByKeys {
	my $service = undef;
	$service = TTP::Service->new( $ep, { service => $opt_service }) if $opt_service;
	my $value = TTP::DBMS::dbmsVar( \@opt_keys, { service => $service });
	print "  [".join( ',', @opt_keys )."]: ".( defined( $value ) ? ( ref( $value ) ? Dumper( $value ) : $value.EOL ) : "(undef)".EOL );
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
	"archivesPeriodic!"	=> \$opt_archivesPeriodic,
	"service=s"			=> \$opt_service,
	"key=s"				=> \@opt_keys )){

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
msgVerbose( "got archivesPeriodic='".( $opt_archivesPeriodic ? 'true':'false' )."'" );
msgVerbose( "got service='$opt_service'" );
@opt_keys= split( /,/, join( ',', @opt_keys ));
msgVerbose( "got keys='".join( ',', @opt_keys )."'" );

# deprecated options
msgWarn( "'--backupsDir' option is deprecated in favor of '--backupsPeriodic'. You should update your configurations and/or your code." ) if $opt_backupsDir;
msgWarn( "'--archivesDir' option is deprecated in favor of '--archivesPeriodic'. You should update your configurations and/or your code." ) if $opt_archivesDir;

# warn if no option has been requested
msgWarn( "none of '--backupsRoot', '--backupsPeriodic', '--archivesRoot', '--archivesPeriodic' or '--key' options has been requested, nothing to do" ) if !$opt_backupsRoot && !$opt_backupsDir && !$opt_backupsPeriodic && !$opt_archivesRoot && !$opt_archivesDir && !$opt_archivesPeriodic && !scalar( @opt_keys );

if( !TTP::errs()){
	listArchivesRoot() if $opt_archivesRoot;
	listArchivesdir() if $opt_archivesDir;
	listArchivesPeriodic() if $opt_archivesPeriodic;
	listBackupsRoot() if $opt_backupsRoot;
	listBackupsdir() if $opt_backupsDir;
	listBackupsPeriodic() if $opt_backupsPeriodic;
	listByKeys() if scalar @opt_keys;
}

TTP::exit();
