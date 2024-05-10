# @(#) display internal TTP variables
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]siteSpec          display the hardcoded site search specification [${siteSpec}]
# @(-) --[no]nodeRoot          display the site-defined root path [${nodeRoot}]
# @(-) --[no]nodesDirs         display the site-defined nodes directories [${nodesDirs}]
# @(-) --[no]logsRoot          display the TTP logs root (not daily) [${logsRoot}]
# @(-) --[no]logsDaily         display the TTP daily root [${logsDaily}]
# @(-) --[no]logsCommands      display the current TTP logs directory [${logsCommands}]
# @(-) --[no]logsMain          display the current TTP main logs file [${logsMain}]
# @(-) --[no]alertsDir         display the configured alerts directory [${alertsDir}]
# @(-) --key=<name[,...]>      the key which addresses the desired value, may be specified several times or as a comma-separated list [${key}]
#
# The Tools Project: a Tools System and Paradigm for IT Production
# Copyright (©) 1998-2023 Pierre Wieser (see AUTHORS)
# Copyright (©) 2023-2024 PWI Consulting
#
# The Tools Project is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version.
#
# The Tools Project is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with The Tools Project; see the file COPYING. If not,
# see <http://www.gnu.org/licenses/>.

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	siteSpec => 'no',
	nodeRoot => 'no',
	nodesDirs => 'no',
	logsRoot => 'no',
	logsDaily => 'no',
	logsCommands => 'no',
	logsMain => 'no',
	alertsDir => 'no',
	key => ''
};

my $opt_siteSpec = false;
my $opt_nodeRoot = false;
my $opt_nodesDirs = false;
my $opt_logsRoot = false;
my $opt_logsDaily = false;
my $opt_logsCommands = false;
my $opt_logsMain = false;
my $opt_alertsDir = false;
my @opt_keys = ();

# -------------------------------------------------------------------------------------------------
# Display the configured alertsDir

sub listAlertsDir {
	my $str = "alertsDir: ".TTP::alertsDir();
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# Display the value accessible through the route of the provided successive keys

sub listByKeys {
	my $value = $ep->var( \@opt_keys );
	print "  [".join( ',', @opt_keys )."]: $value".EOL;
}

# -------------------------------------------------------------------------------------------------
# list logsCommands value - e.g. 'C:\INLINGUA\Logs\240201\Toops'

sub listLogscommands {
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
# list logsMain value - e.g. 'C:\INLINGUA\Logs\240201\Toops\main.log'

sub listLogsmain {
	my $str = "logsMain: ".TTP::logsMain();
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# list logsRoot value - e.g. 'C:\INLINGUA\Logs'

sub listLogsroot {
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

sub listNodesdirs {
	my $str = "nodesDirs: [".join( ',', @{TTP::nodesDirs()} )."]";
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
	"help!"				=> \$ttp->{run}{help},
	"colored!"			=> \$ttp->{run}{colored},
	"dummy!"			=> \$ttp->{run}{dummy},
	"verbose!"			=> \$ttp->{run}{verbose},
	"siteSpec!"			=> \$opt_siteSpec,
	"nodeRoot!"			=> \$opt_nodeRoot,
	"nodesDirs!"		=> \$opt_nodesDirs,
	"logsRoot!"			=> \$opt_logsRoot,
	"logsDaily!"		=> \$opt_logsDaily,
	"logsCommands!"		=> \$opt_logsCommands,
	"logsMain!"			=> \$opt_logsMain,
	"alertsDir!"		=> \$opt_alertsDir,
	"key=s"				=> \@opt_keys )){

		msgOut( "try '".$running->command()." ".$running->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $running->help()){
	$running->verbHelp( $defaults );
	TTP::exit();
}

msgVerbose( "found colored='".( $running->colored() ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $running->dummy() ? 'true':'false' )."'" );
msgVerbose( "found verbose='".( $running->verbose() ? 'true':'false' )."'" );
msgVerbose( "found siteSpec='".( $opt_siteSpec ? 'true':'false' )."'" );
msgVerbose( "found nodeRoot='".( $opt_nodeRoot ? 'true':'false' )."'" );
msgVerbose( "found nodesDirs='".( $opt_nodesDirs ? 'true':'false' )."'" );
msgVerbose( "found logsRoot='".( $opt_logsRoot ? 'true':'false' )."'" );
msgVerbose( "found logsDaily='".( $opt_logsDaily ? 'true':'false' )."'" );
msgVerbose( "found logsCommands='".( $opt_logsCommands ? 'true':'false' )."'" );
msgVerbose( "found logsMain='".( $opt_logsMain ? 'true':'false' )."'" );
msgVerbose( "found alertsDir='".( $opt_alertsDir ? 'true':'false' )."'" );
@opt_keys= split( /,/, join( ',', @opt_keys ));
msgVerbose( "found keys='".join( ',', @opt_keys )."'" );

if( !TTP::errs()){
	listAlertsdir() if $opt_alertsDir;
	listLogsdaily() if $opt_logsDaily;
	listLogscommands() if $opt_logsCommands;
	listLogsmain() if $opt_logsMain;
	listLogsroot() if $opt_logsRoot;
	listNoderoot() if $opt_nodeRoot;
	listNodesdirs() if $opt_nodesDirs;
	listSitespec() if $opt_siteSpec;
	listByKeys() if scalar @opt_keys;
}

TTP::exit();
