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
# A telemetry metric.
#
# Properties are:
# - help: a one-line description
# - name
# - type
# - value
# - labels: an ordered list of 'name=value' labels
#
# Notes:
#
# - Messaging (MQTT-based) telemetry:
#   > by convention, topics are prefixed by the sender node name, the MQTT package takes care of that
#   > values may be both numeric or string (but must be scalars)
#   > doesn't consider one-liner description nor value type
#   > wants ordered labels
#
# - Prometheus telemetry:
#   > by convention, metrics name are 'ttp_' prefixed
#   > the server takes care of having a 'host=<host>' label
#   > values must be numeric
#   > doesn't care about labels ordering

package TTP::Metric;
die __PACKAGE__ . " must be loaded as TTP::Metric\n" unless __PACKAGE__ eq 'TTP::Metric';

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Carp;
use Config;
use Data::Dumper;
use HTTP::Request::Common;
use LWP::UserAgent;
use Role::Tiny::With;
use Scalar::Util qw( looks_like_number );
use URI::Escape;

use TTP::Constants qw( :all );
use TTP::Message qw( :all );

use constant {
	MQTT_DISABLED_BY_CONFIGURATION => 1,
	HTTP_DISABLED_BY_CONFIGURATION => 2,
	TEXT_DISABLED_BY_CONFIGURATION => 3,
	VALUE_UNAVAILABLE => 4,
	VALUE_UNSUITED => 5,
	NAME_UNAVAILABLE => 6,
	MQTT_NOCOMMAND => 7,
	MQTT_COMMAND_ERROR => 8,
	HTTP_NOURL => 9,
	HTTP_REQUEST_ERROR => 10,
	TEXT_NODROPDIR => 11
};

my $Const = {
	# by convention all Prometheus (so http-based and text-based metrics) have this same prefix
	prefix => 'ttp_',
	# the allowed types
	types => [
		'counter',
		'gauge',
		'histogram',
		'summary'
	],
	# labels must match this regex
	# https://prometheus.io/docs/concepts/data_model/
	labelNameRE => '^[a-zA-Z_][a-zA-Z0-9_]*$',
	labelValueRE => '[^/]*',
	# names must match this regex
	# https://prometheus.io/docs/concepts/data_model/
	nameRE => '^[a-zA-Z_:][a-zA-Z0-9_:]*$'
};

### Private methods

### Public methods

# -------------------------------------------------------------------------------------------------
# Getter/Setter
# (I):
# - an optional one-liner description
# (O):
# - the current description

sub help {
	my ( $self, $arg ) = @_;

	$self->{_metric}{help} = $arg if defined $arg;

	return $self->{_metric}{help};
}

# -------------------------------------------------------------------------------------------------
# Getter/Setter
# Check that each label name and value matches the relevant regular expression
# (I):
# - an optional array ref of 'name=value' labels
# (O):
# - the current content of the labels array ref

sub labels {
	my ( $self, $arg ) = @_;

	if( defined( $arg ) && ref( $arg ) eq 'ARRAY' ){
		my $labels = [];
		my $errs = 0;
		foreach my $it ( @{$arg} ){
			my @words = split( /=/, $it );
			if( scalar( @words ) == 2 && $words[0] =~ m/$Const->{labelNameRE}/ && $words[1] =~ m/$Const->{labelValueRE}/ ){
				push( @{$labels}, "$words[0]=$words[1]" );
			} else {
				$errs += 1;
				msgErr( __PACKAGE__."::labels() '$it' doesn't conform to accepted label name or value regexes" );
			}
		}
		if( !$errs ){
			$self->{_metric}{labels} = $labels;
		}
	} elsif( defined( $arg )){
		msgErr( __PACKAGE__."::labels() expects an array ref, found '".ref( $arg )."'" );
	}

	return $self->{_metric}{labels};
}

# -------------------------------------------------------------------------------------------------
# Getter/Setter
# Check that the name matches the relevant regular expression
# (I):
# - an optional name
# (O):
# - the current name

sub name {
	my ( $self, $arg ) = @_;

	if( defined( $arg ) && !ref( $arg ) && $arg ){
		# pwi 2024- 5- 1 Prometheus names do not accept dots
		$arg =~ s/\./_/g;
		if( $arg =~ m/$Const->{nameRE}/ ){
			$self->{_metric}{name} = $arg;
		} else {
			msgErr( __PACKAGE__."::name() '$arg' doesn't conform to accepted name regex" );
		}
	} elsif( defined( $arg )){
		msgErr( __PACKAGE__."::name() expects a scalar, found '".ref( $arg )."'" );
	}

	return $self->{_metric}{name};
}

# -------------------------------------------------------------------------------------------------
# Properties setter
# (I):
# - an arguments hash with following keys:
#   > help
#   > type
#   > name
#   > value
#   > labels as an array ref
# (O):
# - this same object

sub props {
	my ( $self, $args ) = @_;
	$args //= {};

	# set the provided values
	$self->help( $args->{help} ) if defined $args->{help};
	$self->name( $args->{name} ) if defined $args->{name};
	$self->type( $args->{type} ) if defined $args->{type};
	$self->value( $args->{value} ) if defined $args->{value};
	$self->labels( $args->{labels} ) if defined $args->{labels};

	return $self;
}

# -------------------------------------------------------------------------------------------------
# Publish the metric to the specified media
# (I):
# - an arguments hash ref with following keys:
#   > mqtt, whether to publish to (MQTT-based) messaging system, defaulting to false
#   > mqttPrefix, a prefix to the metric name on MQTT publication
#   > http, whether to publish to (HTTP-based) Prometheus PushGateway, defaulting to false
#   > httpPrefix, a prefix to the metric name on HTTP publication
#   > text, whether to publish to (text-based) Prometheus TextFile Collector, defaulting to false
#   > textPrefix, a prefix to the metric name on text publication
# (O):
# - a result hash ref, which may be empty, or with a key foreach 'truethy' medium specified on entering:
#   <medium>: either zero if the metric has been actually and successfully published, or the reason code

sub publish {
	my ( $self, $args ) = @_;
	$args //= {};
	my $result = {};

	my $mqtt = false;
	$mqtt = $args->{mqtt} if defined $args->{mqtt};
	my $mqttPrefix = '';
	$mqttPrefix = $args->{mqttPrefix} if defined $args->{mqttPrefix};
	$result->{mqtt} = $self->_mqtt_publish( $mqttPrefix ) if $mqtt;

	my $http = false;
	$http = $args->{http} if defined $args->{http};
	my $httpPrefix = '';
	$httpPrefix = $args->{httpPrefix} if defined $args->{httpPrefix};
	$result->{http} = $self->_http_publish( $httpPrefix ) if $http && $self->type_check();

	my $text = false;
	$text = $args->{text} if defined $args->{text};
	my $textPrefix = '';
	$textPrefix = $args->{textPrefix} if defined $args->{textPrefix};
	$result->{text} = $self->_text_publish( $textPrefix ) if $text && $self->type_check();

	return $result;
}

# to HTTP (Prometheus PushGateway)
# only publish numeric values

sub _http_publish {
	my ( $self, $prefix ) = @_;
	my $res = 0;

	my $ep = $self->ep();
	my $var = $ep->var([ 'Telemetry', 'withHttp', 'enabled' ]);
	my $enabled = defined( $var ) ? $var : false;
	if( $enabled ){
		$var = $ep->var([ 'Telemetry', 'withHttp', 'url' ]);
		my $url = defined( $var ) ? $var : undef;
		if( $url ){
			my $name = $self->name();
			if( $name ){
				my $value = $self->value();
				if( defined( $value )){
					if( looks_like_number( $value )){
						# do we run in dummy mode ?
						my $dummy = $ep->runner()->dummy();
						# make sure the name has the correct prefix
						$name = "$prefix$name";
						$name = "$Const->{prefix}$name" if $Const->{prefix} && $name !~ m/^$Const->{prefix}/;
						# build the url
						my $labels = $self->labels();
						foreach my $it ( @{$labels} ){
							my @words = split( /=/, $it );
							$url .= "/$words[0]/$words[1]";
						}
						# build the request body
						my $body = "";
						my $type = $self->type();
						$body .= "# TYPE $name $type\n" if $type;
						my $help = $self->help();
						$body .= "# HELP $name $help\n" if $help;
						$body .= "$name $value\n";
						# and post it
						if( $dummy ){
							msgDummy( "posting '$body' to '$url'" );
						} else {
							my $ua = LWP::UserAgent->new();
							my $request = HTTP::Request->new( POST => $url );
							msgVerbose( __PACKAGE__."::_http_publish() url='$url' body='$body'" );
							$request->content( $body );
							my $response = $ua->request( $request );
							if( !$response->is_success ){
								msgVerbose( Dumper( $response ));
								msgWarn( __PACKAGE__."::_http_publish() Code: ".$response->code." MSG: ".$response->decoded_content );
								$res = HTTP_REQUEST_ERROR;
							}
						}
					} else {
						$res = VALUE_UNSUITED;
					}
				} else {
					$res = VALUE_UNAVAILABLE;
				}
			} else {
				$res = NAME_UNAVAILABLE;
			}
		} else {
			$res = HTTP_NOURL;
		}
	} else {
		$res = HTTP_DISABLED_BY_CONFIGURATION;
	}

	msgVerbose( __PACKAGE__."::_http_publish() returning res='$res'" );
	return $res;
}

# to MQTT
# prepend the topic with the hostname
# only used values from ordered labels (do not use the label's names)

sub _mqtt_publish {
	my ( $self, $prefix ) = @_;
	my $res = 0;

	my $ep = $self->ep();
	my $var = $ep->var([ 'Telemetry', 'withMqtt', 'enabled' ]);
	my $enabled = defined( $var ) ? $var : false;
	if( $enabled ){
		$var = $ep->var([ 'Telemetry', 'withMqtt', 'command' ]);
		my $command = defined( $var ) ? $var : undef;
		if( $command ){
			my $name = $self->name();
			if( $name ){
				$name = "$prefix$name";
				# built the topic, starting with the host name
				my $topic = $ep->node()->name();
				$topic .= '/telemetry';
				my $labels = $self->labels();
				foreach my $it ( @{$labels} ){
					my @words = split( /=/, $it );
					$topic .= "/$words[1]";
				}
				$topic .= "/$name";
				# have a payload
				my $value = $self->value();
				# manage macros
				#print "name='$name' value='$value'".EOL;
				$command =~ s/<TOPIC>/$topic/;
				$command =~ s/<PAYLOAD>/$value/;
				# and run the command
				my $dummy = $ep->runner()->dummy() ? "-dummy" : "-nodummy";
				my $verbose = $ep->runner()->verbose() ? "-verbose" : "-noverbose";
				my $cmd = "$command -nocolored $dummy $verbose";
				if( $ep->runner()->dummy()){
					msgDummy( $cmd );
				} else {
					my $stdout = `$cmd`;
					msgVerbose( $stdout );
					my $rc = $?;
					msgVerbose( __PACKAGE__."::_mqtt_publish() got rc=$rc" );
					$res = MQTT_COMMAND_ERROR if $rc;
				}
			} else {
				$res = NAME_UNAVAILABLE;
			}
		} else {
			$res = MQTT_NOCOMMAND;
		}
	} else {
		$res = MQTT_DISABLED_BY_CONFIGURATION;
	}

	msgVerbose( __PACKAGE__."::_mqtt_publish() returning res='$res'" );
	return $res;
}

# to text (Prometheus TextFileCollector)
# only publish numeric values
# the collector filename is ?

sub _text_publish {
	my ( $self, $prefix ) = @_;
	my $res = 0;

	my $ep = $self->ep();
	my $var = $ep->var([ 'Telemetry', 'withText', 'enabled' ]);
	my $enabled = defined( $var ) ? $var : false;
	if( $enabled ){
		$var = $ep->var([ 'Telemetry', 'withText', 'dropDir' ]);
		my $dropdir = defined( $var ) ? $var : undef;
		if( $dropdir ){
			my $name = $self->name();
			if( $name ){
				$name = "$prefix$name";
				my $value = $self->value();
				if( defined( $value )){
					if( looks_like_number( $value )){
						# do we run in dummy mode ?
						my $dummy = $self->ep()->runner()->dummy();
						# make sure the name has the correct prefix
						$name = "$Const->{prefix}$name" if $Const->{prefix} && $name !~ m/^$Const->{prefix}/;
						# pwi 2024- 5- 1 do not remember the reason why ?
						#$name =~ s/\./_/g;
					} else {
						$res = VALUE_UNSUITED;
					}
				} else {
					$res = VALUE_UNAVAILABLE;
				}
			} else {
				$res = NAME_UNAVAILABLE;
			}
		} else {
			$res = TEXT_NODROPDIR;
		}
	} else {
		$res = TEXT_DISABLED_BY_CONFIGURATION;
	}

	msgVerbose( __PACKAGE__."::_text_publish() returning res='$res'" );
	return $res;
}

# -------------------------------------------------------------------------------------------------
# Getter/Setter
# Only http-based and text-based Prometheus metrics take care of the value type
# Documentation says this is an optional information, but Prometheus set the vaue as 'untyped' if
# not specified at the very first time the value is sent, and the value type can never be modified.
# So better to always provide it.
# Doesn't check here if the value is known as messaging (MQTT) doesn't care
# (I):
# - an optional type
# (O):
# - the current type

sub type {
	my ( $self, $arg ) = @_;

	#if( defined( $arg )){
	#	if( grep( /$arg/, @{$Const->{types}} )){
	#		$self->{_metric}{type} = $arg;
	#	} else {
	#		msgErr( __PACKAGE__."::type() '$arg' is not referenced among [".join( ',', @{$Const->{types}} )."]" );
	#	}
	#}
	$self->{_metric}{type} = $arg if defined $arg;

	return $self->{_metric}{type};
}

# -------------------------------------------------------------------------------------------------
# (O):
# - true|false if the type exists, whatever the publishing meda

sub type_check {
	my ( $self ) = @_;

	my $type = $self->type();
	my $res = true;
	if( $type && !grep( /$type/, @{$Const->{types}} )){
		msgErr( __PACKAGE__."::type() '$type' is not referenced among [".join( ',', @{$Const->{types}} )."]" );
		$res = false;
	}

	return $res;
}

# -------------------------------------------------------------------------------------------------
# Getter/Setter
# Doesn't check here if the value is numeric or not, as messaging (MQTT) based telemetry accepts
# both numeric and string values.
# (I):
# - an optional value
# (O):
# - the current value

sub value {
	my ( $self, $arg ) = @_;

	#if( defined( $arg )){
	#	if( looks_like_number( $arg )){
	#		$self->{_metric}{value} = $arg;
	#	} else {
	#		msgErr( __PACKAGE__."::value() '$arg' doesn't look as a number" );
	#	}
	#}

	$self->{_metric}{value} = $arg if defined $arg;

	return $self->{_metric}{value};
}

### Class methods

# -------------------------------------------------------------------------------------------------
# Constructor
# (I):
# - the TTP EP entry point
# - an optional arguments hash with following keys:
#   > help
#   > type
#   > name
#   > value
#   > labels as an array ref
# (O):
# - this object

sub new {
	my ( $class, $ep, $args ) = @_;
	$class = ref( $class ) || $class;
	my $self = $class->SUPER::new( $ep, $args );
	bless $self, $class;

	$self->{_metric} = {};
	$self->{_metric}{labels} = [];

	if( $args && ref( $args ) eq 'HASH' ){
		$self->props( $args );

	# if an arguments is provided but not a hash ref, this is an unrecoverable error
	} elsif( defined( $args )){
		msgErr( __PACKAGE__."::new() expects an optional hash ref arguments, found '".ref( $args )."'" );
		$self = undef;
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

__END__
