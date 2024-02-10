# @(#) display internal TTP variables
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]logsdir           display the current Toops logs directory [${logsdir}]
# @(-) --[no]logsroot          display the Toops logs Root (not daily) [${logsroot}]
# @(-) --[no]siteroot          display the site-defined root path [${siteroot}]
# @(-) --[no]archivepath       display the site-defined archive path [${archivepath}]
#
# @(@) Trying here to dynamically present all toplevel scalar values in toops.json.
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use Sys::Hostname qw( hostname );

use Mods::Services;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	logsdir => 'no',
	logsroot => 'no',
	siteroot => 'no',
	archivepath => 'no'
};

my $opt_logsroot = false;
my $opt_logsdir = false;
my $opt_siteroot = false;
my $opt_archivepath = false;

# the dynamically built options hash
my $options = _computeOptions();

# -------------------------------------------------------------------------------------------------
# compute the available options
sub _computeOptions {
	my $opts = {};
	$opts->{toops} = [];
	foreach my $key ( keys %{$TTPVars->{config}{toops}} ){
		my $ref = ref( $TTPVars->{config}{toops}{$key} );
		push( @{$opts->{toops}}, $key ) unless $ref;
	}
	$opts->{site} = [];
	foreach my $key ( keys %{$TTPVars->{config}{site}} ){
		my $ref = ref( $TTPVars->{config}{toops}{$key} );
		push( @{$opts->{site}}, $key ) unless $ref;
	}
	return $opts;
}

# -------------------------------------------------------------------------------------------------
# provide some help to available options
sub _optionsUsage {
	my $help = Mods::Toops::helpVerbStandardOptions();
	foreach my $opt ( @{$options->{toops}} ){
		my $optlc = lc $opt;
		push( @{$help}, Mods::Toops::pad( "--[no]$optlc", 24, ' ' )."display the Toops $opt variable content [no]" );
	}
	foreach my $opt ( @{$options->{site}} ){
		my $optlc = lc $opt;
		push( @{$help}, Mods::Toops::pad( "--[no]$optlc", 24, ' ' )."display the site-specific $opt variable content [no]" );
	}
	return $help;
}

# -------------------------------------------------------------------------------------------------
# list logsroot value - e.g. 'C:\INLINGUA\Logs'
sub listLogsroot {
	print " logsRoot: $TTPVars->{config}{toops}{logsRoot}".EOL;
}

# -------------------------------------------------------------------------------------------------
# list logsdir value - e.g. 'C:\INLINGUA\Logs\240201\Toops'
sub listLogsdir {
	print " logsDir: $TTPVars->{config}{toops}{logsDir}".EOL;
}

# -------------------------------------------------------------------------------------------------
# list siteroot value - e.g. 'C:\INLINGUA'
sub listSiteroot {
	print " siteRoot: $TTPVars->{config}{site}{rootDir}".EOL;
}

# -------------------------------------------------------------------------------------------------
# list siteroot value - e.g. 'C:\INLINGUA'
sub listArchivepath {
	my $host = uc hostname;
	print " archivePath: $TTPVars->{config}{$host}{archivePath}".EOL;
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"colored!"			=> \$TTPVars->{run}{colored},
	"dummy!"			=> \$TTPVars->{run}{dummy},
	"logsdir!"			=> \$opt_logsdir,
	"logsroot!"			=> \$opt_logsroot,
	"siteroot!"			=> \$opt_siteroot,
	"archivepath"		=> \$opt_archivepath )){

		Mods::Toops::msgOut( "try '$TTPVars->{command_basename} $TTPVars->{verb} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpVerb( $defaults, { usage => \&_optionsUsage });
	Mods::Toops::ttpExit();
}

Mods::Toops::msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found colored='".( $TTPVars->{run}{colored} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found dummy='".( $TTPVars->{run}{dummy} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found logsdir='".( $opt_logsdir ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found logsroot='".( $opt_logsroot ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found siteroot='".( $opt_siteroot ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found archivepath='".( $opt_archivepath ? 'true':'false' )."'" );

if( !Mods::Toops::errs()){
	listLogsdir() if $opt_logsdir;
	listLogsroot() if $opt_logsroot;
	listSiteroot() if $opt_siteroot;
	listArchivepath() if $opt_archivepath;
}

Mods::Toops::ttpExit();
