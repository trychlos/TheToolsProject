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
# Manage the node configuration

package TTP::Node;
die __PACKAGE__ . " must be loaded as TTP::Node\n" unless __PACKAGE__ eq 'TTP::Node';

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Carp;
use Config;
use Data::Dumper;
use File::Spec;
use Role::Tiny::With;
use Sys::Hostname qw( hostname );

use TTP;
use TTP::Service;
use vars::global qw( $ep );

with 'TTP::IAcceptable', 'TTP::IEnableable', 'TTP::IFindable', 'TTP::IJSONable';

use TTP::Constants qw( :all );
use TTP::Message qw( :all );

my $Const = {
	# command by OS to detect mountpoints
	mountPoints => {
		aix => {
			command => 'mount | awk \'{ print $2 }\''
		},
		linux => {
			command => 'mount | awk \'{ print $3 }\''
		}
	},
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
	msgDebug( __PACKAGE__."::_hostname() returns '$name'" );
	return $name;
}

# -------------------------------------------------------------------------------------------------
# List the root mount points
# We are only interested (and only return) with mounts at first level
# (I):
#  -
# (O):
#  - the mount points as an array ref

sub _rootMountPoints {
	my $list = [];
	msgDebug( __PACKAGE__."::_rootMountPoints() osname='$Config{osname}'" );
	my $command = $Const->{mountPoints}{$Config{osname}}{command};
	msgDebug( __PACKAGE__."::_rootMountPoints() command='$command'" );
	if( $command ){
		my @out = `$command`;
		foreach my $path ( @out ){
			chomp $path;
			my ( $volume, $directories, $file ) = File::Spec->splitpath( $path, true );
			my @dirs = File::Spec->splitdir( $directories );
			# as mount points are always returned as absolute paths, the first element of @dirs is always empty
			# so we must restrict our list to paths which only two elements, second being not empty
			#print STDERR "path=$path directories='$directories' dirs=[ ".join( ', ', @dirs )." ] scalar=".(scalar( @dirs )).EOL;
			if( scalar( @dirs ) == 2 && !$dirs[0] && $dirs[1] ){
				msgDebug( __PACKAGE__."::_rootMountPoints() found path='$path'" );
				push( @{$list}, $path ) ;
			}
		}
	}
	return $list;
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

	# 'services' is introduced in v4.10 to replace 'Services'
	my $services = $self->var([ 'services' ]);
	foreach my $it ( keys %{$services} ){
		TTP::substituteMacros( $self->var([ 'services', $it ]), {
			'<SERVICE>' => $it
		});
	}

	# 'Services' is deprecated in v4.10 in favor of 'services'
	# warn only once
	$services = $self->var([ 'Services' ]);
	if( $services && scalar( keys %{$services} ) > 0 ){
		if( !$ep->{_warnings}{services} ){
			msgWarn( "'Services' property is deprecated in favor of 'services'. You should update your configurations." );
			$ep->{_warnings}{services} = true;
		}
		foreach my $it ( keys %{$services} ){
			TTP::substituteMacros( $self->var([ 'Services', $it ]), {
				'<SERVICE>' => $it
			});
		}
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
		my $services = TTP::Service->list({ node => $self });
		$hasService = grep( /$service/, @{$services} );
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

sub var {
	my ( $self, $keys ) = @_;
	msgDebug( __PACKAGE__."::var() keys=".( ref( $keys ) ? "[ ".join( ', ', @{$keys} )." ]" : "'$keys'" ));
	my $value = $self->TTP::IJSONable::var( $keys );
	msgDebug( __PACKAGE__."::var() from Node value=".( $value ? "'$value'" : '(undef)' ));
	$value = $self->ep()->site()->var( $keys ) if !defined( $value );
	msgDebug( __PACKAGE__."::var() from Site value=".( $value ? "'$value'" : '(undef)' ));
	return $value;
}

### Class methods

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
	msgDebug( __PACKAGE__."::enum()" );

	my $availables = [];

	# start with available logical machines if implemented in this site
	my $logicalRe = $ep->site()->var([ 'nodes', 'logicals', 'regexp' ]);
	msgDebug( __PACKAGE__."::enum() logicalRe=".( $logicalRe ? "'$logicalRe'" : '(undef)' ));
	if( $logicalRe ){
		my $mounteds = _rootMountPoints();
		msgDebug( __PACKAGE__."::enum() mounteds=".TTP::chompDumper( $mounteds ));
		foreach my $mount( @${mounteds} ){
			my $candidate = $class->_enumTestForRe( $mount, $logicalRe );
			if( $candidate ){
				msgDebug( __PACKAGE__."::enum() candidate='$candidate'" );
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

	msgDebug( __PACKAGE__."::enum() returning [ ".( join( ', ', @${availables} ))." ]" );
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
	msgDebug( __PACKAGE__."::_enumTestForRe() mount='$mount' res=".( $res ? "'$res'" : '(undef)' ));

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
	msgDebug( __PACKAGE__."::_enumTestSingle() mount='$mount' re=".( $re ? "'$re'" : '(undef)' ));

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
	msgDebug( __PACKAGE__."::findCandidate()" );

	my $nodes = $class->enum();

	return $nodes && scalar( $nodes ) ? $nodes->[0] : undef;
}

# -------------------------------------------------------------------------------------------------
# Returns the list of dirs where nodes JSON configurations are to be found
# (I):
# - none
# (O):
# - returns a ref to the finder, honoring 'nodes.confDirs' variable if any

sub finder {
	my ( $class ) = @_;
	$class = ref( $class ) || $class;

	my %finder = %{$Const->{finder}};
	my $dirs = $ep->var([ 'nodes', 'confDirs' ]);
	if( !$dirs ){
		$dirs = $ep->var([ 'nodes', 'dirs' ]);
		if( $dirs ){
			msgWarn( "'nodes.dirs' property is deprecated in favor of 'nodes.confDirs'. You should update your configurations." );
		} else {
			$dirs = $ep->var( 'nodesDirs' );
			if( $dirs ){
				msgWarn( "'nodesDirs' property is deprecated in favor of 'nodes.confDirs'. You should update your configurations." );
			}
		}
	}
	$finder{dirs} = $dirs if $dirs;

	return \%finder;
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
	msgDebug( __PACKAGE__."::new() candidate=".( $args->{node} ? "'$args->{node}'" : '(undef)' )." abortOnError=".( $args->{abortOnError} ? 'true' : 'false' ));

	# of which node are we talking about ?
	my $node = $args->{node} || $ENV{TTP_NODE} || $self->_hostname();

	# allowed nodes.dirs can be configured at site-level
	my $finder = $class->finder();
	my $findable = {
		dirs => [ $finder->{dirs}, $node.$finder->{suffix} ],
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
	# Caution: do not change these error messages as they are checked in test suite
	} else {
		my $abort = true;
		$abort = $args->{abortOnError} if defined $args->{abortOnError};
		if( $abort ){
			msgErr( "Unable to find a valid execution node for '$node' in [ ".join( ', ', @{$finder->{dirs}} )." ]" );
			msgErr( "Exiting with code 1" );
			exit( 1 );
		} else {
			$self = undef;
			msgErr( "an invalid JSON configuration is detected" );
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
