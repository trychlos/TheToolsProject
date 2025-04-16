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
# Manage the node configuration

package TTP::Node;

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Carp;
use Config;
use Data::Dumper;
use Role::Tiny::With;
use Sys::Hostname qw( hostname );
use vars::global qw( $ep );

with 'TTP::IAcceptable', 'TTP::IEnableable', 'TTP::IFindable', 'TTP::IJSONable';

use TTP::Constants qw( :all );
use TTP::Message qw( :all );
use TTP::Ports;

my $Const = {
	# hardcoded subpaths to find the <node>.json files
	# even if this not too sexy in Win32, this is a standard and a common usage on Unix/Darwin platforms
	finder => {
		dirs => [
			'etc/nodes',
			'etc/machines'
		],
		suffix => '.json'
	}
};

### Private methods

# -------------------------------------------------------------------------------------------------
# Returns the hostname
# Default is to return the hostname as provided by the operating system.
# The site may specify only a short hostname via the 'hostname.short=true' value
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
	my $short = $ep->site()->var([ 'nodes', 'hostname', 'short' ]);
	if( $short ){
		my @a = split( /\./, $name );
		$name = $a[0];
	}
	$ENV{TTP_DEBUG} && print STDERR __PACKAGE__."::_hostname() returns '$name'".EOL;
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

	my $envId;
	my $envObject = $self->jsonData()->{environment};
	if( defined( $envObject )){
		$envId = $envObject->{id};
		if( !defined( $envId )){
			$envId = $envObject->{type};
			if( defined( $envId )){
				msgWarn( "'environment.type' property is deprecated in favor of 'environment.id'. You should update your configurations." );
			}
		}
	} else {
		$envObject = $self->jsonData()->{Environment};
		if( defined( $envObject )){
			msgWarn( "'Environment' property is deprecated in favor of 'environment'. You should update your configurations." );
			$envId = $envObject->{id};
			if( !defined( $envId )){
				$envId = $envObject->{type};
				if( defined( $envId )){
					msgWarn( "'environment.type' property is deprecated in favor of 'environment.id'. You should update your configurations." );
				}
			}
		}
	}

	return $envId;
}

# ------------------------------------------------------------------------------------------------
# Override the 'IJSONable::evaluate()' method to manage the macros substitutions
# (I):
# -none
# (O):
# - this same object

sub evaluate {
	my ( $self ) = @_;

	$self->TTP::IJSONable::evaluate();

	TTP::substituteMacros( $self->jsonData(), {
		'<NODE>' => $self->name()
	});

	my $services = $self->var([ 'Services' ]);
	foreach my $it ( keys %{$services} ){
		TTP::substituteMacros( $self->var([ 'Services', $it ]), {
			'<SERVICE>' => $it
		});
	}

	return $self;
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
# Returns the list of service names defined in this node
# (I):
# - 
# (O):
# - returns an array, maybe empty

sub services {
	my ( $self ) = @_;

	my @services = keys( %{$self->jsonData()->{Services} || {}} );

	return \@services;
}

# -------------------------------------------------------------------------------------------------
# returns the content of a var, read from the node, defaulting to same from the site
# (I):
# - a reference to an array of keys to be read from (e.g. [ 'moveDir', 'byOS', 'MSWin32' ])
#   each key can be itself an array ref of potential candidates for this level
# (O):
# - the evaluated value of this variable, which may be undef

sub var {
	my ( $self, $keys ) = @_;
	#$varDebug = true if ref( $keys ) eq 'ARRAY' && grep( /package/, @{$keys} );
	print STDERR __PACKAGE__."::var() keys=".( ref( $keys ) ? '['.join( ',', @{$keys} ).']' : "'$keys'" ).EOL if $ENV{TTP_DEBUG};
	my $value = $self->TTP::IJSONable::var( $keys );
	print __PACKAGE__."::var() value='".( $value || '(undef)' )."'".EOL if $ENV{TTP_DEBUG};
	$value = $self->ep()->site()->var( $keys ) if !defined( $value );
	return $value;
}

### Class methods

# ------------------------------------------------------------------------------------------------
# Returns the list of subdirectories of TTP_ROOTS in which we may find nodes configuration files
# (I):
# - the TTP EntryPoint
# (O):
# - returns the list of subdirectories which may contain the JSON nodes configuration files as
#   an array ref

sub dirs {
	my ( $class, $ep ) = @_;
	$class = ref( $class ) || $class;

	my $dirs = $ep->site() ? $ep->site()->var( 'nodesDirs' ) || $ep->site()->var([ 'nodes', 'dirs' ]) || $class->finder()->{dirs} : $class->finder()->{dirs};

	return $dirs;
}

# ------------------------------------------------------------------------------------------------
# Returns the list of nodes available on the current host
# This is used at startup by 'ttp.sh switch -default'
# (I):
# - none
# (O):
# - the list of nodes as an array ref

sub enum {
	my ( $class ) = @_;
	$class = ref( $class ) || $class;
	$ENV{TTP_DEBUG} && print STDERR __PACKAGE__."::enum()".EOL;

	my $availables = [];

	# start with available logical machines if implemented in this site
	my $logicalRe = $ep->site()->var([ 'nodes', 'logicals', 'regexp' ]);
	$ENV{TTP_DEBUG} && print STDERR __PACKAGE__."::enum() logicalRe='".( $logicalRe || '' )."'".EOL;
	if( $logicalRe ){
		my $mounteds = TTP::Ports::rootMountPoints();
		$ENV{TTP_DEBUG} && print STDERR __PACKAGE__."::enum() mounteds ".Dumper( $mounteds );
		foreach my $mount( @${mounteds} ){
			my $candidate = $class->_enumTestForRe( $mount, $logicalRe );
			if( $candidate ){
				$ENV{TTP_DEBUG} && print STDERR __PACKAGE__."::enum() candidate '".$candidate."'".EOL;
				my $node = TTP::Node->new( $ep, { node => $candidate, abortOnError => false });
				if( $node ){
					push( @{$availables}, $node->name());
				}
			}
		}
	}

	# then try this host
	my $node = TTP::Node->new( $ep, { abortOnError => false });
	if( $node ){
		push( @{$availables}, $node->name());
	}

	$ENV{TTP_DEBUG} && print STDERR __PACKAGE__."::enum() returning [ ".( join( ', ', @${availables} ))." ]".EOL;
	return $availables;
}

# ------------------------------------------------------------------------------------------------
# Test a mount point against the regexp or the list of regexps
# (I):
# - mount point
# - the regexp or the list of regexps
# (O):
# - either the candidate name if a match is found, or a falsy value

sub _enumTestForRe {
	my ( $class, $mount, $res ) = @_;
	$class = ref( $class ) || $class;
	$ENV{TTP_DEBUG} && print STDERR __PACKAGE__."::_enumTestForRe() mount='".$mount."' res='".( $res || '' )."'".EOL;

	my $candidate = undef;
	$candidate = $class->_enumTestSingle( $mount, $res );
	return $candidate;
}

# ------------------------------------------------------------------------------------------------
# Test a mount point against one single regexp
# NB:
# 	The provided RE must not only match the desired mount point, but also should be able to return
# 	the node name as its first captured group
# (I):
# - mount point
# - a regexp
# (O):
# - either the candidate name if a match is found, or a falsy value

sub _enumTestSingle {
	my ( $class, $mount, $re ) = @_;
	$class = ref( $class ) || $class;
	$ENV{TTP_DEBUG} && print STDERR __PACKAGE__."::_enumTestSingle() mount='".$mount."' re='".( $re || '' )."'".EOL;

	my $candidate = undef;

	if( $mount =~ m/$re/ ){
		$candidate = $1;
	}

	return $candidate;
}

# ------------------------------------------------------------------------------------------------
# Returns the first available node candidate on this host
# (I):
# - none
# (O):
# - the first available node candidate on this host

sub findCandidate {
	my ( $class ) = @_;
	$class = ref( $class ) || $class;
	$ENV{TTP_DEBUG} && print STDERR __PACKAGE__."::findCandidate()".EOL;

	my $nodes = $class->enum();

	return $nodes && scalar( $nodes ) ? $nodes->[0] : undef;
}

# -------------------------------------------------------------------------------------------------
# Returns the list of dirs where nodes are to be found
# (I):
# - none
# (O):
# - Returns the Const->{finder} specification as an array ref

sub finder {
	return $Const->{finder};
}

# -------------------------------------------------------------------------------------------------
# Constructor
# (I):
# - the TTP EP entry point
# - an argument object with following keys:
#   > node: the name of the targeted node, defaulting to current host
#   > abortOnError: whether to abort if we do not found a suitable node JSON configuration,
#     defaulting to true
# (O):
# - this object, or undef in case of an error

sub new {
	my ( $class, $ep, $args ) = @_;
	$class = ref( $class ) || $class;
	$args //= {};
	my $self = $class->SUPER::new( $ep, $args );
	bless $self, $class;
	$ENV{TTP_DEBUG} && print STDERR __PACKAGE__."::new() candidate='".( $args->{node} || '' )."' abortOnError=".( $args->{abortOnError} ? 'true' : 'false' ).EOL;

	# of which node are we talking about ?
	my $node = $args->{node} || $ENV{TTP_NODE} || $self->_hostname();

	# allowed nodesDirs can be configured at site-level
	my $dirs = $class->dirs( $ep );
	my $findable = {
		dirs => [ $dirs, $node.$class->finder()->{suffix} ],
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
			msgErr( "Unable to find a valid execution node for '$node' in [ ".join( ', ', @{$dirs} )." ]" );
			msgErr( "Exiting with code 1" );
			exit( 1 );
		} else {
			$self = undef;
			$ENV{TTP_DEBUG} && print STDERR __PACKAGE__."::new() an invalid JSON configuration is detected".EOL;
		}
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
