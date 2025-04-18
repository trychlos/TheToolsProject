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
#
# Daemon Configuration Management.
#
# The daemon is identified by its JSON configuration basename.
# This configuration must be instanciable outside of any daemon run to be able to manage it.
# Hence this class.
#
# The properties managed here are only standard ones.
# Other daemons are free to derive this class, or just do not manage :(

package TTP::DaemonConfig;

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Data::Dumper;
use Role::Tiny::With;
use vars::global qw( $ep );

with 'TTP::IEnableable', 'TTP::IAcceptable', 'TTP::IFindable', 'TTP::IJSONable';

use TTP;
use TTP::Constants qw( :all );
use TTP::Finder;
use TTP::Message qw( :all );

use constant {
	MIN_LISTEN_INTERVAL => 500,
	DEFAULT_LISTEN_INTERVAL => 1000,
	MIN_MESSAGING_INTERVAL => 5000,
	DEFAULT_MESSAGING_INTERVAL => 60000,
	MIN_HTTPING_INTERVAL => 5000,
	DEFAULT_HTTPING_INTERVAL => 60000,
	MIN_TEXTING_INTERVAL => 5000,
	DEFAULT_TEXTING_INTERVAL => 60000,
	MIN_MQTT_TIMEOUT => 5,
	DEFAULT_MQTT_TIMEOUT => 60
};

my $Const = {
	# how to find the json configuration files
	confFinder => {
		dirs => [
			'etc/daemons',
			'daemons'
		],
		suffix => '.json'
	},
	# how to find the executables specified by a relative path
	execFinder => {
		dirs => [
			'libexec/daemons'
		]
	}
};

### Private methods

# -------------------------------------------------------------------------------------------------
# Load the configuration path
# Honors the '--dummy' verb option by using msgWarn() instead of msgErr() when checking the configuration
# (I):
# - a hash argument with following keys:
#   > jsonPath: the absolute path to the JSON configuration file
#   > checkConfig: whether to check the loaded config for mandatory items, defaulting to true
# (O):
# - true|false whether the configuration has been successfully loaded

sub _loadConfig {
	my ( $self, $args ) = @_;
	$args //= {};

	my $loaded = false;
	my $acceptable = {
		accept => sub { return $self->enabled( @_ ); },
		opts => {
			type => 'JSON'
		}
	};
	# IJSONable role takes care of validating the acceptability and the enable-ity
	$loaded = $self->jsonLoad({ path => $args->{jsonPath}, acceptable => $acceptable });
	# evaluate the data if success
	if( $loaded ){
		$self->evaluate();

		my $checkConfig = true;
		$checkConfig = $args->{checkConfig} if exists $args->{checkConfig};
		if( $checkConfig ){
			my $msgRef = $ep->runner()->dummy() ? \&msgWarn : \&msgErr;
			# must have a valid listening interval
			my $listeningInterval = $self->listeningInterval();
			$msgRef->( "$args->{jsonPath}: daemon configuration doesn't define a valid 'listeningInterval' value, found '".( $listeningInterval ? $listeningInterval : '(undef)' )."'" ) if !$listeningInterval || $listeningInterval < MIN_LISTEN_INTERVAL;
			# must have a valid listening port
			my $listeningPort = $self->listeningPort();
			$msgRef->( "$args->{jsonPath}: daemon configuration doesn't define a valid 'listeningPort' value, found '".( $listeningPort ? $listeningPort : '(undef)' )."'" ) if !$listeningPort || $listeningPort < 1;
			# must have an exec path
			my $execPath = $self->execPath();
			if( $execPath ){
				if( -r $execPath ){
					# fine ?
				} else {
					$msgRef->( "$args->{jsonPath}: execPath='$execPath' not found or not readable" );
				}
			} else {
				$msgRef->( "$args->{jsonPath}: daemon configuration must define an 'execPath' value, not found" );
			}
		} else {
			msgVerbose( "not checking daemon config as checkConfig='false'" );
		}

		# if the JSON configuration has been checked but misses some informations, then says we cannot load
		if( TTP::errs()){
			$self->jsonLoaded( false );
		}
	}

	# set the canonical name as it only depends of the json configuration filename
	my ( $vol, $dirs, $bname ) = File::Spec->splitpath( $self->jsonPath());
	$bname =~ s/\.[^\.]*$//;
	$self->{_name} = $bname;

	return $self->jsonLoaded();
}

### Public methods

# ------------------------------------------------------------------------------------------------
# Returns the execPath of the daemon
# This is a mandatory configuration item.
# Can be specified either as a full path or as a relative one.
# In this later case, the executable is searched for in TTP_ROOTS/libexec/daemons.
# (I):
# - none
# (O):
# - returns the full execPath

sub execPath {
	my ( $self ) = @_;

	my $path = $self->jsonData()->{execPath};

	if( $path && !File::Spec->file_name_is_absolute( $path )){
		my $finder = TTP::Finder->new( $self->ep());
		$path = $finder->find({ dirs => [ TTP::DaemonConfig->execFinder()->{dirs}, $path ], wantsAll => false });
	}

	return $path;
}

# ------------------------------------------------------------------------------------------------
# Whether publishing to http-based telemetry system is an enabled feature
# this is true when the httpingInterval is greater or equal to the mminimum allowed.
# (I):
# - none
# (O):
# - returns true if this daemon is willing to publish to http-based telemetry system

sub httpingEnabled {
	my ( $self ) = @_;

	my $interval = $self->httpingInterval();
	return $interval >= MIN_HTTPING_INTERVAL;
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
# Whether publishing to MQTT bus is an enabled feature
# this is true when the messagingInterval is greater or equal to the mminimum allowed.
# (I):
# - none
# (O):
# - returns true if this daemon is willing to publish to MQTT

sub messagingEnabled {
	my ( $self ) = @_;

	my $interval = $self->messagingInterval();
	return $interval >= MIN_MESSAGING_INTERVAL;
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
# Returns the canonical name of the daemon
#  which happens to be the basename of its configuration file without the extension
# This name is set as soon as the JSON has been loaded, whether successfully or not
# (I):
# - none
# (O):
# - returns the name of the daemon

sub name {
	my ( $self ) = @_;

	return $self->{_name};
}

# ------------------------------------------------------------------------------------------------
# Whether publishing to text-based telemetry system is an enabled feature
# this is true when the textingInterval is greater or equal to the mminimum allowed.
# (I):
# - none
# (O):
# - returns true if this daemon is willing to publish to text-based telemetry system

sub textingEnabled {
	my ( $self ) = @_;

	my $interval = $self->textingInterval();
	return $interval >= MIN_TEXTING_INTERVAL;
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

### Class methods

# ------------------------------------------------------------------------------------------------
# Returns the full specifications to find the daemons configuration files
# It is dynamically updated with 'daemons.confDirs' variable if any.
# (I):
# - none
# (O):
# - returns a ref to the finder, honoring 'daemons.confDirs' variable if any

sub confFinder {
	my ( $class ) = @_;
	$class = ref( $class ) || $class;

	my %finder = %{$Const->{confFinder}};
	my $dirs = $ep->var([ 'daemons', 'confDirs' ]);
	$finder{dirs} = $dirs if $dirs;

	return \%finder;
}

# ------------------------------------------------------------------------------------------------
# Returns the full specifications to find the daemons executables
# It is dynamically updated with 'daemons.execDirs' variable if any.
# (I):
# - none
# (O):
# - returns a ref to the finder, honoring 'daemons.execDirs' variable if any

sub execFinder {
	my ( $class ) = @_;
	$class = ref( $class ) || $class;

	my %finder = %{$Const->{execFinder}};
	my $dirs = $ep->var([ 'daemons', 'execDirs' ]);
	$finder{dirs} = $dirs if $dirs;

	return \%finder;
}

# -------------------------------------------------------------------------------------------------
# Constructor
# We never abort if we cannot find or load the daemon configuration file. We rely instead on the
# 'jsonable-loaded' flag that the caller MUST test.
# (I):
# - the TTP EP entry point
# - an optional argument object with following keys:
#   > jsonPath: the absolute path to the JSON configuration file
#   > checkConfig: whether to check the loaded config for mandatory items, defaulting to true
# (O):
# - this object

sub new {
	my ( $class, $ep, $args ) = @_;
	$class = ref( $class ) || $class;
	$args //= {};
	my $self = $class->SUPER::new( $ep, $args );
	bless $self, $class;

	# if a path is specified, then we try to load it
	# IJSONable role takes care of validating the acceptability and the enable-ity
	if( $args->{jsonPath} ){
		$self->_loadConfig( $args );
	} else {
		msgErr( __PACKAGE__."::new() expects a 'jsonPath' argument, not found" );
		TTP::stackTrace;
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
### the former being preferred (hence the writing inside of the 'Class methods' block which brings
### the class as first argument).

1;
