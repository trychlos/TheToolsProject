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
# A class used by the daemon parts to handle the current configuration.
# Data is provided by parent's DaemonInterface at startup through the 'compare' part of the JSON configuration file.
# The class provides to each daemon the configuration it runs with.

package TTP::HTTP::Compare::Facer;
die __PACKAGE__ . " must be loaded as TTP::HTTP::Compare::Facer\n" unless __PACKAGE__ eq 'TTP::HTTP::Compare::Facer';

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Data::Dumper;
use Scalar::Util qw( blessed );
use Time::Moment;

use TTP;
use vars::global qw( $ep );

use TTP::Constants qw( :all );
use TTP::Message qw( :all );

use constant {
};

my $Const = {
};

### Private methods

### Public methods

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - which url we are running for

sub baseUrl {
	my ( $self ) = @_;
	my $res = undef;

	if( $self->{_from}->isa( 'TTP::RunnerDaemon' )){
		my $config = $self->{_from}->config()->jsonData();
		$res = $config->{compare}{baseUrl};

	} elsif( $self->{_from}->isa( 'TTP::HTTP::Compare::Role' )){
		$res = $self->{_args}{baseUrl};
		TTP::stackTrace() if !$res;

	} else {
		msgErr( "unexpected from='".ref( $self->{_from} )."'" );
		TTP::stackTrace();
	}

	return $res;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - the original arguments provided when initially running the doCompare()

sub compareArgs {
	my ( $self ) = @_;
	my $res = undef;

	if( $self->{_from}->isa( 'TTP::RunnerDaemon' )){
		my $config = $self->{_from}->config()->jsonData();
		$res = $config->{compare}{args} // {};

	} elsif( $self->{_from}->isa( 'TTP::HTTP::Compare::Role' )){
		$res = $self->{_from}{_args} // {};

	} else {
		msgErr( "unexpected from='".ref( $self->{_from} )."'" );
		TTP::stackTrace();
	}

	return $res;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - the TTP::HTTP::Compare::Config object (after serialization/deserialization)

sub conf {
	my ( $self ) = @_;

	return $self->{_conf};
}

# -------------------------------------------------------------------------------------------------
# This Facer originates from either a Role or a RunnerDaemon.
# Only the first (the Role originating) sort can access the DaemonInterface.
# (O):
# - the underlying DaemonInterface if the Facer comes from a Role, or undef

sub daemon {
    my ( $self ) = @_;

	my $daemon = undef;
	my $role = $self->roleName();
	my $which = $self->which();

	if( $self->{_from}->isa( 'TTP::HTTP::Compare::Role' )){
		$daemon = $self->{_from}{_daemons}{$which};

	} else {
		msgErr( "by '$role:$which' Facer::daemon() originating from '$self->{_from}': cannot find a DaemonInterface" );
		TTP::stackTrace();
	}

	return $daemon;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - whether we want run the browser daemon in debug mode
#   this is part of the original arguments issued from the 'http.pl compare' verb command-line
#   defaulting to false

sub isDebug {
	my ( $self ) = @_;
	my $args = $self->compareArgs();
	return $args->{debug} // false;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - the listening port number of the daemon which runs on this facer
#   only available in the parent process

sub port {
	my ( $self ) = @_;
	my $res = undef;

	if( $self->{_from}->isa( 'TTP::RunnerDaemon' )){
		msgErr( "port is unavailable in the daemon process" );
		TTP::stackTrace();

	} elsif( $self->{_from}->isa( 'TTP::HTTP::Compare::Role' )){
		$res = $self->{_args}{port};

	} else {
		msgErr( "unexpected from='".ref( $self->{_from} )."'" );
		TTP::stackTrace();
	}

	return $res;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - the current role directory

sub roleDir {
	my ( $self ) = @_;
	my $res = undef;

	if( $self->{_from}->isa( 'TTP::RunnerDaemon' )){
		my $config = $self->{_from}->config()->jsonData();
		$res = $config->{compare}{roleDir};

	} elsif( $self->{_from}->isa( 'TTP::HTTP::Compare::Role' )){
		$res = $self->{_from}->roleDir();

	} else {
		msgErr( "unexpected from='".ref( $self->{_from} )."'" );
		TTP::stackTrace();
	}

	return $res;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - the current role name

sub roleName {
	my ( $self ) = @_;
	my $res = undef;

	if( $self->{_from}->isa( 'TTP::RunnerDaemon' )){
		my $config = $self->{_from}->config()->jsonData();
		$res = $config->{compare}{roleName};

	} elsif( $self->{_from}->isa( 'TTP::HTTP::Compare::Role' )){
		$res = $self->{_from}->name();

	} else {
		msgErr( "unexpected from='".ref( $self->{_from} )."'" );
		TTP::stackTrace();
	}

	return $res;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - which website we are running for, either 'ref' or 'new'

sub which {
	my ( $self ) = @_;
	my $res = undef;

	if( $self->{_from}->isa( 'TTP::RunnerDaemon' )){
		my $config = $self->{_from}->config()->jsonData();
		$res = $config->{compare}{which};

	} elsif( $self->{_from}->isa( 'TTP::HTTP::Compare::Role' )){
		$res = $self->{_args}{which};
		TTP::stackTrace() if !$res;

	} else {
		msgErr( "unexpected from='".ref( $self->{_from} )."'" );
		TTP::stackTrace();
	}

	return $res;
}

### Class methods

# -------------------------------------------------------------------------------------------------
# Constructor
# (I):
# - the TTP::EP entry point
# - the TTP::HTTP::Compare::Config instance
# - the origin from which we will take the data,
#	 either a TTP::RunnerDaemon when run from the daemon,
#	 or a TTP::HTTP::Compare::Role when run from the parent process
# - an optional third arguments hash which comes complete the origin, may have following keys:
#   > which:
#   > baseUrl:
#   > port: when used by DaemonInterface (so from the parent process)
# (O):
# - this object

sub new {
	my ( $class, $ep, $conf, $from, $args ) = @_;
	$class = ref( $class ) || $class;
	$args //= {};

	if( !$conf || !blessed( $conf ) || !$conf->isa( 'TTP::HTTP::Compare::Config' )){
		msgErr( "unexpected conf: ".TTP::chompDumper( $conf ));
		TTP::stackTrace();
	}
	if( !$from || !blessed( $from ) || ( !$from->isa( 'TTP::RunnerDaemon' ) && !$from->isa( 'TTP::HTTP::Compare::Role' ))){
		msgErr( "unexpected from: ".TTP::chompDumper( $from ));
		TTP::stackTrace();
	}

	my $self = $class->SUPER::new( $ep );
	bless $self, $class;
	msgDebug( __PACKAGE__."::new()" );

	$self->{_conf} = $conf;
	$self->{_from} = $from;
	$self->{_args} = $args;

	return $self;
}

### Global functions
### Note for the developer: while a global function doesn't take any argument, it can be called both
### as a class method 'TTP::Package->method()' or as a global function 'TTP::Package::method()',
### the former being preferred (hence the writing inside of the 'Class methods' block which brings
### the class as first argument).

1;
