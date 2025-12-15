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
#
# http.pl compare daemon interface.
# This instance is part of the parent process, and is used to talk with an associated daemon.

package TTP::HTTP::Compare::DaemonInterface;
die __PACKAGE__ . " must be loaded as TTP::HTTP::Compare::DaemonInterface\n" unless __PACKAGE__ eq 'TTP::HTTP::Compare::DaemonInterface';

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Data::Dumper;
use IO::Socket::INET;
use JSON;
use Path::Tiny;
use Scalar::Util qw( blessed );
use Time::Moment;

use TTP;
use vars::global qw( $ep );

use TTP::Constants qw( :all );
use TTP::HTTP::Compare::Facer;
use TTP::Message qw( :all );

use constant {
};

my $Const = {
    length_limit => 255
};

### Private methods

# -------------------------------------------------------------------------------------------------
# Start the daemon
# (I):
# - nothing, all arguments having been stored by the constructor or by the parent role
# (O):
# - does not return anything
#   but the result execution of the 'daemon.pl start' command is stored in this object

sub _start {
    my ( $self ) = @_;

    my $role = $self->facer()->roleName();
    my $which = $self->facer()->which();
    my $port = $self->facer()->port();
    my $url = $self->facer()->baseUrl();

	# have a temporary binary file to handle config serialization
	my $bin = TTP::getTempFileName({ suffix => "_${which}_bin" });
	my $conf = $self->facer()->conf()->snapshot();
	open my $fh, '>:raw', $bin or die "$bin: $!";
	print $fh $conf;
	close $fh;

	# build a temporary json file which acts as the daemon configuration
	my $json = TTP::getTempFileName({ suffix => "_${which}_json" });
	my $content = {
		enabled => true,
		execPath => $self->facer()->compareArgs()->{worker},
		listeningPort => $port,
		listeningInterval => 500,
		messagingInterval => -1,
		httpingInterval => -1,
		textingInterval => -1,
		# http.pl compare specifics
		compare => {
			binConf => $bin,
			roleName => $role,
			roleDir => $self->facer()->roleDir(),
			which => $which,
			args => $self->facer()->compareArgs()->{args},
			baseUrl => $url
		}
	};
	path( $json )->spew_utf8( encode_json( $content ));

	# build and execute the command to start the daemon
	my $command = "daemon.pl start --json $json --verbose";
	my $res = TTP::commandExec( $command );

	# gather some useful properties (or advertise of an error)
	if( $res->{success} ){
		$res->{setup} = {
			json => $json,
			bin => $bin,
			port => $port
		};
	} else {
		msgErr( "by '$role:$which' DaemonInterface::start() unable to start daemon (json='$json' port='$port' which='$which')" );
	}

    $self->{_start} = $res;
}

### Public methods

# -------------------------------------------------------------------------------------------------
# Returns the initiating facer interface

sub facer {
    my ( $self ) = @_;

	return $self->{_facer};
}

# -------------------------------------------------------------------------------------------------
# get the answer (if any) to the specified daemon
# all commands must at least acnowledge by sending back a single 'OK' line
# NB: waiting for an answer is a blocking call for the site - this is fine as all commands have been
#  previously sent to each site, and both site have to be waited.
# (I):
# - the socket allocated when sending the command
# (O):
# - the received (JSON-decoded) answer, or true if the response is empty, or undef for an error

sub get_answer {
	my ( $self, $socket ) = @_;

    my $role = $self->facer()->roleName();
    my $which = $self->facer()->which();
    msgVerbose( "by '$role:$which' DaemonInterface::get_answer() socket=".( $socket // '(undef)' ));
    return undef if !$socket;

    my $start = Time::Moment->now;
    my $first = true;
    my $verboseReceived = $self->facer()->conf()->confVerbosityDaemonReceived() ? \&msgVerbose : \&msgLog;
    my $verboseSleep = $self->facer()->conf()->confVerbosityDaemonSleep() ? \&msgVerbose : \&msgLog;
    my $answerTimeout = $self->facer()->conf()->confBrowserTimeoutsGetAnswer();
    my $answer = {
        response => "",
        ok => false,
        timedout => false,
        received => false
    };
    do {
        # sleep if not the first call and have not received anything in the last round
        if( $first ){
            $first = false;
        } elsif( !$answer->{received} ){
            $verboseSleep->( "by '$role:$which' DaemonInterface::get_answer() sleeping 1 sec" );
            sleep( 1 );
        }
        # expect something
        _get_answer_part( $socket, $answer );
        # check not yet timed out
        my $now = Time::Moment->now;
        $answer->{timedout} = ( $now->epoch - $start->epoch > $answerTimeout );
    }
      while( !$answer->{ok} && !$answer->{timedout} );

    if( $answer->{timedout} ){
        msgErr( "by '$role:$which' DaemonInterface::get_answer() OK answer not received after $answerTimeout sec." );
    }
    $socket->close();
    if( !$answer->{timedout} ){
        msgVerbose( "by '$role:$which' DaemonInterface::get_answer() success" );
    }

    #print STDERR "answer ".Dumper( $answer );
	my $res = $answer->{ok} ? ( $answer->{response} ? decode_json( $answer->{response} )->{answer} : true ) : undef;
    if( $answer->{ok} ){
        if( $answer->{response} ){
            $verboseReceived->( "by '$role:$which' DaemonInterface::get_answer() got answer length=".length( $answer->{response} ));
        } else {
            $verboseReceived->( "by '$role:$which' DaemonInterface::get_answer() got answer='true'" );
        }
    } else {
        $verboseReceived->( "by '$role:$which' DaemonInterface::get_answer() got no answer" );
    }

    #print STDERR "result ".Dumper( $res );
    return $res;
}

# browser methods which do not return any value must at least returns an 'OK' acknowledge
# else returns the expected value as JSON data, ending with an 'OK' single line

sub _get_answer_part {
	my ( $socket, $answer ) = @_;

    # get something
	my $buffer = "";
    sysread( $socket, $buffer, 8192 );
    $answer->{received} = length( $buffer );

    # check whether last line is single 'OK'
    # else concatenate to global response
    if( $answer->{received} ){
        my @lines = split( /[\r\n]+/, $buffer );
        for( my $i=0; $i<=$#lines ; ++$i ){
            my $line = $lines[$i];
            chomp $line;
            $line =~ s/^[0-9]+\s+//;
            if( $i == $#lines && $line eq 'OK' ){
                $answer->{ok} = true;
            } else {
                $answer->{response} .= $line;
            }
        }
    }
}

# -------------------------------------------------------------------------------------------------
# send a command and wait for the answer
# (I):
# - the command
# - an optional arguments hash to be passed with the command
# - an optional options hash with following keys:
#   > send_timeout: the timeout to be applied when sending the command
# (O):
# - the socket used to send the request

sub send_and_get {
    my ( $self, $command, $args, $opts ) = @_;

    my $socket = $self->send_command( $command, $args, $opts );
    my $answer = $socket ? $self->get_answer( $socket ) : false;

    return $answer;
}

# -------------------------------------------------------------------------------------------------
# send a command to the specified daemon
# do NOT wait for the answer
# do not use daemon.pl command first to be more efficient, second to more easily pass arguments
# (I):
# - the requested method
# - an optional arguments hash to be passed with the command
# - an optional options hash with following keys:
#   > timeout: the timeout to be applied to this operation
# (O):
# - the used socket in which we will wait for the answer

sub send_command {
    my ( $self, $command, $args, $opts ) = @_;
    $args //= {};
    $opts //= {};

    my $role = $self->facer()->roleName();
    my $which = $self->facer()->which();
    my $data = encode_json( $args );
    if( length( $data ) > $Const->{length_limit} ){
        msgVerbose( "by '$role:$which' DaemonInterface::command() sending '$command' with ".length( $data )." data bytes" );
    } else {
        msgVerbose( "by '$role:$which' DaemonInterface::command() sending '$command $data'" );
    }

    my $start = Time::Moment->now;
    my $timedout = false;
    my $first = true;
    my $socket = undef;
    my $verboseSleep = $self->facer()->conf()->confVerbosityDaemonSleep() ? \&msgVerbose : \&msgLog;
    my $sendTimeout = $opts->{timeout} // $self->facer()->conf()->confBrowserTimeoutsSendCommand();

    do {
        # sleep if not the first call
        if( $first ){
            $first = false;
        } else {
            $verboseSleep->( "by '$role:$which' DaemonInterface::command() sleeping 1 sec" );
            sleep( 1 );
        }
        # try to get a socket
        $socket = IO::Socket::INET->new(
            PeerHost => 'localhost',
            PeerPort => $self->facer()->port(),
            Proto => 'tcp',
            Type => SOCK_STREAM
        );
        # check not yet timed out
        if( !$socket ){
            my $now = Time::Moment->now;
            $timedout = ( $now->epoch - $start->epoch > $sendTimeout );
            msgWarn( "by '$role:$which' DaemonInterface::command() timed out after $sendTimeout sec." ) if $timedout;
        }
    }
      while( !$socket && !$timedout );

	# send the command
	if( $socket ){
        $socket->blocking( false );
		my $size = $socket->send( "$command $data" );
		# notify server that request has been sent
		$socket->shutdown( SHUT_WR );

	} else {
        msgErr( "by '$role:$which' DaemonInterface::command() unable to connect: $!" );
    }

	return $socket;
}

# -------------------------------------------------------------------------------------------------
# terminate a daemon
# (I):
# - nothing
# (O):
# - true|false

sub terminate {
    my ( $self ) = @_;

    my $role = $self->facer()->roleName();
    my $which = $self->facer()->which();

    msgVerbose( "by '$role:$which' DaemonInterface::terminate() terminating..." );

    my $res = TTP::commandExec( "daemon.pl stop -json $self->{_start}{setup}{json}" );

    return $res->{success};
}

# -------------------------------------------------------------------------------------------------
# at startup wait for the daemon be ready
# (I):
# - nothing
# (O):
# - true|false

sub wait_ready {
    my ( $self ) = @_;

    my $res = $self->send_and_get( "internal_status" );

    return $res;
}

### Class methods

# -------------------------------------------------------------------------------------------------
# Constructor
# (I):
# - the TTP::EP entry point
# - the TTP::HTTP::Compare::Facer instance
# (O):
# - this object

sub new {
	my ( $class, $ep, $facer ) = @_;
	$class = ref( $class ) || $class;

	if( !$facer || !blessed( $facer ) || !$facer->isa( 'TTP::HTTP::Compare::Facer' )){
		msgErr( "unexpected facer: ".TTP::chompDumper( $facer ));
		TTP::stackTrace();
	}

	my $self = $class->SUPER::new( $ep );
	bless $self, $class;
	msgDebug( __PACKAGE__."::new()" );

	$self->{_facer} = $facer;

    # start the daemon itself, which will itself instanciate a chromedriver browser, connect it, log-in into the site
    $self->_start();

	return $self;
}

### Global functions
### Note for the developer: while a global function doesn't take any argument, it can be called both
### as a class method 'TTP::Package->method()' or as a global function 'TTP::Package::method()',
### the former being preferred (hence the writing inside of the 'Class methods' block which brings
### the class as first argument).

# -------------------------------------------------------------------------------------------------
# Execute a command on all the specified interfaces, simultaneously waiting for the result on each 
#  got sockets - returns when we have got the two results
# (I):
# - the calling TTP::HTTP::Compare::Role instance
# - the command
# - an arguments hash to be passed to the command, can be undef (but must then be specified as such)
# - a hash of the interfaces the command is to be executed on as:
#   > name => DaemonInterface instance
# - an optional replay hash where each key can be sent back by the called work, and trigger an action.
#   For example, if the called work wants triger a relogin, it may return 'relogin' string; if the
#   parent caller has provided a 'relogin' code ref in this options hash, then the code ref will be
#   executed, and an answer will be waited for again; this behavior is allowed to happen only once a time
#   The provided code reference is called with arguments:
#   > the command
#   > the arguments hash
#   > the interfaces
#   > the results
#   > the involved key name in both interfaces and results
#   and should return true|false.
# - an optional options hash with following keys:
#   > execute_timeout: the timeout to be applied to this execute() function
#   > send_timeout: the timeout to be applied when sending the command
#   > get_timeout: the timeout to be applied when getting the answer
# (O):
# - a hash with same keys ('name' above) and following keys:
#   > __PACKAGE__: an internal hash which in particularly handles the opened socket
#   > result: a hash with following keys:
#     - success: true|false
#       this is only a technical indication of the communication, and NOT AT ALL the result of the command itself
#     - reason: only set if success is false, and reason can be:
#       'interface': the specified interface object is not a DaemonInterface instace
#       'socket': unable to open a socket to the daemon in order to send the command
#       'timeout': timeout while waiting for the response
#       'coderef:<replay>': a replay request has been received, but we do not have an ad-hoc coderef
#       'replay:<replay>': a replay request is called more than once
#       'sub:<replay>': the provided CODE ref has returned false
#   > answer: the response which may have been received from the daemon
#     when a response is received, success is considered true
#     can be undef with a success 'true' when the daemon has only acknowledged the command, without
#     returning back any data

sub execute {
	my ( $role, $command, $args, $interfaces, $replay, $opts ) = @_;

    $interfaces //= {};
    $replay //= {};
    $opts //= {};
    my $results = {};
    my $PACKAGE = __PACKAGE__;

    # send the commands to each specified DaemonInterface
    foreach my $name ( sort keys %{$interfaces} ){
        $results->{$name} //= {};
        $results->{$name}{$PACKAGE} //= {};
        $results->{$name}{$PACKAGE}{ended} = false;
        $results->{$name}{result} //= {};
        $results->{$name}{result}{success} = false;
        if( !$interfaces->{$name} || !blessed( $interfaces->{$name} ) || !$interfaces->{$name}->isa( 'TTP::HTTP::Compare::DaemonInterface' )){
            $results->{$name}{$PACKAGE}{ended} = true;
            $results->{$name}{result}{reason} = 'interface';
        } else {
            $opts->{timeout} = $opts->{send_timeout} if defined( $opts->{send_timeout} );
            $results->{$name}{$PACKAGE}{socket} = $interfaces->{$name}->send_command( $command, $args, $opts );
            if( $results->{$name}{$PACKAGE}{socket} ){
                $results->{$name}{$PACKAGE}{first} = true;
                $results->{$name}{$PACKAGE}{start} = time();
                $results->{$name}{$PACKAGE}{role} = $role->name();
                $results->{$name}{$PACKAGE}{which} = $interfaces->{$name}->facer()->which();
                $results->{$name}{$PACKAGE}{response} = "";
                $results->{$name}{$PACKAGE}{replay} = {};
            } else {
                $results->{$name}{$PACKAGE}{ended} = true;
                $results->{$name}{result}{reason} = 'socket';
            }
        }
    }

    # wait simultaneously on all opened sockets while we are still waiting for something
    my $not_ended_count;
    do {
        $not_ended_count = 0;
        foreach my $name ( sort keys %{$interfaces} ){
            if( !$results->{$name}{$PACKAGE}{ended} ){
                $not_ended_count += 1;

                my $id_label = "$results->{$name}{$PACKAGE}{role}:$results->{$name}{$PACKAGE}{which}";
                my $verboseReceived = $interfaces->{$name}->facer()->conf()->confVerbosityDaemonReceived() ? \&msgVerbose : \&msgLog;
                my $verboseSleep = $interfaces->{$name}->facer()->conf()->confVerbosityDaemonSleep() ? \&msgVerbose : \&msgLog;
                my $answerTimeout = $opts->{get_timeout} // $interfaces->{$name}->facer()->conf()->confBrowserTimeoutsGetAnswer();
                my $executeTimeout = $opts->{execute_timeout} // $interfaces->{$name}->facer()->conf()->confBrowserTimeoutsExecute();

                # sleep if not the first call and have not received anything in the last round
                if( $results->{$name}{$PACKAGE}{first} ){
                    $results->{$name}{$PACKAGE}{first} = false;
                } elsif( !$results->{$name}{$PACKAGE}{received} ){
                    $verboseSleep->( "by '$id_label' DaemonInterface::execute() sleeping 1.0 sec" );
                    sleep( 1.0 );
                }

                # expect something
                # set ok, response, received data
                _get_answer_part( $results->{$name}{$PACKAGE}{socket}, $results->{$name}{$PACKAGE} );
                $verboseReceived->( "by '$id_label' DaemonInterface::execute() received $results->{$name}{$PACKAGE}{received} bytes" );

                # if we have received the 'OK' line, then answer is terminated
                # if the received answer is a scalar which is a key of the 'replay' hash, then this is a replay request
                if( $results->{$name}{$PACKAGE}{ok} ){
                    # be verbose about the received answer
                    if( length( $results->{$name}{$PACKAGE}{response} ) > $Const->{length_limit} ){
                        $verboseReceived->( "by '$id_label' DaemonInterface::execute() received ".length( $results->{$name}{$PACKAGE}{response} )." bytes" );
                    } else {
                        $verboseReceived->( "by '$id_label' DaemonInterface::execute() received '$results->{$name}{$PACKAGE}{response}'" );
                    }
                    my $done = false;
                    if( length( $results->{$name}{$PACKAGE}{response} )){
                        my $received = decode_json( $results->{$name}{$PACKAGE}{response} )->{answer};
                        # is it a replay request ?
                        if( $received && !ref( $received ) && $replay->{$received} ){
                            $results->{$name}{$PACKAGE}{replay}{$received} //= {};
                            msgVerbose( "by '$id_label' DaemonInterface::execute() got replay request '$received'" );
                            # replay request already called last time
                            #print STDERR "before replay ".Dumper( $replay );
                            #print STDERR "before ".Dumper( $results->{$name} );
                            if( $results->{$name}{$PACKAGE}{replay}{$received}{replay} ){
                                $results->{$name}{$PACKAGE}{ended} = true;
                                $results->{$name}{result}{reason} = "replay:$received";
                                msgErr( "by '$id_label' DaemonInterface::execute() detected replay loop for '$received'" );
                            } else {
                                # first time request replay
                                my $sub = $replay->{$received};
                                my $ref = ref( $sub );
                                if( $ref eq 'CODE' ){
                                    $results->{$name}{$PACKAGE}{replay}{$received}{replay} = true;
                                    if( !$sub->( $role, $command, $args, $interfaces, $results, $name )){
                                        $results->{$name}{$PACKAGE}{ended} = true;
                                        $results->{$name}{result}{reason} = "sub:$received";
                                    }
                                } else {
                                    $results->{$name}{$PACKAGE}{ended} = true;
                                    $results->{$name}{result}{reason} = "coderef:$received";
                                    msgErr( "by '$id_label' DaemonInterface::execute() replay='$received' without a CODE ref (got ref='$ref')" );
                                }
                                #print STDERR "after replay ".Dumper( $replay );
                                #print STDERR "after results ".Dumper( $results->{$name} );
                            }
                        } else {
                            # not a replay request
                            $results->{$name}{result}{answer} = $received;
                            delete $results->{$name}{$PACKAGE}{response};
                            $done = true;
                        }
                    } else {
                        # no answer at all
                        $done = true;
                    }
                    if( $done ){
                        $results->{$name}{$PACKAGE}{ended} = true;
                        $results->{$name}{result}{success} = true;
                        $results->{$name}{$PACKAGE}{socket}->close();
                        msgVerbose( "by '$id_label' DaemonInterface::execute() success after ".sprintf( "%.6f", time() - $results->{$name}{$PACKAGE}{start} )." sec." );
                    }
                } else {
                    my $now = time();
                    my $timedout = ( $now - $results->{$name}{$PACKAGE}{start} > $executeTimeout );
                    if( $timedout ){
                        $results->{$name}{$PACKAGE}{ended} = true;
                        $results->{$name}{result}{reason} = 'timeout';
                        msgErr( "by '$id_label' DaemonInterface::execute() OK answer not received after $executeTimeout sec." );
                    }
                }
            }
        }
    }
      while( $not_ended_count > 0 );

    # check that success=false always has a reason
    my $count = 0;
    foreach my $name ( sort keys %{$interfaces} ){
        $count += 1 if !$results->{$name}{result}{success} && !$results->{$name}{result}{reason};
    }
    msgWarn( "DaemonInterface::execute() command='$command' returns success 'false' without a reason (count=$count)" ) if $count;

    return $results;
}

1;
