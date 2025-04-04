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
#
# Daemons management
#
# A daemon is identified by its JSON configuration (we are sure there is one).
#
# JSON configuration:
#
# - enabled: whether this configuration is enabled, defaulting to true
# - execPath: the full path to the program to be executed as the main code of the daemon, mandatory
# - listeningPort: the listening port number, mandatory
# - listeningInterval: the interval in ms. between two listening loops, defaulting to 1000 ms
# - messagingInterval: either <=0 (do not advertise to messaging system), or the advertising interval in ms,
#   defaulting to 60000 ms (1 mn)
# - messagingTimeout: the timeout in sec. of the MQTT connection (if applied), defaulting to 60sec.
# - httpingInterval: either <=0 (do not advertise to http-based telemetry system), or the advertising interval in ms,
#   defaulting to 60000 ms (1 mn)
# - textingInterval: either <=0 (do not advertise to text-based telemetry system), or the advertising interval in ms,
#   defaulting to 60000 ms (1 mn)
#
# Also the daemon writer must be conscious of the dynamic character of TheToolsProject.
# In particular and at least, many output directories (logs, temp files and so on) may be built on a daily basis.
# So your configuration files must be periodically re-evaluated.
# This 'Daemon' class takes care of reevaluating both the host and the daemon configurations
# on each listeningInterval.
#
# A note about technical solutions to have daemons on Win32 platforms:
# - Proc::Daemon 0.23 (as of 2024- 2- 3) is not an option.
#   According to the documentation: "INFO: Since fork is not performed the same way on Windows systems as on Linux, this module does not work with Windows. Patches appreciated!"
# - Win32::Daemon 20200728 (as of 2024- 2- 3) defines a service, and is too specialized toward win32 plaforms.
# - Proc::Background seems OK.

package TTP::Daemon;

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Config;
use Data::Dumper;
use File::Spec;
use IO::Socket::INET;
use Proc::Background;
use Proc::ProcessTable;
use Role::Tiny::With;
use Time::Piece;
use vars::global qw( $ep );
use if $Config{osname} eq 'MSWin32', 'Win32::OLE';

with 'TTP::IEnableable', 'TTP::IAcceptable', 'TTP::IFindable', 'TTP::IHelpable', 'TTP::IJSONable', 'TTP::IOptionable', 'TTP::ISleepable', 'TTP::IRunnable';

use TTP;
use TTP::Constants qw( :all );
use TTP::Message qw( :all );
use TTP::Metric;
use TTP::MQTT;

use constant {
	BUFSIZE => 4096,
	MIN_LISTEN_INTERVAL => 500,
	DEFAULT_LISTEN_INTERVAL => 1000,
	MIN_MESSAGING_INTERVAL => 5000,
	DEFAULT_MESSAGING_INTERVAL => 60000,
	MIN_HTTPING_INTERVAL => 5000,
	DEFAULT_HTTPING_INTERVAL => 60000,
	MIN_TEXTING_INTERVAL => 5000,
	DEFAULT_TEXTING_INTERVAL => 60000,
	OFFLINE => "offline",
	MIN_MQTT_TIMEOUT => 5,
	DEFAULT_MQTT_TIMEOUT => 60
};

# auto-flush on socket
$| = 1;

my $Const = {
	# the commands the class manages for all daemons
	commonCommands => {
		help => \&_do_help,
		status => \&_do_status,
		terminate => \&_do_terminate
	},
	# how to find the daemons configuration files
	finder => {
		dirs => [
			'etc/daemons',
			'daemons'
		],
		sufix => '.json'
	}
};

### Private functions
### Must be explicitely called with $daemon as first argument

# ------------------------------------------------------------------------------------------------
# answers to 'help' command
# (I):
# - the received request
# - the daemon-specific commands
# (O):
# - the list of the available commands

sub _do_help {
	my ( $self, $req, $commands ) = @_;
	my $hash = {};
	foreach my $k ( keys %{$commands} ){
		$hash->{$k} = 1;
	}
	foreach my $k ( keys %{$Const->{commonCommands}} ){
		$hash->{$k} = 1;
	}
	my $answer = join( ', ', sort keys %{$hash} ).EOL;
	return $answer;
}

# ------------------------------------------------------------------------------------------------
# answers to 'status' command
# we display the 'status' line first, and the ordered keys after that
# the daemon-specific status will come after this common status, in a daemon-specific order
# (I):
# - the received request
# - the daemon-specific commands
# (O):
# - running since yyyy-mm-dd hh:mi:ss
# - json: 
# - listeningPort:

sub _do_status {
	my ( $self, $req, $commands ) = @_;

	my $status = $self->_status();
	my $answer = 'status: '.$status->{status}.EOL;
	foreach my $k ( sort keys %{$status} ){
		if( $k ne 'status' ){
			$answer .= "$k: ".$status->{$k}.EOL;
		}
	}

	return $answer;
}

# ------------------------------------------------------------------------------------------------
# answers to 'terminate' command
# (I):
# - the received request
# - the daemon-specific commands
# (O):
# - an empty answer

sub _do_terminate {
	my ( $self, $req, $commands ) = @_;

	$self->terminateAsk();

	my $answer = "";
	return $answer;
}

### Private methods

# ------------------------------------------------------------------------------------------------
# initialize the TTP daemon
# when entering here, the JSON config has been successfully read, evaluated and checked
# (I):
# - ignoreInt: whether to ignore (Ctrl+C) INT signal, defaulting to false
# (O):
# - returns this same object

sub _daemonize {
	my ( $self, $args ) = @_;

	my $listeningPort = $self->listeningPort();
	my $listeningInterval = $self->listeningInterval();
	my $messagingInterval = $self->messagingInterval();
	msgVerbose( "listeningPort='$listeningPort' listeningInterval='$listeningInterval' messagingInterval='$messagingInterval'" );

	my $httpingInterval = $self->httpingInterval();
	msgVerbose( "httpingInterval='$httpingInterval'" );
	my $textingInterval = $self->textingInterval();
	msgVerbose( "textingInterval='$textingInterval'" );

	# create a listening socket
	if( !TTP::errs()){
		$self->{_socket} = new IO::Socket::INET(
			LocalHost => '0.0.0.0',
			LocalPort => $listeningPort,
			Proto => 'tcp',
			Type => SOCK_STREAM,
			Listen => 5,
			ReuseAddr => true,
			Blocking => false,
			Timeout => 0
		) or msgErr( "unable to create a listening socket: $!" );
	}

	# connect to MQTT communication bus if the host is configured for
	if( !TTP::errs() && $messagingInterval > 0 ){
		$self->{_mqtt} = TTP::MQTT::connect({
			will => $self->_lastwill()
		});
		TTP::MQTT::keepalive( $self->{_mqtt}, $self->_mqtt_timeout());
	}

	# Ctrl+C handling
	if( !TTP::errs()){
		my $ignoreInt = false;
		$ignoreInt = $args->{ignoreInt} if exists $args->{ignoreInt};
		$SIG{INT} = sub { 
			if( $ignoreInt ){
				msgVerbose( "INT (Ctrl+C) signal received, ignored" );
			} else {
				$self->{_socket}->close();
				TTP::exit();
			}
		};
	}

	return $self;
}

# ------------------------------------------------------------------------------------------------
# the daemon advertise of its status every 'httpingInterval' seconds (defaults to 60)
# the metric advertises the last time we have seen the daemon alive
# (I):
# - none

sub _http_advertise {
	my ( $self ) = @_;
	$self->_metrics({ http => true });
	if( $self->{_telemetry_sub} ){
		$self->{_telemetry_sub}->( $self );
	}
}

# ------------------------------------------------------------------------------------------------
# build and returns the last will MQTT message for the daemon

sub _lastwill {
	my ( $self ) = @_;
	return {
		topic => $self->topic().'/status',
		payload => OFFLINE,
		retain => true
	};
}

# ------------------------------------------------------------------------------------------------
# provides metrics to telemetry
# (I):
# - the hash to be provided for TTP::Metric->publish()

sub _metrics {
	my ( $self, $publish ) = @_;

	my $labels = $self->telemetryLabels();

	# running since x.xxxxx sec.
	my $since = sprintf( "%.5f", $self->runnableStarted()->delta_microseconds( Time::Moment->now ) / 1000000 );
	my $rc = TTP::Metric->new( $ep, {
		name => 'ttp_daemon_since',
		value => $since,
		type => 'gauge',
		help => 'Daemon running since',
		labels => $labels
	})->publish( $publish );
	foreach my $it ( sort keys %{$rc} ){
		msgVerbose( __PACKAGE__."::_metrics() got rc->{$it}='$rc->{$it}'" );
	}

	# used memory
	$rc = TTP::Metric->new( $ep, {
		name => 'ttp_daemon_memory_KB',
		value => sprintf( "%.1f", $self->_metrics_memory()),
		type => 'gauge',
		help => 'Daemon used memory',
		labels => $labels
	})->publish( $publish );
	foreach my $it ( sort keys %{$rc} ){
		msgVerbose( __PACKAGE__."::_metrics() got rc->{$it}='$rc->{$it}'" );
	}

	# page faults
	$rc = TTP::Metric->new( $ep, {
		name => 'ttp_daemon_page_faults_count',
		value => $self->_metrics_page_faults(),
		type => 'gauge',
		help => 'Daemon page faults count',
		labels => $labels
	})->publish( $publish );
	foreach my $it ( sort keys %{$rc} ){
		msgVerbose( __PACKAGE__."::_metrics() got rc->{$it}='$rc->{$it}'" );
	}

	# page file usage
	$rc = TTP::Metric->new( $ep, {
		name => 'ttp_daemon_page_file_usage_KB',
		value => sprintf( "%.1f", $self->_metrics_page_file_usage()),
		type => 'gauge',
		help => 'Daemon page file usage',
		labels => $labels
	})->publish( $publish );
	foreach my $it ( sort keys %{$rc} ){
		msgVerbose( __PACKAGE__."::_metrics() got rc->{$it}='$rc->{$it}'" );
	}
}

# https://stackoverflow.com/questions/1115743/how-can-i-programmatically-determine-my-perl-programs-memory-usage-under-window
# https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-process?redirectedfrom=MSDN

sub _metrics_memory {
	my $objWMI = Win32::OLE->GetObject( 'winmgmts:\\\\.\\root\\cimv2' );
    my $processes = $objWMI->ExecQuery( "select * from Win32_Process where ProcessId=$$" );
    foreach my $proc ( Win32::OLE::in( $processes )){
        return $proc->{WorkingSetSize} / 1024;
    }
}

sub _metrics_page_faults {
	my $objWMI = Win32::OLE->GetObject( 'winmgmts:\\\\.\\root\\cimv2' );
    my $processes = $objWMI->ExecQuery( "select * from Win32_Process where ProcessId=$$" );
    foreach my $proc ( Win32::OLE::in( $processes )){
       return $proc->{PageFaults};
    }
}

sub _metrics_page_file_usage {
	my $objWMI = Win32::OLE->GetObject( 'winmgmts:\\\\.\\root\\cimv2' );
    my $processes = $objWMI->ExecQuery( "select * from Win32_Process where ProcessId=$$" );
    foreach my $proc ( Win32::OLE::in( $processes )){
        return $proc->{PageFileUsage};
    }
}

# ------------------------------------------------------------------------------------------------
# the daemon advertise of its status every 'messagingInterval' seconds (defaults to 60)
# topics are:
#	'<node>/daemon/<daemon_name>/status'				'running since yyyy-mm-dd hh:mm:ss.nnnnn`|offline'	retained
#	'<node>/daemon/<json_basename_wo_ext>/pid'					<pid>
#	'<node>/daemon/<json_basename_wo_ext>/json'					<full_json_path>
#	'<node>/daemon/<json_basename_wo_ext>/enabled'				'true|false'
#	'<node>/daemon/<json_basename_wo_ext>/listeningPort'		<listeningPort>
#	'<node>/daemon/<json_basename_wo_ext>/listeningInterval'	<listeningInterval>
#	'<node>/daemon/<json_basename_wo_ext>/messagingInterval'	<messagingInterval>
#	'<node>/daemon/<json_basename_wo_ext>/messagingTimeout'		<messagingTimeout>
#	'<node>/daemon/<json_basename_wo_ext>/httpingInterval'		<httpingInterval>
#	'<node>/daemon/<json_basename_wo_ext>/textingInterval'		<textingInterval>
#	'<node>/daemon/<json_basename_wo_ext>/execPath'				<execPath>
# where:
#	<daemon_name> is the JSON basename without the extension
#
# Other topics may be added by the daemon itself via the messagingSub() method.

sub _mqtt_advertise {
	my ( $self ) = @_;
	msgVerbose( __PACKAGE__."::_mqtt_advertise()" );

	if( $self->{_mqtt} ){
		# let the daemon have its own topics
		if( $self->{_mqtt_status_sub} ){
			my $array = $self->{_mqtt_status_sub}->( $self );
			if( $array ){
				if( ref( $array ) eq 'ARRAY' ){
					foreach my $it ( @{$array} ){
						if( $it->{topic} && exists( $it->{payload} )){
							$self->_mqtt_publish( $it );
						} else {
							msgErr( __PACKAGE__."::_mqtt_advertise() expects a hash { topic, payload }, found $it" );
						}
					}
				} else {
					msgErr( __PACKAGE__."::_mqtt_advertise() expects an array from messagingSub() function, got '".ref( $array )."'" );
				}
			} else {
				msgLog( __PACKAGE__."::_mqtt_advertise() got undefined value from messagingSub() function, nothing to do" );
			}
		}
		# and publish ours
		my $topic = $self->topic();
		my $status = $self->_status();
		foreach my $k ( keys %{$status} ){
			my $retain = $k eq 'status';
			$self->_mqtt_publish({ 'topic' => "$topic/$k", 'payload' => $status->{$k}, 'retain' => $retain });
		}
	} else {
		msgVerbose( __PACKAGE__."::_mqtt_advertise() not publishing as MQTT is not initialized" );
	}
}

# ------------------------------------------------------------------------------------------------
# send the disconnection topics if the daemon has asked for that feature

sub _mqtt_disconnect {
	my ( $self ) = @_;

	# have disconnection topics sent before closing the connection
	if( $self->{_mqtt_disconnect_sub} ){
		my $array = $self->{_mqtt_disconnect_sub}->( $self );
		if( $array ){
			if( ref( $array ) eq 'ARRAY' ){
				foreach my $it ( @{$array} ){
					if( $it->{topic} ){
						$self->_mqtt_publish( $it );
					} else {
						msgErr( __PACKAGE__."::_mqtt_disconnect() expects a hash { topic, payload }, found $it" );
					}
				}
			} else {
				msgErr( __PACKAGE__."::_mqtt_disconnect() expects an array, got '".ref( $array )."'" );
			}
		} else {
			msgLog( __PACKAGE__."::_mqtt_disconnect() got undefined value, nothing to do" );
		}
	}
	
	# and erase or own topics
	my $topic = $self->topic();
	my $status = $self->_status();
	foreach my $k ( keys %{$status} ){
		my $retain = $k eq 'status';
		$self->_mqtt_publish({ 'topic' => "$topic/$k", 'retain' => $retain });
	}
}

# ------------------------------------------------------------------------------------------------
# publish a single topic+payload
# (I):
# - a hash with following keys:
#     > topic mandatory
#     > payload, defaulting to empty string, which will erase the topic
#     > retain, defaulting to false

sub _mqtt_publish {
	my ( $self, $item ) = @_;
	msgVerbose( __PACKAGE__."::_mqtt_publish() ".$item->{topic} );

	if( $self->{_mqtt} && $item && $item->{topic} ){
		my $payload = $item->{payload} || '';
		if( $item->{retain} ){
			msgLog( "retain $item->{topic} [$payload]" );
			$self->{_mqtt}->retain( $item->{topic}, $payload );
		} else {
			msgLog( "publish $item->{topic} [$payload]" );
			$self->{_mqtt}->publish( $item->{topic}, $payload );
		}
	} else {
		msgLog( __PACKAGE__."::_mqtt_publish() not publishing as passed arguments are not valid" );
	}
}

# ------------------------------------------------------------------------------------------------
# returns the to-be-applied mqtt timeout

sub _mqtt_timeout {
	my ( $self ) = @_;

	my $timeout = $self->jsonData()->{messagingTimeout};
	$timeout = DEFAULT_MQTT_TIMEOUT if !defined $timeout;
	if( $timeout && $timeout < MIN_MQTT_TIMEOUT ){
		msgVerbose( "defined messagingTimeout=$timeout less than minimum accepted ".MIN_MQTT_TIMEOUT.", ignored" );
		$timeout = DEFAULT_MQTT_TIMEOUT;
	}

	return $timeout;
}

# ------------------------------------------------------------------------------------------------

sub _running {
	my ( $self ) = @_;

	return "running since ".$self->runnableStarted()->strftime( '%Y-%m-%d %H:%M:%S.%5N' );
}

# ------------------------------------------------------------------------------------------------
# Status of the daemon
# (I):
# - none
# (O):
# - returns a hash with all advertised metrics for the daemon

sub _status {
	my ( $self ) = @_;

	my $status = {};
	$status->{status} = $self->_running();
	$status->{pid} = $$;
	$status->{json} = $self->jsonPath();
	$status->{enabled} = $self->enabled( $self->jsonData()) ? 'true' : 'false';
	$status->{listeningPort} = $self->listeningPort();
	$status->{listeningInterval} = $self->listeningInterval();
	$status->{messagingInterval} = $self->messagingInterval();
	$status->{messagingTimeout} = $self->messagingTimeout();
	$status->{httpingInterval} = $self->httpingInterval();
	$status->{textingInterval} = $self->textingInterval();
	$status->{execPath} = $self->execPath();

	return $status;
}

# ------------------------------------------------------------------------------------------------
# the daemon advertise of its status every 'textingInterval' seconds (defaults to 60)
# (I):
# - none

sub _text_advertise {
	my ( $self ) = @_;
	msgVerbose( "text-based telemetry not honored at the moment" );
}

### Public methods

# ------------------------------------------------------------------------------------------------
# returns common commands
# (useful when the daemon wants override a standard answer)
# (I):
# - none
# (O):
# - returns the common commands as a hash ref

sub commonCommands {
	my ( $self ) = @_;

	return $Const->{commonCommands};
}

# ------------------------------------------------------------------------------------------------
# Declare the commom sleepable functions
# (I):
# - the daemon-specific commands as a hash ref
# (O):
# - this same object

sub declareSleepables {
	my ( $self, $commands ) = @_;

	# the listening function, each 'listeningInterval'
	$self->sleepableDeclareFn( sub => sub { $self->listen( $commands ); }, interval => $self->listeningInterval() );
	# the mqtt status publication, each 'mqttInterval'
	my $mqttInterval = $self->messagingInterval();
	$self->sleepableDeclareFn( sub => sub { $self->_mqtt_advertise(); }, interval => $mqttInterval ) if $mqttInterval > 0;
	# the http telemetry publication, each 'httpInterval'
	my $httpInterval = $self->httpingInterval();
	$self->sleepableDeclareFn( sub => sub { $self->_http_advertise(); }, interval => $httpInterval ) if $httpInterval > 0;
	# the text telemetry publication, each 'textInterval'
	my $textInterval = $self->textingInterval();
	$self->sleepableDeclareFn( sub => sub { $self->_text_advertise(); }, interval => $textInterval ) if $textInterval > 0;

	$self->sleepableDeclareStop( sub => sub { return $self->terminating(); });

	return $self;
}

# ------------------------------------------------------------------------------------------------
# Set a sub to be called on daemon disconnection
# The provided sub:
# - will receive this TTP::Daemon as single argument,
# - must return a ref to an array of hashes { topic, payload )
#   the returned hash may have a 'retain' key, with true|false value, defaulting to false.
# Note that this cannot be a 'last will' sub as the Net::MQTT::Simple package wants its last_will
# just be a hash { topic, payload, retain } and not a sub (and the MQTT protocol only allows one
# 'last_will' per connection).
# (I):
# - a code ref to be called at lastwill time
# (O):
# - this same object

sub disconnectSub {
	my ( $self, $sub ) = @_;

	if( $sub && ref( $sub ) eq 'CODE' ){
		$self->{_mqtt_disconnect_sub} = $sub;
	} else {
		msgErr( __PACKAGE__."::disconnectSub() expects a code ref, got '".ref( $sub )."'" );
	}

	return $self;
}

# ------------------------------------------------------------------------------------------------
# the daemon answers to the client
# the answer string is expected to be '\n'-terminated
# we send the answer prefixing each line by the daemon pid
# (I):
# - the received request
# - the computed answer
# (O):
# - this same object

sub doAnswer {
	my ( $self, $req, $answer ) = @_;

	msgLog( "answering '$answer' and ok-ing" );
	foreach my $line ( split( /[\r\n]+/, $answer )){
		$req->{socket}->send( "$$ $line\n" );
	}
	$req->{socket}->send( "$$ OK\n" );
	$req->{socket}->shutdown( SHUT_WR );

	return $self;
}

# ------------------------------------------------------------------------------------------------
# the daemon deals with the received command
# we are able to answer here to 'help', 'status' and 'terminate' commands and the daemon doesn't
# need to declare them.
# (I):
# - the received request
# - the hash of the daemon specific commands
# (O):
# - the computed answer as an array ref

sub doCommand {
	my ( $self, $req, $commands ) = @_;

	my $answer = undef;

	# first try to execute a specific daemon command, passing it the received request
	if( $commands->{$req->{command}} ){
		$answer = $commands->{$req->{command}}( $self, $req );

	# else ty to execute a standard command
	# the subroutine code refs must be called with the daemin instance as first argument
	} elsif( $Const->{commonCommands}{$req->{command}} ){
		$answer = $Const->{commonCommands}{$req->{command}}( $self, $req, $commands );

	# else the command is just unknowned
	} else {
		$answer = "unknowned command '$req->{command}'\n";
	}
	return $answer;
}

# ------------------------------------------------------------------------------------------------
# Returns the execPath of the daemon
# This is a mandatory configuration item.
# (I):
# - none
# (O):
# - returns the execPath

sub execPath {
	my ( $self ) = @_;

	return $self->jsonData()->{execPath};
}

# ------------------------------------------------------------------------------------------------
# Returns the interval in sec. between two advertisings to http-based telemetry system.
# May be set to false in the configuration file to disable that.
# (I):
# - none
# (O):
# - returns the http-ing interval, which may be zero if disabled

sub httpingInterval {
	my ( $self ) = @_;

	my $interval = $self->jsonData()->{httpingInterval};
	$interval = DEFAULT_HTTPING_INTERVAL if !defined $interval;
	if( $interval && $interval > 0 && $interval < MIN_HTTPING_INTERVAL ){
		msgVerbose( "defined httpingInterval=$interval less than minimum accepted ".MIN_HTTPING_INTERVAL.", ignored" );
		$interval = DEFAULT_HTTPING_INTERVAL;
	}

	return $interval;
}

# ------------------------------------------------------------------------------------------------
# periodically listen on the TCP port - reevaluate the host configuration at that moment
# this is needed to cover running when day changes and be sure that we are logging into the right file
# (I):
# - the hash of commands defined by the daemon
# (O):
# returns undef or a hash with:
# - client socket
# - peer host, address and port
# - received command
# - args

sub listen {
	my ( $self, $commands ) = @_;
	$commands //= {};

	# before anything else, reevalute our configurations
	# -> the daemon config
	$self->evaluate();
	# -> toops+site and execution host configurations
	$ep->site()->evaluate();
	$ep->node()->evaluate();

	my $client = $self->{_socket}->accept();
	my $result = undef;
	my $data = "";
	if( $client ){
		$result = {
			socket => $client,
			peerhost => $client->peerhost(),
			peeraddr => $client->peeraddr(),
			peerport => $client->peerport()
		};
		$client->recv( $data, BUFSIZE );
	}
	if( $result ){
		msgLog( "received '$data' from '$result->{peerhost}':'$result->{peeraddr}':'$result->{peerport}'" );
		my @words = split( /\s+/, $data );
		$result->{command} = shift( @words );
		$result->{args} = \@words;
		my $answer = $self->doCommand( $result, $commands );
		$self->doAnswer( $result, $answer );
	}

	return $result;
}

# ------------------------------------------------------------------------------------------------
# Returns the interval in sec. between two listening loops
# We provide a default value if not specified in the configuration file.
# (I):
# - none
# (O):
# - returns the listening interval

sub listeningInterval {
	my ( $self ) = @_;

	my $interval = $self->jsonData()->{listeningInterval};
	$interval = DEFAULT_LISTEN_INTERVAL if !defined $interval;
	if( $interval > 0 && $interval < MIN_LISTEN_INTERVAL ){
		msgVerbose( "defined listeningInterval=$interval less than minimum accepted ".MIN_LISTEN_INTERVAL.", ignored" );
		$interval = DEFAULT_LISTEN_INTERVAL;
	}

	return $interval;
}

# ------------------------------------------------------------------------------------------------
# Returns the listening port of the daemon
# This is a mandatory configuration item.
# (I):
# - none
# (O):
# - returns the listening port

sub listeningPort {
	my ( $self ) = @_;

	return $self->jsonData()->{listeningPort};
}

# ------------------------------------------------------------------------------------------------
# Returns whether the daemon configuration has been successfully loaded
# (I):
# - none
# (O):
# - returns true|false

sub loaded {
	my ( $self ) = @_;

	return $self->jsonLoaded();
}

# ------------------------------------------------------------------------------------------------
# Returns the interval in sec. between two advertisings to messaging system.
# May be set to false in the configuration file to disable that.
# (I):
# - none
# (O):
# - returns the listening interval, which may be zero if disabled

sub messagingInterval {
	my ( $self ) = @_;

	my $interval = $self->jsonData()->{messagingInterval};
	$interval = DEFAULT_MESSAGING_INTERVAL if !defined $interval;
	if( $interval && $interval < MIN_MESSAGING_INTERVAL ){
		msgVerbose( "defined messagingInterval=$interval less than minimum accepted ".MIN_MESSAGING_INTERVAL.", ignored" );
		$interval = DEFAULT_MESSAGING_INTERVAL;
	}

	return $interval;
}

# ------------------------------------------------------------------------------------------------
# Set a sub to be called each time the daemon is about to mqtt-publish
# The provided sub:
# - will receive this TTP::Daemon as single argument,
# - must return a ref to an array of hashes { topic, payload )
#   the returned hash may have a 'retain' key, with true|false value, defaulting to false
# (I):
# - a code ref to be called at mqtt-advertising time
# (O):
# - this same object

sub messagingSub {
	my ( $self, $sub ) = @_;

	if( $sub && ref( $sub ) eq 'CODE' ){
		$self->{_mqtt_status_sub} = $sub;
	} else {
		msgErr( __PACKAGE__."::messagingSub() expects a code ref, got '".ref( $sub )."'" );
	}

	return $self;
}

# ------------------------------------------------------------------------------------------------
# Returns the mqtt messaging timeout in msec.
# (I):
# - none
# (O):
# - returns the messaging timeout

sub messagingTimeout {
	my ( $self ) = @_;

	my $interval = $self->jsonData()->{messagingTimeout};
	$interval = DEFAULT_MQTT_TIMEOUT if !defined $interval;
	if( $interval && $interval < MIN_MQTT_TIMEOUT ){
		msgVerbose( "defined messagingTimeout=$interval less than minimum accepted ".MIN_MQTT_TIMEOUT.", ignored" );
		$interval = DEFAULT_MQTT_TIMEOUT;
	}

	return $interval;
}

# ------------------------------------------------------------------------------------------------
# Add a 'name=value' label to the published metrics
# (I):
# - the name
# - the value
# (O):
# - this same object

sub metricLabelAppend {
	my ( $self, $name, $value ) = @_;

	if( $name && defined $value ){
		$self->{_labels} = [] if !exists $self->{_labels};
		push( @{$self->{_labels}}, "$name=$value" );
	} else {
		msgErr( __PACKAGE__."::metricLabelAppend() got name='$name' value='$value'" );
	}

	return $self;
}

# ------------------------------------------------------------------------------------------------
# Returns the canonical name of the daemon
#  which happens to be the basename of its configuration file without the extension
# This name is set as soon as the JSON has been successfully loaded, whether the daemon itself
# is for daemonizing or not.
# (I):
# - none
# (O):
# - returns the name of the daemon, or undef if the initialization has not been successful

sub name {
	my ( $self ) = @_;

	return undef if !$self->loaded();

	return $self->{_name};
}

# -------------------------------------------------------------------------------------------------
# Set the configuration path
# Honors the '--dummy' verb option by using msgWarn() instead of msgErr() when checking the configuration
# (I):
# - a hash argument with following keys:
#   > json: the path to the JSON configuration file
#   > checkConfig: whether to check the loaded config for mandatory items, defaulting to true
#   > daemonize: whether to activate the daemonization process, defaulting to true
# (O):
# - true|false whether the configuration has been successfully loaded

sub setConfig {
	my ( $self, $args ) = @_;
	$args //= {};

	# only manage JSON configuration at the moment
	if( $args->{json} ){
		my $loaded = false;
		my $acceptable = {
			accept => sub { return $self->enabled( @_ ); },
			opts => {
				type => 'JSON'
			}
		};
		# JSOnable role takes care of validating the acceptability and the enable-ity
		$loaded = $self->jsonLoad({ path => $args->{json}, acceptable => $acceptable });
		# evaluate the data if success
		if( $loaded ){
			$self->evaluate();

			my $checkConfig = true;
			$checkConfig = $args->{checkConfig} if exists $args->{checkConfig};
			if( $checkConfig ){
				my $msgRef = $self->ep()->runner()->dummy() ? \&msgWarn : \&msgErr;
				# must have a listening port
				$msgRef->( "$args->{json}: daemon configuration must define a 'listeningPort' value, not found" ) if !$self->listeningPort();
				# must have an exec path
				my $program = $self->execPath();
				$msgRef->( "$args->{json}: daemon configuration must define an 'execPath' value, not found" ) if !$program;
				$msgRef->( "$args->{json}: execPath='$program' not found or not readable" ) if ! -r $program;
			} else {
				msgVerbose( "not checking daemon config as checkConfig='false'" );
			}

			# if the JSON configuration has been checked but misses some informations, then says we cannot load
			if( TTP::errs()){
				$self->jsonLoaded( false );

			# else initialize the daemon (socket+messaging) unless otherwise specified
			} else {
				my ( $vol, $dirs, $bname ) = File::Spec->splitpath( $self->jsonPath());
				$bname =~ s/\.[^\.]*$//;
				$self->{_name} = $bname;
				my $daemonize = true;
				$daemonize = $args->{daemonize} if exists $args->{daemonize};
				if( $daemonize ){
					# set a runnable qualifier as soon as we can
					$self->runnableSetQualifier( $bname );
					# and initialize listening socket and messaging connection
					$self->_daemonize( $args );
				}
			}
		}
	}

	return $self->loaded();
}

# ------------------------------------------------------------------------------------------------
# Parent process
# Start the daemon
# (I):
# - none
# (O):
# - returns true|false

sub start {
	my ( $self ) = @_;

	my $program = $self->execPath();
	my $command = "perl $program -json ".$self->jsonPath()." -ignoreInt ".join( ' ', @ARGV );
	my $res = undef;

	if( $self->ep()->runner()->dummy()){
		msgDummy( $command );
		msgDummy( "considering startup as 'true'" );
		$res = true;
	} else {
		$res = Proc::Background->new( $command );
	}

	return $res;
}

# ------------------------------------------------------------------------------------------------
# Returns the labels to be set on a published telemetry
# (I):
# - 
# (O):
# - the array of labels

sub telemetryLabels {
	my ( $self ) = @_;

	my $labels = [ "daemon=".$self->name() ];
	push( @{$labels}, "environment=".$ep->node()->environment());
	push( @{$labels}, "command=".$self->command());
	push( @{$labels}, "qualifier=".$self->runnableQualifier());
	push( @{$labels}, @{$self->{_labels}} ) if exists $self->{_labels};
	
	return $labels;
}

# ------------------------------------------------------------------------------------------------
# Set a sub to be called each time the daemon is about to telemetry-publish (either http or text)
# The provided sub:
# - will receive this TTP::Daemon as single argument,
# - is responsible to publish itself all its own telemetry
# (I):
# - a code ref to be called at telemetry-advertising time
# (O):
# - this same object

sub telemetrySub {
	my ( $self, $sub ) = @_;

	if( $sub && ref( $sub ) eq 'CODE' ){
		$self->{_telemetry_sub} = $sub;
	} else {
		msgErr( __PACKAGE__."::telemetrySub() expects a code ref, got '".ref( $sub )."'" );
	}

	return $self;
}

# ------------------------------------------------------------------------------------------------
# terminate the daemon, gracefully closing all opened connections

sub terminate {
	my ( $self ) = @_;

	# have disconnection topics sent before closing the connection
	$self->_mqtt_disconnect();

	# close MQTT connection
	TTP::MQTT::disconnect( $self->{_mqtt} ) if $self->{_mqtt};

	# advertise http and text-based telemetry
	$self->_http_advertise() if $self->httpingInterval() > 0;
	$self->_text_advertise() if $self->textingInterval() > 0;

	# close TCP connection
	$self->{_socket}->close();

	# have a log line
	msgLog( "terminating" );

	# and quit the program
	TTP::exit();
}

# ------------------------------------------------------------------------------------------------
# Ask for daemon termination by setting the termination flag
# (I):
# - none
# (O):
# - none

sub terminateAsk {
	my ( $self ) = @_;

	$self->{_terminating} = true;
}

# ------------------------------------------------------------------------------------------------
# Returns whether the daemon has been asked to terminate
# (I):
# - none
# (O):
# - returns true|false

sub terminating {
	my ( $self ) = @_;

	return $self->{_terminating};
}

# ------------------------------------------------------------------------------------------------
# Returns the interval in sec. between two advertisings to text-based telemetry system.
# May be set to false in the configuration file to disable that.
# (I):
# - none
# (O):
# - returns the text-ing interval, which may be zero if disabled

sub textingInterval {
	my ( $self ) = @_;

	my $interval = $self->jsonData()->{textingInterval};
	$interval = DEFAULT_TEXTING_INTERVAL if !defined $interval;
	if( $interval && $interval > 0 && $interval < MIN_TEXTING_INTERVAL ){
		msgVerbose( "defined textingInterval=$interval less than minimum accepted ".MIN_TEXTING_INTERVAL.", ignored" );
		$interval = DEFAULT_TEXTING_INTERVAL;
	}

	return $interval;
}

# ------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - returns the base of the topics to be published

sub topic {
	my ( $self ) = @_;

	my $topic = $ep->node()->name();
	$topic .= "/daemon";
	$topic .= "/".$self->name();

	return $topic;
}

### Class methods

# ------------------------------------------------------------------------------------------------
# Returns the list of subdirectories of TTP_ROOTS in which we may find daemons configuration files
# (I):
# - none
# (O):
# - returns the list of subdirectories which may contain the JSON daemons configuration files as
#   an array ref

sub dirs {
	my ( $class ) = @_;
	$class = ref( $class ) || $class;

	my $dirs = $ep->var( 'daemonsDirs' ) || $class->finder()->{dirs};

	return $dirs;
}

# ------------------------------------------------------------------------------------------------
# Returns the (hardcoded) specifications to find the daemons configuration files
# (I):
# - none
# (O):
# - returns the list of directories which may contain the JSON daemons configuration files as
#   an array ref

sub finder {
	return $Const->{finder};
}

# -------------------------------------------------------------------------------------------------
# Run by the daemon program
# Initialize the TTP environment as soon as possible
# Instanciating the Daemon also initialize the underlying IRunnable

sub init {
	my ( $class ) = @_;
	$class = ref( $class ) || $class;
	#print __PACKAGE__."::init()".EOL;

	$ep = TTP::EP->new();
	$ep->bootstrap();

	my $daemon = $class->new( $ep );
	$daemon->{_initialized} = true;
	$daemon->run();

	return $daemon;
}

# -------------------------------------------------------------------------------------------------
# Constructor
# We never abort if we cannot find or load the daemon configuration file. We rely instead on the
# 'jsonable-loaded' flag that the caller MUST test.
# (I):
# - the TTP EP entry point
# - an optional argument object with following keys:
#   > path: the absolute path to the JSON configuration file
# (O):
# - this object

sub new {
	my ( $class, $ep, $args ) = @_;
	$class = ref( $class ) || $class;
	$args //= {};
	my $self = $class->SUPER::new( $ep, $args );
	bless $self, $class;

	$self->{_initialized} = false;
	$self->{_terminating} = false;

	# if a path is specified, then we try to load it
	# IJSONable role takes care of validating the acceptability and the enable-ity
	if( $args && $args->{path} ){
		$args->{json} = $args->{path};
		$self->setConfig( $args );
	}

	return $self;
}

# -------------------------------------------------------------------------------------------------
# Destructor
# (I):
# - instance
# (O):

sub DESTROY {
	my $self = shift;
	$self->SUPER::DESTROY();
	return;
}

### Global functions
### Note for the developer: while a global function doesn't take any argument, it can be called both
### as a class method 'TTP::Package->method()' or as a global function 'TTP::Package::method()',
### the former being preferred (hence the writing inside of the 'Class methods' block).

1;
