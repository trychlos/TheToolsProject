# @(#) display internal TTP variables
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]siteSpec          display the hardcoded site search specification [${siteSpec}]
# @(-) --[no]credentialsDirs   display the list of credentials directories [${credentialsDirs}]
# @(-) --[no]nodesDirs         display the site-defined nodes directories [${nodesDirs}]
# @(-) --[no]logsRoot          display the TTP logs root (not daily) [${logsRoot}]
# @(-) --[no]logsPeriodic      display the TTP periodic root [${logsPeriodic}]
# @(-) --[no]logsCommands      display the current TTP logs directory [${logsCommands}]
# @(-) --[no]logsMain          display the current TTP main logs file [${logsMain}]
# @(-) --[no]alertsDir         display the configured alerts directory [${alertsDir}]
# @(-) --key=<name[,...]>      the key which addresses the desired value, may be specified several times or as a comma-separated list [${key}]
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

use TTP::Credentials;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	siteSpec => 'no',
	credentialsDirs => 'no',
	nodesDirs => 'no',
	logsRoot => 'no',
	logsPeriodic => 'no',
	logsCommands => 'no',
	logsMain => 'no',
	alertsDir => 'no',
	key => ''
};

my $opt_siteSpec = false;
my $opt_credentialsDirs = false;
my $opt_nodeRoot = false;
my $opt_nodesDirs = false;
my $opt_logsRoot = false;
my $opt_logsDaily = false;
my $opt_logsPeriodic = false;
my $opt_logsCommands = false;
my $opt_logsMain = false;
my $opt_alertsDir = false;
my @opt_keys = ();

# -------------------------------------------------------------------------------------------------
# Display the configured alerts.byFile.dir

sub listAlertsDir {
	my $str = "alertsFileDropdir: ".TTP::alertsFileDropdir();
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# Display the value accessible through the route of the provided successive keys

sub listByKeys {
	my $value = $ep->var( \@opt_keys );
	print "  [".join( ',', @opt_keys )."]: ".( defined( $value ) ? ( ref( $value ) ? Dumper( $value ) : $value.EOL ) : "(undef)".EOL );
}

# -------------------------------------------------------------------------------------------------
# Display the configured credentials.dirs

sub listCredentialsDirs {
	my $credentialsFinder = TTP::Credentials::finder();
	my $str = "credentialsDirs: [".join( ',', @{$credentialsFinder->{dirs}})."]";
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# list logsCommands value - e.g. 'C:\INLINGUA\Logs\240201\TTP'

sub listLogsCommands {
	my $str = "logsCommands: ".TTP::logsCommands();
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# list logsDaily value - e.g. 'C:\INLINGUA\Logs\240201'

sub listLogsdaily {
	my $str = "logsDaily: ".TTP::logsDaily();
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# list logsMain value - e.g. 'C:\INLINGUA\Logs\240201\TTP\main.log'

sub listLogsMain {
	my $str = "logsMain: ".TTP::logsMain();
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# list logsperiodic value - e.g. 'C:\INLINGUA\Logs\240201'

sub listLogsPeriodic {
	my $str = "logsPeriodic: ".TTP::logsPeriodic();
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# list logsRoot value - e.g. 'C:\INLINGUA\Logs'

sub listLogsRoot {
	my $str = "logsRoot: ".TTP::logsRoot();
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# list nodeRoot value - e.g. 'C:\INLINGUA'

sub listNoderoot {
	my $str = "nodeRoot: ".TTP::nodeRoot();
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# list nodesDirs value - e.g. '[ 'etc/nodes', 'nodes', 'etc/machines', 'machines' ]'

sub listNodesDirs {
	my $finder = TTP::Node->finder();
	my $str = "nodesDirs: [".join( ',', @{$finder->{dirs}} )."]";
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# list siteSpec value - e.g. '[ 'etc/ttp/site.json', 'etc/site.json' ]'

sub listSitespec {
	my $str = "siteSpec: [".join( ',', @{TTP::Site->finder()->{dirs}} )."]";
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
	"siteSpec!"			=> \$opt_siteSpec,
	"credentialsDirs!"	=> \$opt_credentialsDirs,
	"nodeRoot!"			=> \$opt_nodeRoot,
	"nodesDirs!"		=> \$opt_nodesDirs,
	"logsRoot!"			=> \$opt_logsRoot,
	"logsDaily!"		=> \$opt_logsDaily,
	"logsPeriodic!"		=> \$opt_logsPeriodic,
	"logsCommands!"		=> \$opt_logsCommands,
	"logsMain!"			=> \$opt_logsMain,
	"alertsDir!"		=> \$opt_alertsDir,
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
msgVerbose( "got siteSpec='".( $opt_siteSpec ? 'true':'false' )."'" );
msgVerbose( "got credentialsDirs='".( $opt_credentialsDirs ? 'true':'false' )."'" );
msgVerbose( "got nodeRoot='".( $opt_nodeRoot ? 'true':'false' )."'" );
msgVerbose( "got nodesDirs='".( $opt_nodesDirs ? 'true':'false' )."'" );
msgVerbose( "got logsRoot='".( $opt_logsRoot ? 'true':'false' )."'" );
msgVerbose( "got logsDaily='".( $opt_logsDaily ? 'true':'false' )."'" );
msgVerbose( "got logsPeriodic='".( $opt_logsPeriodic ? 'true':'false' )."'" );
msgVerbose( "got logsCommands='".( $opt_logsCommands ? 'true':'false' )."'" );
msgVerbose( "got logsMain='".( $opt_logsMain ? 'true':'false' )."'" );
msgVerbose( "got alertsDir='".( $opt_alertsDir ? 'true':'false' )."'" );
@opt_keys= split( /,/, join( ',', @opt_keys ));
msgVerbose( "got keys='".join( ',', @opt_keys )."'" );

msgErr( "'--nodesRoot' option is deprecated and not replaced. You should update your configurations and/or your code." ) if $opt_nodeRoot;

msgWarn( "'--logsDaily' option is deprecated in favor of '--logsPeriodic'. You should update your configurations and/or your code." ) if $opt_logsDaily;

if( !TTP::errs()){
	listAlertsDir() if $opt_alertsDir;
	listCredentialsDirs() if $opt_credentialsDirs;
	listLogsdaily() if $opt_logsDaily;
	listLogsPeriodic() if $opt_logsPeriodic;
	listLogsCommands() if $opt_logsCommands;
	listLogsMain() if $opt_logsMain;
	listLogsRoot() if $opt_logsRoot;
	listNodesDirs() if $opt_nodesDirs;
	listSitespec() if $opt_siteSpec;
	listByKeys() if scalar @opt_keys;
}

TTP::exit();
