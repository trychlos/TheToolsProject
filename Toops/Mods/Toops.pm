# Copyright (@) 2023-2024 PWI Consulting

package Mods::Toops;

use strict;
use warnings;

use Config;
use Data::Dumper;
use File::Path qw( make_path );
use File::Spec;
use Getopt::Long;
use JSON;
use Mods::HostConf;
use Path::Tiny qw( path );
use Sub::Exporter;
use Sys::Hostname qw( hostname );
use Term::ANSIColor;
use Time::Piece;
use Win32::Console::ANSI;

use Mods::Constants qw( :all );

Sub::Exporter::setup_exporter({
	exports => [ qw(
		doHelpCommand
		doHelpVerb
		dump
		errs
		getDefaultTempDir
		getHostConfig
		getOptions
		makeDirExist
		msgErr
		msgLog
		msgOut
		msgPrefix
		msgVerbose
		msgWarn
		pathRemoveTrailingChar
		pathRemoveTrailingSeparator
		run
		ttpExit
		TTPVars
		wantsHelp
	)]
});

# autoflush STDOUT
$| = 1;

# make sure colors are resetted after end of line
$Term::ANSIColor::EACHLINE = EOL;

# store here our Toops variables
my $TTPVars = {
	Toops => {
		# defaults which depend of the host OS
		defaults => {
			darwin => {
				logsRoot => '/tmp',
				tempDir => '/tmp'
			},
			linux => {
				logsRoot => '/tmp',
				tempDir => '/tmp'
			},
			MSWin32 => {
				logsRoot => 'C:\\Temp',
				tempDir => 'C:\\Temp'
			}
		},
		# reserved words: the commands must be named outside of this array
		#  either because they are folders of the Toops installation tree
		#  or because they are first level key in TTPVars (thus preventing to have a 'command' object at this first level)
		ReservedWords => [
			'bin',
			'config',
			'dyn',
			'Mods',
			'run',
			'Toops'
		],
		# some internally used constants
		commentPreUsage => '^# @\(#\) ',
		commentPostUsage => '^# @\(@\) ',
		verbSufix => '.do.pl',
		verbSed => '\.do\.pl'
	},
	# initialize some run variables
	run => {
		exit_code => 0,
		help => false,
		verbose => false
	}
};

# -------------------------------------------------------------------------------------------------
# Display the one-liner command help
# Extract lines from command script and list the header lines of the found verbs
sub doHelpCommand {
	#Mods::Toops::dump();
	# display the command inline help
	my $commandInline = Mods::Toops::getInlineHelp( $TTPVars->{run}{command}{path} );
	print "$TTPVars->{run}{command}{basename}: $commandInline".EOL;
	# display each verb inline help
	my @verbs = Mods::Toops::getVerbs();
	my $verbHelps = {};
	foreach my $it ( @verbs ){
		my $verbInline = Mods::Toops::getInlineHelp( $it, { warnIfSeveral => false });
		my ( $volume, $directories, $file ) = File::Spec->splitpath( $it );
		my $verb = $file;
		$verb =~ s/$TTPVars->{Toops}{verbSed}$//;
		$verbHelps->{$verb} = $verbInline;
	}
	@verbs = keys %{$verbHelps};
	my @sorted = sort @verbs;
	foreach my $it ( @sorted ){
		print "  $it: $verbHelps->{$it}".EOL;
	}
}

# -------------------------------------------------------------------------------------------------
# Display the full verb help
# Args are the options in Toops format (see Mods::Toops::getOptions)
sub doHelpVerb {
	my $args = shift;
	my $commandInline = Mods::Toops::getInlineHelp( $TTPVars->{run}{command}{path} );
	print "$TTPVars->{run}{command}{basename}: $commandInline".EOL;
	my @verbHelp = Mods::Toops::getInlineHelp( $TTPVars->{run}{verb}{path}, { warnIfSeveral => false, returnOne => false });
	my $verbInline = '';
	if( scalar @verbHelp ){
		$verbInline = shift @verbHelp;
	}
	print "  $TTPVars->{run}{verb}{name}: $verbInline".EOL;
	foreach my $line ( @verbHelp ){
		print "    $line".EOL;
	}
	#print Dumper( $TTPVars->{run} );
}

# -------------------------------------------------------------------------------------------------
# Dump the internal variables
sub dump {
	foreach my $key ( keys %{$TTPVars} ){
		Mods::Toops::msgVerbose( "$key='$TTPVars->{$key}'", { verbose => true, withLog => true });
	}
}

# -------------------------------------------------------------------------------------------------
# is there any error
#  exit code may be seen as an error counter as it is incremented by msgErr
sub errs {
	return $TTPVars->{run}{exit_code};
}

# -------------------------------------------------------------------------------------------------
# returns the default temp directory for the running OS
sub getDefaultTempDir {
	return $TTPVars->{Toops}{defaults}{$Config{osname}}{tempDir};
}

# -------------------------------------------------------------------------------------------------
# returns the host config
sub getHostConfig {
	my $host = hostname;
	return $TTPVars->{config}{$host};
}

# -------------------------------------------------------------------------------------------------
# returns the one-line inline help for the file
# (E):
# - the filename to be parsed
# - an optional options hash with following keys:
#   > warnIfNone defaulting to true
#   > warnIfSeveral defaulting to true
sub getInlineHelp {
	my ( $filename, $opts ) = @_;
	$opts //= {};
	local $/ = "\r\n";
	my @content = path( $filename )->lines_utf8;
	chomp @content;
	my @help = grep( /$TTPVars->{Toops}{commentPreUsage}/, @content );
	my $inline = undef;
	my $warnIfNone = true;
	$warnIfNone = $opts->{warnIfNone} if exists $opts->{warnIfNone};
	if( scalar @help == 0 ){
		Mods::Toops::msgWarn( "'$filename' doesn't have any inline help. This is bad!" ) if $warnIfNone;
	} else {
		my $warnIfSeveral = true;
		$warnIfSeveral = $opts->{warnIfSeveral} if exists $opts->{warnIfSeveral};
		if( scalar @help > 1 ){
			Mods::Toops::msgWarn( "'$filename' has more than one inline help line. This is bad!" ) if $warnIfSeveral;
		}
		$inline = $help[0];
		$inline =~ s/^$TTPVars->{Toops}{commentPreUsage}//;
	}
	return $inline;
}

# -------------------------------------------------------------------------------------------------
# Interpret the command-line options
# Deal here with -help and -verbose
# args is a ref to an array of hashes with following keys:
# - key: the option name
# - help: a short help message
# - opt: the string to be appended to the option to be passed to GetOptions::Long
# - var: the reference to the variable which will hold the value
# - def: the displayed default value
sub getOptions {
	Mods::Toops::msgErr( "Mods::Toops::getOptions() is just a placeholder for now. Please use standard GetOptions()." );
}

=pod
# -------------------------------------------------------------------------------------------------
# Interpret the command-line options
# Deal here with -help and -verbose
# args is a ref to an array of hashes with following keys:
# - key: the option name
# - help: a short help message
# - opt: the string to be appended to the option to be passed to GetOptions::Long
# - var: the reference to the variable which will hold the value
# - def: the displayed default value
sub getOptions {
	my $parms = shift;
	print "getOoptions()".EOL;
	my $args = getOptionsPrepend( $parms );
	my $optargs = getOptionsToOpts( $args );
	#print Dumper( $optargs );
	print "calling GetOptions()..".EOL;
	if( !myGetOptions( @{$optargs} )){
		Mods::Toops::msgOut( "try '$TTPVars->{command_basename} $TTPVars->{verb} --help' to get full usage syntax" );
		#$TTPVars->{exitCode} += 1;
		Mods::Toops::ttpExit();
	}
	print "return from GetOptions()".EOL;
	if( !scalar @{$TTPVars->{verb_args}} ){
		$TTPVars->{help} = true;
	}
	if( $TTPVars->{help} ){
		Mods::Toops::doHelpVerb();
		Mods::Toops::ttpExit();
	}
	Mods::Toops::msgVerbose( "found verbose='true'" );
}

# -------------------------------------------------------------------------------------------------
# Append our own options to the list of verb options
sub getOptionsPrepend {
	my $parms = shift;
	my $args = [
		{
			key	 => 'help',
			help => 'print this message, and exit',
			opt	 => '!',
			var  => \$TTPVars->{help},
			def  => "no"
		},
		{
			key	 => 'verbose',
			help => 'run verbosely',
			opt	 => '!',
			var  => \$TTPVars->{verbose},
			def  => "no"
		}
	];
	$TTPVars->{help} = false;
	$TTPVars->{verbose} = false;
	return [ @{$args}, @{$parms} ];
}

# -------------------------------------------------------------------------------------------------
# convert the Toops options array to the GetOptions one
sub getOptionsToOpts {
	my $parms = shift;
	my $args = [];
	foreach my $opt ( @{$parms} ){
		print Dumper( $opt );
		push( @{$args}, [ $opt->{key}.$opt->{opt},  $opt->{var} ]);
	}
	print Dumper( $args );
	return $args;
}
=cut

# -------------------------------------------------------------------------------------------------
# returns the available verbs for the current command
sub getVerbs {
	my @verbs = glob( File::Spec->catdir( $TTPVars->{run}{command}{verbs_dir}, "*".$TTPVars->{Toops}{verbSufix} ));
	return @verbs;
}

# -------------------------------------------------------------------------------------------------
# get the machine services configuration as a hash indexed by hostname
#  HostConf::init() is expected to return a hash with a single top key which is the hostname
#  we check and force that here
#  + set the host as a value to be more easily available
sub initHostConfiguration {
	my $host = hostname;
	$TTPVars->{config}{$host} = Mods::HostConf::init()->{$host};
	$TTPVars->{config}{$host}{host} = $host;
}

# -------------------------------------------------------------------------------------------------
# Initialize the logs
# Expects the site configuration has a 'toops/logsRoot' variable, defaulting to /tmp/Toops/logs in unix and C:\Temps\Toops\logs in Windows
# Make sure the daily directory exists
sub initLogs {
	my $logs_root = undef;
	if( $TTPVars->{config} && $TTPVars->{config}{site} && $TTPVars->{config}{site}{toops} ){
		$logs_root = $TTPVars->{config}{site}{toops}{logsRoot};
	}
	if( !$logs_root ){
		$logs_root = File::Spec->catdir( $TTPVars->{Toops}{defaults}{$Config{osname}}{logsRoot}, 'Toops', 'logs' );
		Mods::Toops::msgWarn( "'logsRoot' not found in site configuration, defaulting to '$logs_root'" );
	}
	$TTPVars->{dyn}{logs_root} = $logs_root;
	$TTPVars->{dyn}{daily_8} = localtime->strftime( '%Y%m%d' );
	$TTPVars->{dyn}{daily_6} = localtime->strftime( '%y%m%d' );
	$TTPVars->{dyn}{logs_dir} = File::Spec->catdir( $logs_root, $TTPVars->{dyn}{daily_6} );
	make_path( $TTPVars->{dyn}{logs_dir} );
	$TTPVars->{dyn}{logs_main} = File::Spec->catdir( $TTPVars->{dyn}{logs_dir}, 'main.log' );
}

# -------------------------------------------------------------------------------------------------
# Make sure we have a site configuration JSON file and loads it
sub initSiteConfiguration {
		my $json_path = File::Spec->catdir( $ENV{TTP_SITE}, 'toops.json' );
		if( -f $json_path ){
			my $json_text = do {
			   open( my $json_fh, "<:encoding(UTF-8)", $json_path ) or die( "Can't open '$json_path': $!".EOL );
			   local $/;
			   <$json_fh>
			};
			my $json = JSON->new;
			$TTPVars->{config}{site} = $json->decode( $json_text );
		} else {
			Mods::Toops::msgWarn( "site configuration file '$json_path' not found or not readable" );
		}
}

# -------------------------------------------------------------------------------------------------
# make sure a directory exist
sub makeDirExist {
	my ( $dir ) = @_;
	# seems that make_path is not easy with UNC path (actually seems that make_path just dies)
	if( $dir =~ /^\\\\/ ){
		my @levels = ();
		my $candidate = $dir;
		my ( $volume, $directories, $file ) = File::Spec->splitpath( $candidate );
		my $other;
		unshift( @levels, $file );
		while( length $directories > 1 ){
			$candidate = Mods::Toops::pathRemoveTrailingSeparator( $directories );
			( $other, $directories, $file ) = File::Spec->splitpath( $candidate );
			unshift( @levels, $file );
		}
		$candidate = '';
		while( scalar @levels ){
			my $level = shift @levels;
			my $dir = File::Spec->catpath( $volume, $candidate, $level );
			mkdir $dir;
			$candidate = File::Spec->catdir(  $candidate, $level );
		}
	} else {
		make_path( $dir );
	}
}

# -------------------------------------------------------------------------------------------------
# Error message - always logged
sub msgErr {
	my $msg = shift;
	my $line = msgPrefix()."(ERR) $msg";
	Mods::Toops::msgLogAppend( $line );
	print color( 'bold red' );
	print STDERR $line.EOL;
	print color( 'reset' );
	$TTPVars->{run}{exit_code} += 1;
}

# -------------------------------------------------------------------------------------------------
# prefix and log a message
sub msgLog {
	my $msg = shift;
	Mods::Toops::msgLogAppend( Mods::Toops::msgPrefix().$msg );
}

# -------------------------------------------------------------------------------------------------
# log an already prefixed message
# do not try to write in logs while they are not initialized
sub msgLogAppend {
	my $msg = shift;
	if( $TTPVars->{dyn}{logs_main} ){
		my $host = hostname;
		my $username = $ENV{LOGNAME} || $ENV{USER} || $ENV{USERNAME} || 'unknown'; #getpwuid( $< );
		my $line = localtime->strftime( '%Y-%m-%d %H:%M:%S' )." $host $username $msg";
		path( $TTPVars->{dyn}{logs_main} )->append_utf8( $line.EOL );
	}
}

# -------------------------------------------------------------------------------------------------
# Also logs msgOut or msgVerbose (or others) messages depending of:
# - whether the passed-in options have a truethy 'withLog'
# - whether the corresponding option is set in Toops site configuration
# - defaulting to truethy (Toops default is to log everything)
sub msgLogIf {
	# the ligne which has been printed
	my $msg = shift;
	# the caller options - we search here for a 'withLog' option
	my $opts = shift || {};
	# the key in site configuration
	my $key = shift || '';
	# where default is true
	my $withLog = true;
	if( exists( $opts->{withLog} )){
		$withLog = $opts->{withLog};
	} elsif( $key && $TTPVars->{config} && $TTPVars->{config}{site} && $TTPVars->{config}{site}{toops} && exists( $TTPVars->{config}{site}{toops}{$key} )){
		$withLog = $TTPVars->{config}{site}{toops}{$key};
	}
	if( $withLog ){
		Mods::Toops::msgLog( $msg );
	}
}

# -------------------------------------------------------------------------------------------------
# standard message on stdout
# (E):
# - the message to be printed
# - (optional) a hash options with 'withLog=true|false'
#   which override the site configuration , with itself overrides the Toops default which is true
sub msgOut {
	my $msg = shift;
	my $opts = shift || {};
	my $line = Mods::Toops::msgPrefix().$msg;
	print $line.EOL;
	Mods::Toops::msgLogIf( $line, $opts, 'msgOut' );
}

# -------------------------------------------------------------------------------------------------
# Compute the message prefix, including a trailing space
sub msgPrefix {
	my $prefix = '';
	if( $TTPVars->{run}{command}{basename} ){
		$prefix = "[$TTPVars->{run}{command}{basename}";
		$prefix .= ' '.$TTPVars->{run}{verb}{name} if $TTPVars->{run}{verb}{name};
		$prefix.= '] ';
	}
	return $prefix;
}

# -------------------------------------------------------------------------------------------------
# Verbose message
# (E):
# - the message to be printed
# - (optional) a hash options with following options:
#   > verbose=true|false
#     overrides the --verbose option of the running command/verb
#   > withLog=true|false
#     overrides the site configuration , with itself overrides the Toops default which is true
sub msgVerbose {
	my $msg = shift;
	my $opts = shift || {};
	my $line = Mods::Toops::msgPrefix()."(VERB) $msg";
	my $verbose = false;
	$verbose = $TTPVars->{run}{verbose} if exists( $TTPVars->{run}{verbose} );
	$verbose = $opts->{verbose} if exists( $opts->{verbose} );
	if( $verbose ){
		print color( 'bright_blue' );
		print $line.EOL;
		print color( 'reset' );
	}
	Mods::Toops::msgLogIf( $line, $opts, 'msgVerbose' );
}

# -------------------------------------------------------------------------------------------------
# Warning message - always logged
sub msgWarn {
	my $msg = shift;
	my $line = Mods::Toops::msgPrefix()."(WARN) $msg";
	Mods::Toops::msgLogAppend( $line );
	print color( 'bright_yellow' );
	print STDERR $line.EOL;
	print color( 'reset' );
}

# -------------------------------------------------------------------------------------------------
# Remove the trailing character
sub pathRemoveTrailingChar {
	my $line = shift;
	my $char = shift;
	if( substr( $line, -1 ) eq $char ){
		$line = substr( $line, 0, length( $line )-1 );
	}
	return $line;
}

# -------------------------------------------------------------------------------------------------
# Remove the trailing path separator
sub pathRemoveTrailingSeparator {
	my $dir = shift;
	my $sep = File::Spec->catdir( '' );
	return Mods::Toops::pathRemoveTrailingChar( $dir, $sep );
}

# -------------------------------------------------------------------------------------------------
# Run by the command
# Expects $0 be the full path name to the command script (this is the case in Windows+Strawberry)
# and @ARGV the command-line arguments
sub run {
	Mods::Toops::initSiteConfiguration();
	Mods::Toops::initLogs();
	Mods::Toops::msgLog( "executing $0 ".join( ' ', @ARGV ));
	Mods::Toops::initHostConfiguration();
	$TTPVars->{run}{command}{path} = $0;
	my @command_args = @ARGV;
	$TTPVars->{run}{command}{args} = \@command_args;
	my ( $volume, $directories, $file ) = File::Spec->splitpath( $TTPVars->{run}{command}{path} );
	my $command = $file;
	$TTPVars->{run}{command}{basename} = $command;
	$command =~ s/\.[^.]+$//;
	# make sure the command is not a reserved word
	if( grep( /^$command$/, @{$TTPVars->{Toops}{ReservedWords}} )){
		Mods::Toops::msgErr( "command '$command' is a Toops reserved word. Aborting." );
		Mods::Toops::ttpExit();
	}
	$TTPVars->{run}{command}{name} = $command;
	# the directory where are stored the verbs of the command
	my @dirs = File::Spec->splitdir( Mods::Toops::pathRemoveTrailingSeparator( $directories ));
	pop( @dirs );
	$TTPVars->{run}{command}{verbs_dir} = File::Spec->catdir( $volume, @dirs, $command );
	# prepare for the datas of the command
	$TTPVars->{$command} = {};
	# first argument is supposed to be the verb
	if( scalar @command_args ){
		$TTPVars->{run}{verb}{name} = shift( @command_args );
		$TTPVars->{run}{verb}{args} = \@command_args;
		# as verbs are written as Perl scripts, they are dynamically ran from here
		local @ARGV = @command_args;
		$TTPVars->{run}{help} = scalar @ARGV ? false : true;
		$TTPVars->{run}{verb}{path} = File::Spec->catdir( $TTPVars->{run}{command}{verbs_dir}, $TTPVars->{run}{verb}{name}.$TTPVars->{Toops}{verbSufix} );
		if( -f $TTPVars->{run}{verb}{path} ){
			do $TTPVars->{run}{verb}{path};
		} else {
			Mods::Toops::msgErr( "script not found or not readable: '$TTPVars->{run}{verb}{path}' (most probably, '$TTPVars->{run}{verb}{name}' is not a valid verb)" );
		}
	} else {
		Mods::Toops::doHelpCommand();
	}
}

# -------------------------------------------------------------------------------------------------
# exit the command
# Return code is optional, defaulting to exit_code
sub ttpExit {
	my $rc = shift || $TTPVars->{run}{exit_code};
	Mods::Toops::msgVerbose( "exiting with code $rc" );
	exit $rc;
}

# -------------------------------------------------------------------------------------------------
# Used by verbs to access our global variables
sub TTPVars {
	return $TTPVars;
}

# -------------------------------------------------------------------------------------------------
# whether help has been required
sub wantsHelp {
	return $TTPVars->{run}{help};
}

1;
