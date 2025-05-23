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
# Whether a candidate object can be accepted by the implementation.
#
# This is notably used by the JSON configuration file-based classes as Site, Node, Service or Daemon
# to check if the file is enabled or not. From this point of view, the enabled property is a primary
# element of the acceptability decision.
#
# The accepted status is set to true at instanciation time.

package TTP::IAcceptable;
die __PACKAGE__ . " must be loaded as TTP::IAcceptable\n" unless __PACKAGE__ eq 'TTP::IAcceptable';

our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Data::Dumper;

use TTP::Constants qw( :all );
use TTP::Message qw( :all );

### https://metacpan.org/pod/Role::Tiny
### All subs created after importing Role::Tiny will be considered methods to be composed.
use Role::Tiny;

requires qw( _newBase );

# -------------------------------------------------------------------------------------------------
# Test something for acceptation
# We call successively each test function, AND-ing each result to get the final result
# (of course stopping as soon as we get a false result).
# Functions prototype is fn( $obj, $opts ): boolean
# (I):
# - an arguments hash with following keys:
#   > accept: a code ref or an array of code refs, to be successively executed with passed-in object
#     and options; the result of each function is AND-ed to get the final result
#   > object: the (scalar) object to be tested
#   > opts: optional options to be passed to every test function
# (O):
# - current accepted status of the object

sub accept {
	my ( $self, $args ) = @_;

	my $ref = ref( $args );
	if( $ref eq 'HASH' ){
		if( $args->{accept} ){
			$ref = ref( $args->{accept} );
			if( $ref eq 'CODE' || $ref eq 'ARRAY' ){
				if( $args->{object} ){
					$self->_accept_run( $args );
				} else {
					msgErr( __PACKAGE__."::accept() expects args->object object, which has not been found" );
					TTP::stackTrace();
				}
			} else {
				msgErr( __PACKAGE__."::accept() expects args->accept be a code ref an an array of code refs, found '$ref'" );
				TTP::stackTrace();
			}				
		} else {
			msgErr( __PACKAGE__."::accept() expects args->accept object, which has not been found" );
			TTP::stackTrace();
		}
	} else {
		msgErr( __PACKAGE__."::accept() expects args be a hash, found '$ref'" );
		TTP::stackTrace();
	}

	return $self->accepted();
}

# arguments have been checked, just run

sub _accept_run {
	my ( $self, $args ) = @_;

	my $ref = ref( $args->{accept} );
	my $accepted = true;
	if( $ref eq 'CODE' ){
		$accepted = $args->{accept}->( $args->{object}, $args->{opts} );
	} else {
		foreach my $it ( @{$args->{accept}} ){
			$ref = ref( $it );
			if( $ref eq 'CODE' ){
				$accepted &= $it->( $args->{object}, $args->{opts} );
			} else {
				msgErr( __PACKAGE__."::_accept_run() expects a code ref, found '$ref'" );
				TTP::stackTrace();
			}
			last if !$accepted;
		}
	}

	msgDebug( __PACKAGE__."::_accept_run() accepted=".( $accepted ? "true" : "false" ));
	$self->accepted( $accepted );
}

# -------------------------------------------------------------------------------------------------
# Getter/Setter
# (I):
# - as a getter:
#   > none
# - as a setter
#   > a boolean which says whether the object is accepted or not
# (O):
# - current accepted status of the object

sub accepted {
	my ( $self, $newAccepted ) = @_;
	
	if( defined( $newAccepted )){
		$self->{_iacceptable}{accepted} = ( $newAccepted ? true : false );
	}

	return $self->{_iacceptable}{accepted};
}

# -------------------------------------------------------------------------------------------------
# Acceptable initialization
# (I):
# - none
# (O):
# -none

after _newBase => sub {
	my ( $self ) = @_;

	$self->{_iacceptable} //= {};
	$self->{_iacceptable}{accepted} = true;
};

1;

__END__
