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
# Manage the node configuration

package TTP::Node;

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use warnings;

use Carp;
use Config;
use Data::Dumper;
use Role::Tiny::With;
use Sys::Hostname qw( hostname );
use vars::global qw( $ttp );

with 'TTP::IAcceptable', 'TTP::IEnableable', 'TTP::IFindable', 'TTP::IJSONable';

use TTP::Constants qw( :all );
use TTP::Message qw( :all );

my $Const = {
	# hardcoded subpaths to find the <node>.json files
	# even if this not too sexy in Win32, this is a standard and a common usage on Unix/Darwin platforms
	finder => {
		dirs => [
			'etc/nodes',
			'nodes',
			'etc/machines',
			'machines'
		],
		sufix => '.json'
	}
};

### Private methods

# -------------------------------------------------------------------------------------------------
# returns the hostname
# (I):
# - none
# (O):
# - returns the hostname
#   > as-is in *nix environments (including Darwin)
#   > in uppercase on Windows

sub _hostname {
	# not a method - just a function
	my $name = hostname;
	$name = uc $name if $Config{osname} eq 'MSWin32';
	return $name;
}

### Public methods

# -------------------------------------------------------------------------------------------------
# Getter
# Returns the environment to which this node is attached
# (I):
# - none
# (O):
# - the environment, may be undef

sub environment {
	my ( $self ) = @_;

	my $env = $self->jsonData()->{Environment}{type};

	return $env;
}

# -------------------------------------------------------------------------------------------------
# Check if the provided service is defined and not disabled in this node
# (I):
# - name of the service
# (O):
# - returns true|false

sub hasService {
	my ( $self, $service ) = @_;
	my $hasService = false;

	if( !$service || ref( $service )){
		msgErr( __PACKAGE__."::hasService() expects a service name be specified, found '".( $service || '(undef)' )."'" );
	} else {
		my $services = $self->jsonData()->{Services} || {};
		my $hash = $services->{$service};
		my $enabled = $hash ? true : false;
		$enabled = $hash->{enabled} if $hash && exists( $hash->{enabled} );
		$hasService = $hash && $enabled;
	}

	return $hasService;
}

# -------------------------------------------------------------------------------------------------
# returns the node name
# (I):
# - none
# (O):
# - returns the node name

sub name {
	my ( $self ) = @_;

	return $self->{_node};
}

# -------------------------------------------------------------------------------------------------
# returns the content of a var, read from the node, defaulting to same from the site
# (I):
# - a reference to an array of keys to be read from (e.g. [ 'moveDir', 'byOS', 'MSWin32' ])
#   each key can be itself an array ref of potential candidates for this level
# (O):
# - the evaluated value of this variable, which may be undef

my $varDebug = false;
sub var {
	my ( $self, $keys ) = @_;
	#$varDebug = true if ref( $keys ) eq 'ARRAY' && grep( /package/, @{$keys} );
	print __PACKAGE__."::var() keys=".( ref( $keys ) ? '['.join( ',', @{$keys} ).']' : "'$keys'" ).EOL if $varDebug;
	my $value = $self->TTP::IJSONable::var( $keys );
	print __PACKAGE__."::var() value='".( $value || '(undef)' )."'".EOL if $varDebug;
	$value = $ttp->site()->var( $keys ) if !defined( $value );
	return $value;
}

### Class methods

# ------------------------------------------------------------------------------------------------
# Returns the list of subdirectories of TTP_ROOTS in which we may find nodes configuration files
# (I):
# - none
# (O):
# - returns the list of subdirectories which may contain the JSON nodes configuration files as
#   an array ref

sub dirs {
	my ( $class ) = @_;
	$class = ref( $class ) || $class;

	my $dirs = $ttp->var( 'nodesDirs' ) || $class->finder()->{dirs};

	return $dirs;
}

# -------------------------------------------------------------------------------------------------
# Returns the list of dirs where nodes are to be found
# (I]:
# - none
# (O):
# - Returns the Const->{finder} specification as an array ref

sub finder {
	return $Const->{finder};
}

# -------------------------------------------------------------------------------------------------
# Constructor
# (I]:
# - the TTP EP entry point
# - an argument object with following keys:
#   > node: the name of the targeted node, defaulting to current host
#   > abortOnError: whether to abort if we do not found a suitable node JSON configuration,
#     defaulting to true
# (O):
# - this object, or undef in case of an error

sub new {
	my ( $class, $ttp, $args ) = @_;
	$class = ref( $class ) || $class;
	$args //= {};
	my $self = $class->SUPER::new( $ttp, $args );
	bless $self, $class;

	# of which node are we talking about ?
	my $node = $args->{node} || _hostname();

	# allowed nodesDirs are configured at site-level
	my $dirs = $class->dirs();
	my $findable = {
		dirs => [ $dirs, $node.$class->finder()->{sufix} ],
		wantsAll => false
	};
	my $acceptable = {
		accept => sub { return $self->enabled( @_ ); },
		opts => {
			type => 'JSON'
		}
	};

	# try to load the json configuration
	if( $self->jsonLoad({ findable => $findable, acceptable => $acceptable })){
		# keep node name if ok
		$self->{_node} = $node;

	# unable to find and load the node configuration file ?
	# this is an unrecoverable error unless otherwise specified
	} else {
		my $abort = true;
		$abort = $args->{abortOnError} if exists $args->{abortOnError};
		if( $abort ){
			msgErr( "Unable to find a valid execution node for '$node' in [".join( ',', @{$dirs} )."]" );
			msgErr( "Exiting with code 1" );
			exit( 1 );
		} else {
			$self = undef;
		}
	}

	return $self;
}

# -------------------------------------------------------------------------------------------------
# Destructor
# (I]:
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
