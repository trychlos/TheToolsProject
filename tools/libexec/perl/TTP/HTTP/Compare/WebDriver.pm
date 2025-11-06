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
# http.pl compare webdriver start and stop.

package TTP::HTTP::Compare::WebDriver;
die __PACKAGE__ . " must be loaded as TTP::HTTP::Compare::WebDriver\n" unless __PACKAGE__ eq 'TTP::HTTP::Compare::WebDriver';

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Data::Dumper;
use File::Spec;
use Proc::Background;
use Scalar::Util qw( blessed );

use TTP;
use vars::global qw( $ep );

use TTP::Constants qw( :all );
use TTP::Message qw( :all );

use constant {
};

my $Const = {
};

### Private methods

# -------------------------------------------------------------------------------------------------
# When terminating, recursively kill all children

sub _kill_tree {
    my ( $self, $pid ) = @_;
    my @children = `pgrep -P $pid`;
    chomp @children;
    for my $c ( @children ){
        $self->_kill_tree( $c );
    }
    msgVerbose( "(trying to) kill $pid" );
    kill 'KILL', $pid;
    kill 'QUIT', $pid;
    `kill -9 $pid`
}

### Public methods

### Class methods

# -------------------------------------------------------------------------------------------------
# Constructor
# (I):
# - the TTP::EP entry point
# - the TTP::HTTP::Compare::Config object
# - the logs directory
# (O):
# - this object

sub new {
	my ( $class, $ep, $conf, $logsdir ) = @_;
	$class = ref( $class ) || $class;

	if( !$ep || !blessed( $ep ) || !$ep->isa( 'TTP::EP' )){
		msgErr( "unexpected ep: ".TTP::chompDumper( $ep ));
		TTP::stackTrace();
	}
	if( !$conf || !blessed( $conf ) || !$conf->isa( 'TTP::HTTP::Compare::Config' )){
		msgErr( "unexpected conf: ".TTP::chompDumper( $conf ));
		TTP::stackTrace();
	}

	my $self = $class->SUPER::new( $ep );
	bless $self, $class;
	msgDebug( __PACKAGE__."::new()" );

	$self->{_conf} = $conf;

    my $cmd = $conf->browserCommand();
    if( $cmd ){
        my $fname = File::Spec->catfile( $logsdir, "webdriver.log" );
        # search the executable path
        my @w = split( /\s+/, $cmd );
        my $res = TTP::commandExec( "which $w[0]" );
        if( $res->{success} ){
            my $exe = $res->{stdouts}->[0];
            $self->{_driver} = Proc::Background->new({
                exe => $exe,
                stdout => $fname,
                stdout => $fname,
                stderr => $fname,
                command => \@w,
                autoterminate => true
            });
        }
    }
    if( $self->{_driver} && $self->{_driver}->alive ){
        $self->{_pid} = $self->{_driver}->pid;
        msgVerbose( "WebDriver started with PID=$self->{_pid}" );
    } else {
        msgErr( "unable to start the WebDriver (cmd='$cmd')" );
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

	my $driver = $self->{_driver};
    if( $driver && $self->{_pid} ){
        msgVerbose( "WebDriver terminating" );
        $self->_kill_tree( $self->{_pid} );
    	$driver->terminate();
    } else {
        msgVerbose( "WebDriver is not defined" );
    }

	return;
}

### Global functions
### Note for the developer: while a global function doesn't take any argument, it can be called both
### as a class method 'TTP::Package->method()' or as a global function 'TTP::Package::method()',
### the former being preferred (hence the writing inside of the 'Class methods' block which brings
### the class as first argument).

1;
