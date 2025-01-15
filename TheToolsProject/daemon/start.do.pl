# @(#) start a TTP daemon
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --json=<name>           the JSON file which characterizes this daemon [${json}]
# @(-) --bname=<name>          the JSON file basename [${bname}]
#
# @(@) The Tools Project is able to manage any daemons with these very same verbs.
# @(@) Each separate daemon is characterized by its own JSON properties which uniquely identifies it from the TTP point of view.
# @(@) This script accepts other options, after a '--' double dash, which will be passed to the run daemon program.
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

use utf8;
use strict;
use warnings;

use File::Spec;

use TTP::Daemon;
my $running = $ep->runner();

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	json => '',
	bname => ''
};

my $opt_json = $defaults->{json};
my $opt_bname = $defaults->{bname};

# -------------------------------------------------------------------------------------------------
# start the daemon

sub doStart {
	msgOut( "starting the daemon from '$opt_json'..." );
	my $daemon = TTP::Daemon->new( $ep, { path => $opt_json, daemonize => false });
	if( $daemon->loaded()){
		if( $daemon->start()){
			msgOut( "success" );
		} else {
			msgErr( "NOT OK" );
		}
	} else {
		msgErr( "unable to load the '$opt_json' specified configuration file" );
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$ep->{run}{help},
	"colored!"			=> \$ep->{run}{colored},
	"dummy!"			=> \$ep->{run}{dummy},
	"verbose!"			=> \$ep->{run}{verbose},
	"json=s"			=> \$opt_json,
 	"bname=s"			=> \$opt_bname )){

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
msgVerbose( "found json='$opt_json'" );
msgVerbose( "found bname='$opt_bname'" );

# either the json or the basename must be specified (and not both)
my $count = 0;
$count += 1 if $opt_json;
$count += 1 if $opt_bname;
if( $count == 0 ){
	msgErr( "one of '--json' or '--bname' options must be specified, none found" );
} elsif( $count > 1 ){
	msgErr( "one of '--json' or '--bname' options must be specified, several were found" );
}
#if a bname is specified, find the full filename
if( $opt_bname ){
	my $finder = TTP::Finder->new( $ep );
	$opt_json = $finder->find({ dirs => [ TTP::Daemon->dirs(), $opt_bname ], wantsAll => false });
	msgErr( "unable to find a suitable daemon JSON configuration file for '$opt_bname'" ) if !$opt_json;
}

if( !TTP::errs()){
	doStart();
}

TTP::exit();
