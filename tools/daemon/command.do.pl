# @(#) send a command to a running daemon and print the received answer until 'OK'
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --json=<name>           the JSON file which characterizes this daemon [${json}]
# @(-) --name=<name>           the daemon name [${name}]
# @(-) --port=<port>           the port number to address [${port}]
# @(-) --command=<command>     the command to be sent to the daemon [${command}]
# @(-) --timeout=<timeout>     command timeout in sec. [${timeout}]
#
# @(@) A command is a simple string. The daemon is expected to (at least) acknowledge it.
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

use IO::Socket::INET;
use Time::Moment;

# auto-flush on socket
$| = 1;

use TTP::Finder;
use TTP::RunnerDaemon;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	json => '',
	name => '',
	port => '',
	command => '',
	timeout => 10
};

my $opt_json = $defaults->{json};
my $opt_name = $defaults->{name};
my $opt_port = -1;
my $opt_port_set = false;
my $opt_command = $defaults->{command};
my $opt_timeout = $defaults->{timeout};

# -------------------------------------------------------------------------------------------------
# send a command to the daemon

sub doSend {
	# in dummy mode, just simulate and output the acknowledge
	if( $ep->runner()->dummy()){
		msgDummy( "OK" );

	# connect, triggering an error if the daemon is not active
	} else {
		my $socket = new IO::Socket::INET(
			PeerHost => 'localhost',
			PeerPort => $opt_port,
			Proto => 'tcp',
			Type => SOCK_STREAM
		) or msgErr( "unable to connect: $!" );

		# send the command
		if( $socket ){
			my $size = $socket->send( $opt_command );
			msgVerbose( "sent '$opt_command' to the server ($size bytes)" );
			# notify server that request has been sent
			$socket->shutdown( SHUT_WR );
			# receive a response of up to 4096 characters from server
			# print the received (non-empty) lines until got OK
			my $start = Time::Moment->now;
			my $timedout = false;
			my $ok = getAnswerOk( $socket );
			while( !$ok && !$timedout ){
				sleep( 1 );
				my $now = Time::Moment->now;
				$timedout = ( $now->epoch - $start->epoch > $opt_timeout );
				if( !$timedout ){
					$ok = getAnswerOk( $socket );
				}
			}
			if( $timedout ){
				msgErr( "OK answer not received after $opt_timeout sec." );
			}
			$socket->close();
			if( !$timedout ){
				msgOut( "success" );
			}
		}
	}
}

# -------------------------------------------------------------------------------------------------
# get an answer from the daemon
# print the response until got 'OK'
# returns true if found

sub getAnswerOk {
	my ( $socket ) = @_;
	my $response = "";
	$socket->recv( $response, 4096 );
	my $hasOk = false;
	my @lines = split( /[\r\n]+/, $response );
	foreach my $line ( @lines ){
		$hasOk = true if $line =~ m/^[0-9]+\s+OK/;
		chomp $line;
		if( $line ){
			print "$line".EOL;
			msgLog( $line );
		}
	}
	return $hasOk;
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
	"name=s"			=> \$opt_name,
	"port=i"			=> sub {
		my( $opt_name, $opt_value ) = @_;
		$opt_port = $opt_value;
		$opt_port_set = true;
	},
	"command=s"			=> \$opt_command,,
	"timeout=i"			=> \$opt_timeout )){

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
msgVerbose( "got port='$opt_port'" );
msgVerbose( "got port_set='".( $opt_port_set ? 'true':'false' )."'" );
msgVerbose( "got command='$opt_command'" );
msgVerbose( "got timeout='$opt_timeout'" );

# either the json or the basename or the port must be specified (and not both)
my $count = 0;
$count += 1 if $opt_json;
$count += 1 if $opt_name;
$count += 1 if $opt_port != -1;
if( $count == 0 ){
	msgErr( "one of '--json' or '--name' or '--port' options must be specified, none found" );
} elsif( $count > 1 ){
	msgErr( "one of '--json' or '--name' or '--port' options must be specified, several were found" );
}
# if a daemon name is specified, find the full JSON filename
if( $opt_name ){
	my $finder = TTP::Finder->new( $ep );
	$opt_json = $finder->find({ dirs => [ TTP::RunnerDaemon->dirs(), $opt_name ], sufix => TTP::RunnerDaemon->finder()->{sufix}, wantsAll => false });
	msgErr( "unable to find a suitable daemon JSON configuration file for '$opt_name'" ) if !$opt_json;
}
# if a json has been specified or has been found, must have a listeningPort and get it
if( $opt_json ){
	my $daemon = TTP::RunnerDaemon->new( $ep, { path => $opt_json, daemonize => false });
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
