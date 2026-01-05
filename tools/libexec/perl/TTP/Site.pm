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
# Manage the site configuration as a site context
#
# Instanciation may abort and exit immediately with exitCode=1 if site configuration is not found
# or with unknown keys. Thanks to that, the returned instance can always be considered valid by
# the caller.

package TTP::Site;
die __PACKAGE__ . " must be loaded as TTP::Site\n" unless __PACKAGE__ eq 'TTP::Site';

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Carp;
use Data::Dumper;
use Role::Tiny::With;

with 'TTP::IAcceptable', 'TTP::IEnableable', 'TTP::IFindable', 'TTP::IJSONable';

use TTP::Constants qw( :all );
use TTP::Message qw( :all );

my $Const = {
	# allowed top keys in the site configuration file
	# either exact keys or anything which ends with 'comments'
	keys => [
		'comments$',
		'^enabled$',
		'^site$',
		'^toops$',
		'^TTP$'
	],
	# when searching for a key value in the site.json file, test following prefixes
	prefix => [
		'',
		'toops',
		'TTP'
	],
	# hardcoded subpaths to find the global site.json
	# even if this not too sexy in Win32, this is a standard and a common usage on Unix/Darwin platforms
	finder => {
		dirs => [
			'etc/site.json',
			'etc/toops.json',
			'etc/ttp.json',
			'etc/toops/site.json',
			'etc/toops/toops.json',
			'etc/toops/ttp.json',
			'etc/ttp/site.json',	# the current preferred version
			'etc/ttp/toops.json',
			'etc/ttp/ttp.json'
		]
	}
};

### Private methods

# -------------------------------------------------------------------------------------------------
# Check the top keys of the provided hash, making sure only allowed keys are here
# (I):
# - hash ref to be checked
# - array ref of allowed keys
# (O):
# - a ref to the array of unallowed keys

sub _checkTopKeys {
	my ( $self, $hash, $allowedKeys ) = @_;
	my $others = [];
	foreach my $key ( keys %{$hash} ){
		#my $allowed = grep( /key/, @{$allowedKeys} );
		my $allowed = false;
		foreach my $it ( @{$allowedKeys} ){
			$allowed = ( $key =~ m/$it/ ) if !$allowed;
		}
		push( @{$others}, $key ) if !$allowed;
	}
	return $others;
}

### Public methods

# -------------------------------------------------------------------------------------------------
# Returns the disallowed keys found in the site configuration file
# (I):
# - none
# (O):
# - disallowed keys as an array ref, maybe empty

sub disallowed {
	my ( $self ) = @_;

	return $self->{_disallowed};
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

	my $node = $self->ep()->node();
	if( $node ){
		print STDERR __PACKAGE__."::evaluate() substitute <NODE> macro".EOL if $ENV{TTP_EVAL};
		TTP::substituteMacros( $self->jsonData(), {
			NODE => $node->name()
		});
	}

	return $self;
}

# -------------------------------------------------------------------------------------------------
# returns the content of a var read from the site
# (I):
# - a reference to an array of keys to be read from (e.g. [ 'moveDir', 'byOS', 'MSWin32' ])
#   each key can be itself an array ref of potential candidates for this level
# (O):
# - the evaluated value of this variable, which may be undef

sub var {
	my ( $self, $keys ) = @_;
	my @newKeys = ref $keys eq 'ARRAY' ? @{$keys} : ( $keys );
	unshift( @newKeys, $Const->{prefix} );
	msgDebug( __PACKAGE__."::var() keys=[ ".join( ', ', @newKeys )." ]" );
	my $value = $self->TTP::IJSONable::var( \@newKeys, $self->jsonData());
	return $value;
}

### Class methods

# -------------------------------------------------------------------------------------------------
# Returns the (hardcoded) site specifications
# The 'Site' is the first object we instanciate, and the parent of all configuration values.
# No way to configure anything here: the path and name have to be hardcoded
# (and we do not want go into environment variables or command-line)
# (I):
# - none
# (O):
# - Returns the Const->{finder} specification as an array ref

sub finder {
	return $Const->{finder};
}

# -------------------------------------------------------------------------------------------------
# Constructor
# May abort and exit immediately with code=1 if site configuration not found or with unknown keys.
# (I):
# - the TTP EP entry point
# (O):
# - this object

sub new {
	my ( $class, $ep, $args ) = @_;
	$class = ref( $class ) || $class;
	$args //= {};
	my $self = $class->SUPER::new( $ep );
	bless $self, $class;
	msgDebug( __PACKAGE__."::new()" );

	# try to load and evaluate the JSON configuration file with the list of allowed ending paths
	#  specs here is a ref to an array of arrays which have to be successively tested (so an array
	#  inside of an array)
	my $findable = {
		dirs => [ $class->finder()->{dirs} ],
		wantsAll => false
	};
	my $acceptable = {
		accept => sub { return $self->enabled( @_ ); },
		opts => {
			type => 'JSON'
		}
	};
	my $loaded = $self->jsonLoad({ findable => $findable, acceptable => $acceptable });

	# unable to find and load a site configuration file ? this is an unrecoverable error
	# Caution: do not change these error messages as they are checked in test suite
	if( !$loaded ){
		msgErr( "Unable to find an acceptable site configuration file among [ ".( join( ', ', @{$class->finder()->{dirs}}))." ]" );
		msgErr( "Please make sure that the file exists in one of the TTP_ROOTS paths, is JSON-valid, and is not disabled" );
		msgErr( "Exiting with code 1" );
		exit( 1 );
	}

	# check the top keys of the site file
	# found a not allowed key ? this is still an unrecoverable error
	# Caution: do not change these error messages as they are checked in test suite
	$self->{_disallowed} = $self->_checkTopKeys( $self->jsonData(), $Const->{keys } );
	if( scalar @{$self->{_disallowed}} ){
		msgErr( "Invalid key(s) found in site configuration file: [".join( ', ', @{$self->disallowed()} )."]" );
		msgErr( "Remind that site own keys should be inside 'site' hierarchy while TTP global configuration must be inside 'TTP' hierarchy" );
		msgErr( "Exiting with code 1" );
		exit( 1 );
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
