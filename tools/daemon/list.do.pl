# @(#) List available configurations
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]json              display available JSON configuration files [${json}]
# @(-) --[no]check             whether to check the loaded configurations [${check}]
#
# @(@) Dummy mode is honored here by using msgWarn() instead of msgErr() when checking the JSON daemon configurations
# @(@) (if '--check' option has been set). Please be conscious that any of these two options may so return a different
# @(@) result set of the one returned by the standard (default) run.
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

use TTP::Daemon;
use TTP::Finder;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	json => 'no',
	check => 'no'
};

my $opt_json = false;
my $opt_check = false;

# -------------------------------------------------------------------------------------------------
# display available JSON configuration files in ASCII order, once for each basename

sub doListJSON {
	msgOut( "displaying available JSON configuration files..." );
	my $count = 0;
	my $findable = {
		dirs => [ TTP::Daemon->dirs() ],
		glob => '*'.TTP::Daemon->finder()->{sufix}
	};
	my $finder = TTP::Finder->new( $ep );
	my $jsons = $finder->find( $findable );
	# only keep first enabled found for each basename
	my $kepts = {};
	foreach my $it ( @{$jsons} ){
		my $daemon = TTP::Daemon->new( $ep, { path => $it, checkConfig => $opt_check, daemonize => false });
		my $name = $daemon->name();
		$kepts->{$name} = $it if !exists( $kepts->{$name} ) && $daemon->loaded();
	}
	# and list in ascii order
	foreach my $it ( sort keys %{$kepts} ){
		print " $kepts->{$it}".EOL;
		$count += 1;
	}
	msgOut( "$count found daemon JSON configuration file(s)" );
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> sub { $ep->runner()->help( @_ ); },
	"colored!"			=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"			=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"			=> sub { $ep->runner()->verbose( @_ ); },
	"json!"				=> \$opt_json,
	"check!"			=> \$opt_check )){

		msgOut( "try '".$ep->runner()->command()." ".$ep->runner()->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $ep->runner()->help()){
	$ep->runner()->verbHelp( $defaults );
	TTP::exit();
}

msgVerbose( "got colored='".( $ep->runner()->colored() ? 'true':'false' )."'" );
msgVerbose( "got dummy='".( $ep->runner()->dummy() ? 'true':'false' )."'" );
msgVerbose( "got verbose='".( $ep->runner()->verbose() ? 'true':'false' )."'" );
msgVerbose( "got json='".( $opt_json ? 'true':'false' )."'" );
msgVerbose( "got check='".( $opt_check ? 'true':'false' )."'" );

msgWarn( "no action as '--json' option is not set" ) if !$opt_json;

if( !TTP::errs()){
	doListJSON() if $opt_json;
}

TTP::exit();
