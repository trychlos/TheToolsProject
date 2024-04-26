# @(#) get the running status of a TTP daemon
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --json=<name>           the JSON file which characterizes this daemon [${json}]
# @(-) --bname=<name>          the JSON file basename [${bname}]
# @(-) --port=<port>           the port number to address [${port}]
# @(-) --[no]http              whether to publish an HTTP telemetry [${http}]
#
# @(@) The Tools Project is able to manage any daemons with these very same verbs.
# @(@) Each separate daemon is characterized by its own JSON properties which uniquely identifies it from the TTP point of view.
# @(@) This script accepts other options, after a '--' double dash, which will be passed to 'telemetry.pl publish' verb.
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

use File::Spec;

use TTP::Daemon;
use TTP::Finder;
use TTP::Path;

my $TTPVars = TTP::TTPVars();

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	json => '',
	bname => '',
	port => '',
	http => 'no'
};

my $opt_json = $defaults->{json};
my $opt_port = -1;
my $opt_http = false;

# -------------------------------------------------------------------------------------------------
# get a daemon status

sub doStatus {
	msgOut( "requesting the daemon for its status..." );
	my $dummy = $running->dummy() ? "-dummy" : "-nodummy";
	my $verbose = $running->verbose() ? "-verbose" : "-noverbose";
	my $cmd = "daemon.pl command -nocolored $dummy $verbose -command status -port $opt_port";
	msgVerbose( $cmd );
	my $res = `$cmd`;
	print "res='$res'".EOL;
	my $result = ( $res && length $res && $? == 0 );

	if( $opt_http ){
		my $value = $result ? "1" : "0";
		my $command = "telemetry.pl publish -value $value ".join( ' ', @ARGV )." -nomqtt -http -nocolored $dummy $verbose";
		msgVerbose( $command );
		my $stdout = `$command`;
		my $rc = $?;
		msgVerbose( $stdout );
		msgVerbose( "rc=$rc" );
	}
	if( $result ){
		print "$res";
		msgOut( "done" );
	} else {
		msgWarn( "no answer from the daemon" );
		msgErr( "NOT OK" );
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$ttp->{run}{help},
	"colored!"			=> \$ttp->{run}{colored},
	"dummy!"			=> \$ttp->{run}{dummy},
	"verbose!"			=> \$ttp->{run}{verbose},
	"json=s"			=> \$opt_json,
	"bname=s"			=> \$opt_bname,
	"port=i"			=> \$opt_port,
	"http!"				=> \$opt_http )){

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
msgVerbose( "found port='$opt_port'" );
msgVerbose( "found http='".( $opt_http ? 'true':'false' )."'" );

# either the json or the basename or the port must be specified (and not both)
my $count = 0;
$count += 1 if $opt_json;
$count += 1 if $opt_bname;
$count += 1 if $opt_port != -1;
if( $count == 0 ){
	msgErr( "one of '--json' or '--bname' or '--port' options must be specified, none found" );
} elsif( $count > 1 ){
	msgErr( "one of '--json' or '--bname' or '--port' options must be specified, several were found" );
}
#if a bname is specified, find the full filename
if( $opt_bname ){
	my $finder = TTP::Finder->new( $ttp );
	$opt_json = $finder->find({ dirs => [ TTP::Daemon->dirs(), $opt_bname ], wantsAll => false });
	if( !$opt_json ){
		msgErr( "unable to find a suitable daemon JSON configuration file for '$opt_bname'" );
	}
}
#if a json has been specified or has been found, must have a listeningPort and get it
if( $opt_json ){
	my $daemon = TTP::Daemon->new( $ttp, { path => $opt_json, messaging => false, runnable => { running => false }});
	if( $daemon->loaded()){
		$opt_port = $daemon->listeningPort();
	}
}

if( !TTP::errs()){
	doStatus();
}

TTP::exit();
