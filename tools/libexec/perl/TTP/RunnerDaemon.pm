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
# Also the daemon author must be conscious of the dynamic character of TheToolsProject.
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
#
# RunnerDaemon has two qualifiers, the daemon name and the configuration name. e.g. 'mqtt-monitor-daemon.pl trychlos-mqtt-monitor'

package TTP::RunnerDaemon;
die __PACKAGE__ . " must be loaded as TTP::RunnerDaemon\n" unless __PACKAGE__ eq 'TTP::RunnerDaemon';

use base qw( TTP::RunnerExtern );
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
use Time::Moment;
use if $Config{osname} eq 'MSWin32', "Win32::OLE";

with 'TTP::ISleepable';

use TTP;
use vars::global qw( $ep );

use TTP::Constants qw( :all );
use TTP::DaemonConfig;
use TTP::Message qw( :all );
use TTP::Metric;
use TTP::MQTT;

use constant {
	BUFSIZE => 4096,
	OFFLINE => "offline"
};

# auto-flush on socket
$| = 1;

my $Const = {
	# the commands the class manages for all daemons
	commonCommands => {
		help => \&_do_help,
		hup => \&_do_hup,
		status => \&_do_status,
		terminate => \&_do_terminate
	},
	# the metrics sub by OS
	metrics => {
		MSWin32 => [
			\&_metrics_mswin32_memory,
			\&_metrics_mswin32_page_faults,
			\&_metrics_mswin32_page_file_usage
		]
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
# answers to 'hup' command
# reload the JSON configuration
# (I):
# - the received request
# - the daemon-specific commands
# (O):
# - an empty answer

sub _do_hup {
	my ( $self, $req, $commands ) = @_;

	$self->config()->reload();

	my $answer = "";
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
# initialize the TTP daemon
# when entering here, the JSON config has been successfully read, evaluated and checked
# (I):
# - ignoreInt: whether to ignore (Ctrl+C) INT signal, defaulting to false
# (O):
# - returns this same object

sub _initListener {
	my ( $self, $args ) = @_;

	my $listeningPort = $self->config()->listeningPort();
	msgVerbose( "listeningPort='$listeningPort'" );

	my $listeningInterval = $self->config()->listeningInterval();
	msgVerbose( "listeningInterval='$listeningInterval'" );

	my $messagingInterval = $self->config()->messagingInterval();
	msgVerbose( "messagingInterval='$messagingInterval'" );

	my $httpingInterval = $self->config()->httpingInterval();
	msgVerbose( "httpingInterval='$httpingInterval'" );

	my $textingInterval = $self->config()->textingInterval();
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

	# connect to MQTT communication bus if the host is configured for and messaging is enabled
	if( !TTP::errs() && $self->config()->messagingEnabled()){
		$self->{_mqtt} = TTP::MQTT::connect({
			will => $self->_lastwill()
		});
		TTP::MQTT::keepalive( $self->{_mqtt}, $self->config()->messagingTimeout());
	}

	# Ctrl+C handling
	if( !TTP::errs()){
		my $ignoreInt = false;
		$ignoreInt = $args->{ignoreInt} if defined $args->{ignoreInt};
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
	my $rc = TTP::Metric->new( $self->ep(), {
		name => 'ttp_daemon_since',
		value => $since,
		type => 'gauge',
		help => 'Daemon running since',
		labels => $labels
	})->publish( $publish );
	foreach my $it ( sort keys %{$rc} ){
		msgVerbose( __PACKAGE__."::_metrics() got rc->{$it}='$rc->{$it}'" );
	}

	# have metrics specific to the running OS
	foreach my $sub ( @{$Const->{metrics}{$Config{osname}}} ){
		$sub->( $self, $labels, $publish );
	}
}

# https://stackoverflow.com/questions/1115743/how-can-i-programmatically-determine-my-perl-programs-memory-usage-under-window
# https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-process?redirectedfrom=MSDN

# used memory
sub _metrics_mswin32_memory {
	my ( $self, $labels, $publish ) = @_;

	my $objWMI = Win32::OLE->GetObject( 'winmgmts:\\\\.\\root\\cimv2' );
    my $processes = $objWMI->ExecQuery( "select * from Win32_Process where ProcessId=$$" );
	my $proc = get_first_item_of_ole_collection( $processes );
	my $metric = $proc->{WorkingSetSize} / 1024;

	my $rc = TTP::Metric->new( $self->ep(), {
		name => 'ttp_daemon_memory_KB',
		value => sprintf( "%.1f", $metric ),
		type => 'gauge',
		help => 'Daemon used memory',
		labels => $labels
	})->publish( $publish );

	foreach my $it ( sort keys %{$rc} ){
		msgVerbose( __PACKAGE__."::_metrics_mswin32_memory() got rc->{$it}='$rc->{$it}'" );
	}

}

# page faults
sub _metrics_mswin32_page_faults {
	my ( $self, $labels, $publish ) = @_;

	my $objWMI = Win32::OLE->GetObject( 'winmgmts:\\\\.\\root\\cimv2' );
    my $processes = $objWMI->ExecQuery( "select * from Win32_Process where ProcessId=$$" );
	my $proc = get_first_item_of_ole_collection( $processes );
	my $metric = $proc->{PageFaults};

	my $rc = TTP::Metric->new( $self->ep(), {
		name => 'ttp_daemon_page_faults_count',
		value => $metric,
		type => 'gauge',
		help => 'Daemon page faults count',
		labels => $labels
	})->publish( $publish );

	foreach my $it ( sort keys %{$rc} ){
		msgVerbose( __PACKAGE__."::_metrics_mswin32_page_faults() got rc->{$it}='$rc->{$it}'" );
	}
}

# page file usage
sub _metrics_mswin32_page_file_usage {
	my ( $self, $labels, $publish ) = @_;

	my $objWMI = Win32::OLE->GetObject( 'winmgmts:\\\\.\\root\\cimv2' );
    my $processes = $objWMI->ExecQuery( "select * from Win32_Process where ProcessId=$$" );
	my $proc = get_first_item_of_ole_collection( $processes );
	my $metric = $proc->{PageFileUsage};

	my $rc = TTP::Metric->new( $self->ep(), {
		name => 'ttp_daemon_page_file_usage_KB',
		value => sprintf( "%.1f", $metric ),
		type => 'gauge',
		help => 'Daemon page file usage',
		labels => $labels
	})->publish( $publish );

	foreach my $it ( sort keys %{$rc} ){
		msgVerbose( __PACKAGE__."::_metrics_mswin32_page_file_usage() got rc->{$it}='$rc->{$it}'" );
	}
}

# wrapper by ChatGPT
sub get_first_item_of_ole_collection {
    my ( $collection ) = @_;

    # try using an enumerator
    my $enum = Win32::OLE::Enum->new( $collection );
    if ($enum) {
        my $item = $enum->Next;
        return $item if $item;
    }

    # try Item(0)
    my $item = eval { $collection->Item(0) };
    return $item if defined $item;

    # try Item(1)
    $item = eval { $collection->Item(1) };
    return $item if defined $item;

    # try foreach loop
    foreach my $obj (in $collection) {
        return $obj;
    }

    return undef;  # nothing found
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
						if( $it->{topic} && defined( $it->{payload} )){
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

sub _running {
	my ( $self ) = @_;

	return "running since ".$self->runnableStarted()->strftime( '%Y-%m-%d %H:%M:%S.%6N %:z' );
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
	$status->{json} = $self->config()->jsonPath();
	$status->{enabled} = $self->config()->enabled( $self->config()->jsonData()) ? 'true' : 'false';
	$status->{listeningPort} = $self->config()->listeningPort();
	$status->{listeningInterval} = $self->config()->listeningInterval();
	$status->{messagingInterval} = $self->config()->messagingInterval();
	$status->{messagingTimeout} = $self->config()->messagingTimeout();
	$status->{httpingInterval} = $self->config()->httpingInterval();
	$status->{textingInterval} = $self->config()->textingInterval();
	$status->{execPath} = $self->config()->execPath();

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
# returns the configuration DaemonConfig instance
# (I):
# - none
# (O):
# - returns the configuration

sub config {
	my ( $self ) = @_;

	return $self->{_config};
}

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
	$self->sleepableDeclareFn( sub => sub { $self->listen( $commands ); }, interval => $self->config()->listeningInterval());
	# the mqtt status publication, each 'mqttInterval'
	my $mqttInterval = $self->config()->messagingInterval();
	$self->sleepableDeclareFn( sub => sub { $self->_mqtt_advertise(); }, interval => $mqttInterval ) if $self->config()->messagingEnabled();
	# the http telemetry publication, each 'httpInterval'
	my $httpInterval = $self->config()->httpingInterval();
	$self->sleepableDeclareFn( sub => sub { $self->_http_advertise(); }, interval => $httpInterval ) if $self->config()->httpingEnabled();
	# the text telemetry publication, each 'textInterval'
	my $textInterval = $self->config()->textingInterval();
	$self->sleepableDeclareFn( sub => sub { $self->_text_advertise(); }, interval => $textInterval ) if $self->config()->textingEnabled();

	$self->sleepableDeclareStop( sub => sub { return $self->terminating(); });

	return $self;
}

# ------------------------------------------------------------------------------------------------
# Set a sub to be called on daemon disconnection
# The provided sub:
# - will receive this TTP::RunnerDaemon as single argument,
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
	msgDebug( __PACKAGE__."::listen()" );

	# before anything else, reevalute our configurations
	# -> the daemon config
	$self->config()->evaluate();
	# -> toops+site and execution host configurations
	$self->ep()->site()->evaluate();
	$self->ep()->node()->evaluate();

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
# Set a sub to be called each time the daemon is about to mqtt-publish
# The provided sub:
# - will receive this TTP::RunnerDaemon as single argument,
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
# Add a 'name=value' label to the published metrics
# (I):
# - the name
# - the value
# (O):
# - this same object

sub metricLabelAppend {
	my ( $self, $name, $value ) = @_;

	if( $name && defined $value ){
		$self->{_labels} = [] if !defined $self->{_labels};
		push( @{$self->{_labels}}, "$name=$value" );
	} else {
		msgErr( __PACKAGE__."::metricLabelAppend() got name='$name' value='$value'" );
	}

	return $self;
}

# ------------------------------------------------------------------------------------------------
# Returns the canonical name of the daemon, which is also the canonical name of the json configuratio
# (I):
# - none
# (O):
# - returns the name of the daemon whether the config has been successfully loaded or not

sub name {
	my ( $self ) = @_;

	return $self->config()->name();
}

# -------------------------------------------------------------------------------------------------
# The daemon has been instanciated in its own process and the corresponding EntryPoint has been bootstrapped
# Now that the command-line options has been dealt with, it is time to load the configuration and start to run
# (I):
# - a hash argument with following keys:
#   > jsonPath: the absolute path to the JSON configuration file
#   > ignoreInt: whether to ignore the 'Ctrl+C' interrupts, defaulting to false
# (O):
# - true|false whether the configuration has been successfully loaded

sub run {
	my ( $self, $args ) = @_;
	$args //= {};
	msgDebug( __PACKAGE__."::run() jsonPath='$args->{jsonPath}' ignoreInt=".( $args->{ignoreInt} ? 'true' : 'false' ));

	my $loaded = false;

	# if a path is specified, then we try to load it
	# IJSONable role takes care of validating the acceptability and the enable-ity
	if( $args->{jsonPath} ){
		$self->{_config} = TTP::DaemonConfig->new( $self->ep(), $args );
		if( $self->config()->jsonLoaded()){
			# set a runnable qualifier as soon as we can
			$self->runnablePushQualifier( $self->config()->name());
			# and initialize listening socket and messaging connection when asked for
			my $listener = true;
			$listener = $args->{listener} if defined $args->{listener};
			$self->_initListener( $args ) if $listener;
			$loaded = true;
		}
	} else {
		msgErr( __PACKAGE__."run() expects args->{jsonPath}, not found" );
		TTP::stackTrace();
	}

	return $loaded;
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
	my $env = $self->ep()->node()->environment();
	push( @{$labels}, "environment=$env" ) if $env;
	push( @{$labels}, "command=".$self->command());
	# get only the first other (the second) qualifier
	my @qualifiers = @{$self->runnableQualifiers()};
	if( @qualifiers and scalar( @qualifiers ) >= 2 ){
		push( @{$labels}, "qualifier=".$qualifiers[1] );
	}
	push( @{$labels}, @{$self->{_labels}} ) if defined $self->{_labels};
	
	return $labels;
}

# ------------------------------------------------------------------------------------------------
# Set a sub to be called each time the daemon is about to telemetry-publish (either http or text)
# The provided sub:
# - will receive this TTP::RunnerDaemon as single argument,
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
	$self->_http_advertise() if $self->config()->httpingEnabled();
	$self->_text_advertise() if $self->config()->textingEnabled();

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
# Getter
# (I):
# - none
# (O):
# - returns the base of the topics to be published

sub topic {
	my ( $self ) = @_;

	my $topic = $self->ep()->node()->name();
	$topic .= "/daemon";
	$topic .= "/".$self->name();

	return $topic;
}

### Class methods

# -------------------------------------------------------------------------------------------------
# Constructor
# We never abort if we cannot find or load the daemon configuration file. We rely instead on the
# 'jsonable-loaded' flag that the caller MUST test.
# (I):
# - the TTP EP entry point
# (O):
# - this object

sub new {
	my ( $class, $ep, $args ) = @_;
	$class = ref( $class ) || $class;
	$args //= {};
	my $self = $class->SUPER::new( $ep, $args );
	bless $self, $class;
	msgDebug( __PACKAGE__."::new()" );

	$self->{_initialized} = false;
	$self->{_terminating} = false;

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
### the former being preferred (hence the writing inside of the 'Class methods' block which brings
### the class as first argument).

# -------------------------------------------------------------------------------------------------
# the daemon process is just being instanciated: time to instanciate and bootstrap an EntryPoint
# (I):
# - the DaemonConfig configuration
# (O):
# - the newly instanciated RunnerDaemon

sub bootstrap {
	my ( $class ) = @_;
	msgDebug( __PACKAGE__."::bootstrap() \@ARGV=".TTP::chompDumper( @ARGV ));

	$ep = TTP::EP->new();
	$ep->bootstrap();
	my $daemon = TTP::RunnerDaemon->new( $ep );
	return $daemon;
}

# -------------------------------------------------------------------------------------------------
# From inside the parent process, i.e. the daemon process has not yet been instanciated...
# Please note that the EntryPoint which is used where is those of the parent process
# (I):
# - this TTP::RunnerDaemon class name because this has to be called as 'TTP::RunnerDaemon->start()'
# - the DaemonConfig configuration
# (O):
# - the newly instanciated RunnerDaemon

sub startDaemon {
	my ( $class, $config ) = @_;
	msgDebug( __PACKAGE__."::startDaemon() config=".ref( $config ));

	my $program = $config->execPath();
	my $command = "perl $program -json ".$config->jsonPath()." -ignoreInt ".join( ' ', @ARGV );
	my $res = undef;

	if( $config->ep()->runner()->dummy()){
		msgDummy( $command );
		msgDummy( "considering startup as 'true'" );
		$res = true;
	} else {
		$res = Proc::Background->new( $command );
	}

	return $command;
}

### Global functions
### Note for the developer: while a global function doesn't take any argument, it can be called both
### as a class method 'TTP::Package->method()' or as a global function 'TTP::Package::method()',
### the former being preferred (hence the writing inside of the 'Class methods' block which brings
### the class as first argument).

1;
