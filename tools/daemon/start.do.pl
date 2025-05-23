# @(#) start a TTP daemon
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --json=<name>           the JSON file which characterizes this daemon [${json}]
# @(-) --name=<name>           the daemon name [${name}]
#
# @(@) Note 1: TheToolsProject is able to manage any daemons with these very same verbs.
# @(@)         Each separate daemon is characterized by its own JSON properties which uniquely identifies it from the TTP point of view.
# @(@)         This script accepts other options, after a '--' double dash, which will be passed to the run daemon program.
# @(@) Note 2: "daemon.pl" command and all its verbs only act on the local node.
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

use File::Spec;

use TTP::DaemonConfig;
use TTP::RunnerDaemon;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	json => '',
	name => ''
};

my $opt_json = $defaults->{json};
my $opt_name = $defaults->{name};

# -------------------------------------------------------------------------------------------------
# start the daemon

sub doStart {
	msgOut( "starting the daemon from '$opt_json'..." );
	my $config = TTP::DaemonConfig->new( $ep, { jsonPath => $opt_json });
	if( $config->jsonLoaded()){
		if( TTP::RunnerDaemon->startDaemon( $config )){
			msgOut( "success" );
		} else {
			msgErr( "NOT OK" );
		}
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
	"json=s"			=> \$opt_json,
 	"name=s"			=> \$opt_name )){

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
msgVerbose( "got json='$opt_json'" );
msgVerbose( "got name='$opt_name'" );

# either the json or the basename must be specified (and not both)
my $count = 0;
$count += 1 if $opt_json;
$count += 1 if $opt_name;
if( $count == 0 ){
	msgErr( "one of '--json' or '--name' options must be specified, none found" );
} elsif( $count > 1 ){
	msgErr( "one of '--json' or '--name' options must be specified, several were found" );
}
# if a daemon name is specified, find the full filename of its configuration file
if( $opt_name ){
	my $finder = TTP::Finder->new( $ep );
	my $confFinder = TTP::DaemonConfig->confFinder();
	$opt_json = $finder->find({ dirs => [ $confFinder->{dirs}, $opt_name ], suffix => $confFinder->{suffix}, wantsAll => false });
	msgErr( "unable to find a suitable daemon JSON configuration file for '$opt_name'" ) if !$opt_json;
}

if( !TTP::errs()){
	doStart();
}

TTP::exit();
