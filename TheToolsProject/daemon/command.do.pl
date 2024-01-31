# @(#) send a command to a running daemon
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --json=<name>           the JSON file which characterizes this daemon [${json}]
# @(-) --bname=<name>          the JSON file basename [${bname}]
# @(-) --port=<port>           the port number to address [${port}]
# @(-) --command=<command>     the command to be sent to the daemon [${command}]
#
# @(@) A command is a simple string. The daemon is expected to (at least) acknowledge it.
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

use IO::Socket::INET;

# auto-flush on socket
$| = 1;

use TTP::Daemon;
use TTP::Finder;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	json => '',
	bname => '',
	port => '',
	command => ''
};

my $opt_json = $defaults->{json};
my $opt_bname = $defaults->{bname};
my $opt_port = -1;
my $opt_port_set = false;
my $opt_command = $defaults->{command};

# -------------------------------------------------------------------------------------------------
# send a command to the daemon

sub doSend {
	# in dummy mode, just simulate and output the acknowledge
	if( $running->dummy()){
		msgDummy( "OK" );

	# connect, triggering an error if the daemon is not active
	} else {
		my $socket = new IO::Socket::INET(
			PeerHost => 'localhost',
			PeerPort => $opt_port,
			Proto => 'tcp',
			Type => SOCK_STREAM
		) or msgErr( "unable to connect: $!" ) if !$socket;

		# send the command
		if( $socket ){
			my $size = $socket->send( $opt_command );
			msgVerbose( "sent '$opt_command' to the server ($size bytes)" );
			# notify server that request has been sent
			$socket->shutdown( SHUT_WR );
			# receive a response of up to 4096 characters from server
			my $response = "";
			while( !isOk( $response )){
				$socket->recv( $response, 4096 );
				chomp $response;
				print "$response".EOL;
				msgLog( $response );
			}
			$socket->close();
		}
	}
	if( TTP::errs()){
		msgErr( "NOT OK" );
	} else {
		msgOut( "success" );
	}
}

# -------------------------------------------------------------------------------------------------
# whether the received answer is just 'OK'

sub isOk {
	my ( $answer ) = @_;
	my @lines = split( /[\r\n]+/, $answer );
	foreach my $line ( @lines ){
		return true if $line =~ m/^[0-9]+\s+OK/;
	}
	return false;
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
	"command=s"			=> \$opt_command )){

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
msgVerbose( "found command='$opt_command'" );

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

# must have a command too
msgErr( "'--command' option is mandatory, but is not specified" ) if !$opt_command;

if( !TTP::errs()){
	doSend();
}

TTP::exit();
