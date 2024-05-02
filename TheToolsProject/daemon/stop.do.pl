# @(#) stop a TTP daemon
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --json=<name>           the JSON file which characterizes this daemon [${json}]
# @(-) --bname=<name>          the JSON file basename [${bname}]
# @(-) --port=<port>           the port number to address [${port}]
# @(-) --[no]ignore            ignore the return code if the daemon was not active [${ignore}]
# @(-) --[no]wait              wait for actual termination [${wait}]
# @(-) --timeout=<timeout>     timeout when waiting for termination [${termination}]
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
use Time::Piece;

use TTP::Daemon;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	json => '',
	bname => '',
	port => '',
	ignore => 'yes',
	wait => 'yes',
	timeout => 60
};

my $opt_json = $defaults->{json};
my $opt_bname = $defaults->{bname};
my $opt_port = -1;
my $opt_port_set = false;
my $opt_ignore = true;
my $opt_wait = true;
my $opt_timeout = $defaults->{timeout};

# -------------------------------------------------------------------------------------------------
# stop the daemon

sub doStop {
	msgOut( "requesting the daemon for termination..." );
	my $dummy = $running->dummy() ? "-dummy" : "-nodummy";
	my $verbose = $running->verbose() ? "-verbose" : "-noverbose";
	my $cmd = "daemon.pl command -nocolored $dummy $verbose -command terminate -port $opt_port";
	msgVerbose( $cmd );
	my $res = `$cmd`;
	# rc is zero if OK
	my $rc = $?;
	if( $res && length $res && !$rc ){
		$res = $running->filter( $res );
		print join( '\n', @{$res} ).EOL;
		my $result = true;
		if( $opt_wait ){
			$result = doWait( $res );
		}
		if( $result ){
			msgOut( "success" );
		} else {
			msgErr( "timeout while waiting for daemon termination" );
		}
	} else {
		if( $opt_ignore ){
			msgOut( "no answer from the daemon" );
			msgOut( "success" );
		} else {
			msgWarn( "no answer from the daemon" );
			msgErr( "NOT OK" );
		}
	}
}

# -------------------------------------------------------------------------------------------------
# wait for the daemon actual termination
# return true if the daemon is terminated, false else
# In dummy mode, just considers that the daemon has exited immediately

sub doWait {
	my ( $answer ) = @_;
	my $alive = true;
	if( $running->dummy()){
		msgDummy( "considering the daemon has immediately exited" );
		$alive = false,;
	} else {
		# get the pid of the answering daemon (first word of each line)
		my @w = split( /\s+/, $answer->[0] );
		my $pid = $w[0];
		msgLog( "waiting for '$pid' termination" );
		my $start = localtime;
		my $timedout = false;
		while( $alive && !$timedout ){
			$alive = kill( 0, $pid );
			if( $alive ){
				sleep( 1 );
				my $now = localtime;
				$timedout = ( $now - $start > $opt_timeout );
			}
		}
	}
	return !$alive;
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
	"port=i"			=> sub {
		my( $opt_name, $opt_value ) = @_;
		$opt_port = $opt_value;
		$opt_port_set = true;
	},
	"ignore!"			=> \$opt_ignore,
	"wait!"				=> \$opt_wait,
	"timeout=i"			=> \$opt_timeout )){

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
msgVerbose( "found port_set='".( $opt_port_set ? 'true':'false' )."'" );
msgVerbose( "found ignore='".( $opt_ignore ? 'true':'false' )."'" );
msgVerbose( "found wait='".( $opt_wait ? 'true':'false' )."'" );
msgVerbose( "found timeout='$opt_timeout'" );

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
	msgErr( "unable to find a suitable daemon JSON configuration file for '$opt_bname'" ) if !$opt_json;
}
#if a json has been specified or has been found, must have a listeningPort and get it
if( $opt_json ){
	my $daemon = TTP::Daemon->new( $ttp, { path => $opt_json, daemonize => false });
	if( $daemon->loaded()){
		$opt_port = $daemon->listeningPort();
	} else {
		msgErr( "unable to load a suitable daemon configuration for json='$opt_json'" );
	}
}
#if a port is set, must be greater than zero
msgErr( "when specified, addressed port must be greater than zero" ) if $opt_port <= 0;

if( !TTP::errs()){
	doStop();
}

TTP::exit();
