# @(#) display some daemon variables
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]confDirs          display the list of directories which may contain daemons configurations [${confDirs}]
# @(-) --[no]execDirs          display the list of directories which may contain daemons executables [${execDirs}]
# @(-) --json=<name>           the JSON file to operate on when requesting by keys [${json}]
# @(-) --name=<name>           the daemon name to operate on when requesting by keys [${name}]
# @(-) --key=<name[,...]>      the key which addresses the desired value, may be specified several times or as a comma-separated list [${key}]
#
# @(@) daemon.pl command and all its verbs only work on the local node.
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

use TTP::DaemonConfig;
use TTP::Finder;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	confDirs => 'no',
	execDirs => 'no',
	json => '',
	name => '',
	key => ''
};

my $opt_confDirs = false;
my $opt_execDirs = false;
my $opt_json = $defaults->{json};
my $opt_name = $defaults->{name};
my @opt_keys = ();

# the daemon config when requesting by keys
my $daemonConfig = undef;

# -------------------------------------------------------------------------------------------------
# Display the value accessible through the route of the provided successive keys

sub listByKeys {
	my $value = $daemonConfig->var( \@opt_keys );
	print "  [".join( ',', @opt_keys )."]: ".( defined( $value ) ? ( ref( $value ) ? Dumper( $value ) : $value.EOL ) : "(undef)".EOL );
}

# -------------------------------------------------------------------------------------------------
# list confDirs value - e.g. 'C:\INLINGUA\configurations\daemons'

sub listConfdirs {
	my $dirs = [];
	my @roots = split( /$Config{path_sep}/, $ENV{TTP_ROOTS} );
	my $specs = TTP::DaemonConfig->confFinder()->{dirs};
	foreach my $it ( @roots ){
		foreach my $sub ( @{$specs} ){
			push( @{$dirs}, File::Spec->catdir( $it, $sub ));
		}
	}
	my $str = "confDirs: [".( join( ',', @{$dirs} ))."]";
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# list execDirs value - e.g. 'TOOLS/libexec/daemons'

sub listExecdirs {
	my $dirs = [];
	my @roots = split( /$Config{path_sep}/, $ENV{TTP_ROOTS} );
	my $specs = TTP::DaemonConfig->execFinder()->{dirs};
	foreach my $it ( @roots ){
		foreach my $sub ( @{$specs} ){
			push( @{$dirs}, File::Spec->catdir( $it, $sub ));
		}
	}
	my $str = "execDirs: [".( join( ',', @{$dirs} ))."]";
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
	"confDirs!"			=> \$opt_confDirs,
	"execDirs!"			=> \$opt_execDirs,
	"json=s"			=> \$opt_json,
	"name=s"			=> \$opt_name,
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
msgVerbose( "got confDirs='".( $opt_confDirs ? 'true':'false' )."'" );
msgVerbose( "got execDirs='".( $opt_execDirs ? 'true':'false' )."'" );
msgVerbose( "got json='$opt_json'" );
msgVerbose( "got name='$opt_name'" );
@opt_keys= split( /,/, join( ',', @opt_keys ));
msgVerbose( "got keys='".join( ',', @opt_keys )."'" );

# when requesting keys, they must be addressed inside of a daemon configuration, so have a json or a name
if( scalar( @opt_keys )){
	my $count = 0;
	$count += 1 if $opt_json;
	$count += 1 if $opt_name;
	if( $count == 0 ){
		msgErr( "one of '--json' or '--name' options must be specified when requesting by keys, none found" );
	} elsif( $count > 1 ){
		msgErr( "one of '--json' or '--name' options must be specified when requesting by keys, both were found" );
	}
	# if a daemon name is specified, find the full filename of the JSON configuration file
	if( $opt_name ){
		my $finder = TTP::Finder->new( $ep );
		my $confFinder = TTP::DaemonConfig->confFinder();
		$opt_json = $finder->find({ dirs => [ $confFinder->{dirs}, $opt_name ], suffix => $confFinder->{suffix}, wantsAll => false });
		msgErr( "unable to find a suitable daemon JSON configuration file for '$opt_name'" ) if !$opt_json;
	}
	# if a json has been specified or has been found, must be loadable
	if( $opt_json ){
		$daemonConfig = TTP::DaemonConfig->new( $ep, { jsonPath => $opt_json, checkConfig => false });
		if( !$daemonConfig->jsonLoaded()){
			msgErr( "unable to load a suitable daemon configuration for json='$opt_json'" );
		}
	}
}

# warn if no option has been requested
msgWarn( "none of '--confDirs', '--execDirs', '--key' options has been requested, nothing to do" ) if !$opt_confDirs && !$opt_execDirs && !scalar( @opt_keys );

if( !TTP::errs()){
	listConfdirs() if $opt_confDirs;
	listExecdirs() if $opt_execDirs;
	listByKeys() if scalar @opt_keys;
}

TTP::exit();
