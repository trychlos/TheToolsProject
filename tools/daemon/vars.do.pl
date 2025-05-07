# @(#) display some daemon variables
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]confDirs          display the list of directories which may contain daemons configurations [${confDirs}]
# @(-) --[no]execDirs          display the list of directories which may contain daemons executables [${execDirs}]
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

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	confDirs => 'no',
	execDirs => 'no'
};

my $opt_confDirs = false;
my $opt_execDirs = false;

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
	"execDirs!"			=> \$opt_execDirs )){

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

if( !TTP::errs()){
	listConfdirs() if $opt_confDirs;
	listExecdirs() if $opt_execDirs;
}

TTP::exit();
