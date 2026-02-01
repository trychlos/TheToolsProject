# TheToolsProject - Tools System and Working Paradigm for IT Production
# Copyright (©) 1998-2023 Pierre Wieser (see AUTHORS)
# Copyright (©) 2023-2026 PWI Consulting
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

with 'TTP::IAcceptable', 'TTP::IEnableable', 'TTP::IFindable', 'TTP::IJSONable';

use TTP;
use vars::global qw( $ep );

use TTP::Service;
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
		my $res = TTP::filter( $command );
		foreach my $path ( @{$res} ){
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
# - an optional options hash with following keys:
#   > warnOnUninitialized, defaulting to true
# (O):
# - this same object

sub evaluate {
	my ( $self, $opts ) = @_;
	$opts //= {};

	print STDERR __PACKAGE__."::evaluate() entering".EOL if $ENV{TTP_EVAL};
	$self->TTP::IJSONable::evaluate( $opts );

	print STDERR __PACKAGE__."::evaluate() substitute <NODE> macro".EOL if $ENV{TTP_EVAL};
	my $data = $self->jsonData();
	$data = TTP::substituteMacros( $data, {
		NODE => $self->name()
	});

	print STDERR __PACKAGE__."::evaluate() substitute <SERVICE> macro for 'services' keys".EOL if $ENV{TTP_EVAL};
	# 'services' is introduced in v4.10 to replace 'Services'
	my $services = $data->{services};
	if( $services && scalar( keys %{$services} ) > 0 ){
		foreach my $it ( keys %{$services} ){
			TTP::substituteMacros( $services->{$it}, {
				SERVICE => $it
			});
		}
	}

	# 'Services' is deprecated in v4.10 in favor of 'services'
	# warn only once
	print STDERR __PACKAGE__."::evaluate() substitute <SERVICE> macro for 'Services' keys".EOL if $ENV{TTP_EVAL};
	$services = $data->{Services};
	if( $services && scalar( keys %{$services} ) > 0 ){
		if( !$ep->{_warnings}{services} ){
			msgWarn( "'Services' property is deprecated in favor of 'services'. You should update your configurations." );
			$ep->{_warnings}{services} = true;
		}
		foreach my $it ( keys %{$services} ){
			TTP::substituteMacros( $services->{$it}, {
				SERVICE => $it
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
# Returns the first available node which host the named service in the specified environment
# (I):
# - environment identifier, which may be undef
# - service name
# - an optional options hash with following keys:
#   > inhibit: a node or a list of node names to prevent from being candidates
#   > target: a target node to be chosen among the found candidates
# (O):
# - the first found node as a TTP::Node instance, or undef

sub findByService {
	my ( $class, $environment, $service, $opts ) = @_;
	$class = ref( $class ) || $class;
	$opts //= {};
	msgDebug( __PACKAGE__."::findByService() environment=".( "'$environment'" || '(undef)' )." service='$service'" );

	my $founds = [];
	my $candidate = undef;

	# compute to-be-inhibited nodes list
	my $inhibits = [];
	if( $opts->{inhibit} ){
		my $ref = ref( $opts->{inhibit} );
		if( $ref eq 'ARRAY' ){
			$inhibits = $opts->{inhibit};
		} elsif( $ref ){
			msgErr( __PACKAGE__."::findByService() expects 'inhibit' be a string or an array, got '$ref'" );
		} else {
			$inhibits = [ $opts->{inhibit} ];
		}
	}
	msgVerbose( __PACKAGE__."::findByService() inhibit=[".join( ',', @{$inhibits} )."]" );

	# test the current execution node before scanning the full list
	$candidate = $ep->node();
	$candidate->findByService_addCandidate( $environment, $service, $founds, $inhibits ) if $candidate;

	# if it is candidate, this node will be chosen by default
	# scan the full list a) to find others b) to be able to emit a warning when several nodes are found and c) to honor the target option
	my $nodeNames = $class->list();
	foreach my $name ( @{$nodeNames} ){
		$candidate = $class->new( $ep, { node => $name });
		$candidate->findByService_addCandidate( $environment, $service, $founds, $inhibits ) if $candidate;
	}

	# this is an error to not have any candidate
	my $found = undef;
	my $count = scalar( @{$founds} );
	if( $count == 0 ){
		msgErr( "unable to find an hosting node for '$service' service in ".( "'$environment'" || '(undef)' )." environment" ) ;

	# it is possible to have several candidates and we choose the first one
	# we emit a warning when several candidates are found but no target is specified
	} else {
		my $names = [];
		my $founds_hash = {};
		foreach my $it ( @{$founds} ){
			push( @{$names}, $it->name());
			$founds_hash->{$it->name()} = $it;
		}
		if( $opts->{target} ){
			if( defined( $founds_hash->{$opts->{target}} )){
				$found = $founds_hash->{$opts->{target}};
				msgVerbose( "found target='$opts->{target}' among candidates [".join( ',', @{$names} )."]" );
			} else {
				msgErr( "target='$opts->{target}' not found among candidates [".join( ',', @{$names} )."]" );
			}
		} else {
			$found = $founds->[0];
			if( $count > 1 ){
				my $objService = TTP::Service->new( $ep, { service => $service });
				my $msg = "found $count hosting nodes [".join( ',', @{$names} )."] for '$service' service in ".( "'$environment'" || '(undef)' )." environment, choosing the first one (".$found->name().")";
				if( $objService->warnOnMultipleHostingNodes()){
					msgWarn( $msg ) ;
				} else {
					msgVerbose( $msg ) ;
				}
			}
		}
	}

	return $found;
}

# $environment may be undef
# $founds is an (ordered) array ref of current candidates

sub findByService_addCandidate {
	my ( $self, $environment, $service, $founds, $inhibits ) = @_;

	my $addedCandidate = false;
	my $name = $self->name();

	if( grep( /$name/, @{$inhibits} )){
		msgVerbose( __PACKAGE__."::findByService_addCandidate() '$name' is inhibited by option" );

	} else {
		if( $self->hasService( $service ) &&
			(( $self->environment() && $environment && $self->environment() eq $environment ) || ( !$self->environment() && !$environment ))){

			my $alreadyAdded = false;
			foreach my $node ( @{$founds} ){
				if( $node->name() eq $self->name()){
					$alreadyAdded = true;
					last;
				}
			}
			if( $alreadyAdded ){
				msgVerbose( __PACKAGE__."::findByService_addCandidate() '$name' has already been added" );
			} else {
				$addedCandidate = true;
				push( @{$founds}, $self );
				msgVerbose( __PACKAGE__."::findByService_addCandidate() adding '$name'" );
			}
		}
	}

	return $addedCandidate;
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
# list the available (defined) nodes
# (I):
# - none
# (O):
# - a ref to the array of defined nodes in ASCII order

sub list {
	my ( $class ) = @_;
	$class = ref( $class ) || $class;

	# list all nodes in all TTP_ROOTS trees
	my $finder = $class->finder();
	my $findable = {
		dirs => [ $finder->{dirs} ],
		glob => '*'.$finder->{suffix}
	};
	my $nodes = $ep->runner()->find( $findable );
	# get only unique available nodes
	my $uniqs = {};
	foreach my $it ( @{$nodes} ){
		my ( $vol, $dirs, $file ) = File::Spec->splitpath( $it );
		my $name = $file;
		$name =~ s/\.[^\.]+$//;
		my $node = TTP::Node->new( $ep, { node => $name, abortOnError => false });
		$uniqs->{$name} = $it if $node && !defined( $uniqs->{$name} );
	}
	# evaluates in array context
	my @nodes = sort keys %{$uniqs};

	return \@nodes;
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
		# auto-evaluate at least once at instanciation time
		$self->evaluate({ warnOnUninitialized => false });

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
			# the JSON can be malformed (already warned by jsonRead() function)
			# the JSON can be disabled
			$self = undef;
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
