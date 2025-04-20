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
# Let several tasks have different sleep intervals.
#
# First declare all your tasks (with ms intervals):
#   sleepableDeclareFn( sub => sub, interval => interval )
#
# Do not omit to declare a stop function:
# It will be called every second to see if the loop may continue.
#   sleepableDeclareStop( sub => sub )
#   The stop() function is called with this object as a single parameter.
#   Must return a truethy value to stop the infinite loop.
#
# Then sleepableStart(), and let each sub be called at its own interval

package TTP::ISleepable;
die __PACKAGE__ . " must be loaded as TTP::ISleepable\n" unless __PACKAGE__ eq 'TTP::ISleepable';

our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Data::Dumper;
use Time::HiRes qw( time usleep );

use TTP::Constants qw( :all );
use TTP::Message qw( :all );

my $Const = {
};

### https://metacpan.org/pod/Role::Tiny
### All subs created after importing Role::Tiny will be considered methods to be composed.
use Role::Tiny;

requires qw( _newBase );

# -------------------------------------------------------------------------------------------------
# See if a function has reached its requested interval (unless the stop() sub has been called)
# (I):
# - last run, may be undef or zero
# - requested interval (ms)
# (O):
# - true if the function should be called, false else

sub _isCallable {
	my ( $self, $last, $interval ) = @_;

	my $callable = false;
	if( $last ){
		my $diff_ms = ( time() - $last ) * 1000.0;
		$callable = ( $diff_ms > $interval );
	} else {
		$callable = true;
	}

	return $callable;
}

# -------------------------------------------------------------------------------------------------
# Declare a new function to be called on its own interval
# (I):
# - sub (named option): the code reference
# - parms (named option): the parms to pass to the code ref as a single scalar (most probably a hash or an array ref ?)
# - interval (named option): the interval call in ms.
# (O):
# - true unless an error has occurred

sub sleepableDeclareFn {
	my ( $self, %args ) = @_;

	my $success = false;
	my $ref = ref( $args{sub} );
	msgErr( __PACKAGE__."::sleepableDeclareFn() expects a code reference, found '$ref'" ) if $ref ne 'CODE';

	$ref = ref( $args{interval} );
	msgErr( __PACKAGE__."::sleepableDeclareFn() expects an interval integer, found '$ref'" ) if $ref;
	msgErr( __PACKAGE__."::sleepableDeclareFn() expects a positive interval, found '$args{interval}'" ) if !$args{interval} || $args{interval} <= 0;

	if( !TTP::errs()){
		push( @{$self->{_isleepable}{fn}}, { sub => $args{sub}, parms => $args{parms}, interval => $args{interval} } );
		$success = true;
	}

	return $success;
}

# -------------------------------------------------------------------------------------------------
# Declare a function to be called for stop
# (I):
# - sub (named option): the code reference
# (O):
# - true unless an error has occurred

sub sleepableDeclareStop {
	my ( $self, %args ) = @_;

	my $success = false;
	my $ref = ref( $args{sub} );
	msgErr( __PACKAGE__."::sleepableDeclareStop() expects a code reference, found '$ref'" ) if $ref ne 'CODE';

	if( !TTP::errs()){
		$self->{_isleepable}{stop} = { sub => $args{sub} };
		$success = true;
	}

	return $success;
}

# -------------------------------------------------------------------------------------------------
# Start an infinite loop which will successively call each declared function at the requested interval.
# This only returns when the stop() function has answered 'true'
# (I):
# - nothing
# (O):
# - true unless an error has occurred

sub sleepableStart {
	my ( $self ) = @_;

	my $success = false;
	msgErr( __PACKAGE__."::sleepableStart() no stop() function has been declared" ) if !defined $self->{_isleepable}{stop};

	if( !TTP::errs()){
		# compute the minimal interval and loop on 1/10e of it
		my $min = 0;
		foreach my $it ( @{$self->{_isleepable}{fn}} ){
			my $interval = $it->{interval};
			$min = $interval if !$min || $min > $interval;
		}
		if( $min <= 0 ){
			msgErr( __PACKAGE__."::sleepableStart() cowardly refuse to start the infinite loop with a non-positive interval, found '$min'" );
		} else {
			# the sleep time in ms
			my $loop = $min / 10.0;
			# the sleep time is usec
			my $uloop = 1000.0 * $loop;
			#print __PACKAGE__."::sleepableStart() found min='$min' sec., compute loop='$loop' sec., uloop='$uloop' usecs.".EOL;

			# get seconds and microseconds since the epoch
			#my ( $s, $usec ) = gettimeofday();

			my $stop = false;
	
			while( !$stop ){
				# call each function first
				foreach my $it ( @{$self->{_isleepable}{fn}} ){
					if( $self->_isCallable( $it->{last}, $it->{interval} )){
						$it->{sub}->( $self, $it->{params} );
						$it->{last} = time();
					}
				}
				# test for stop (every 1000 ms)
				if( $self->_isCallable( $self->{_isleepable}{stop}{last}, 1000 )){
					$stop = $self->{_isleepable}{stop}{sub}->( $self );
					$self->{_isleepable}{stop}{last} = time();
				}
				usleep( $uloop );
			}

			$success = true;
		}
	}

	return $success;
}

# -------------------------------------------------------------------------------------------------
# Sleepable initialization
# (I):
# - none
# (O):
# -none

after _newBase => sub {
	my ( $self ) = @_;

	$self->{_isleepable} //= {};
	$self->{_isleepable}{fn} = [];
	$self->{_isleepable}{stop} = undef;
};

1;

__END__
