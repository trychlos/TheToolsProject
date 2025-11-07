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
# http.pl compare login management.

package TTP::HTTP::Compare::Login;
die __PACKAGE__ . " must be loaded as TTP::HTTP::Compare::Login\n" unless __PACKAGE__ eq 'TTP::HTTP::Compare::Login';

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Data::Dumper;
use Scalar::Util qw( blessed );

use TTP;
use vars::global qw( $ep );

use TTP::Constants qw( :all );
use TTP::Message qw( :all );

use constant {
	DEFAULT_EXCLUDED_COOKIES => [
		"AspNetCore.Antiforgery"
	],
};

my $Const = {
};

### Private methods

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - the configured list of excluded cookies

sub _excluded_cookies {
	my ( $self ) = @_;

	my $ref = $self->_hash();
	my $excluded = $ref->{excluded_cookies};
	$excluded = DEFAULT_EXCLUDED_COOKIES if !defined $excluded || !$excluded || !scalar( @{$excluded} );

	return $excluded;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - a ref to the configuration hash

sub _hash {
    my ( $self ) = @_;

	return $self->{_conf}->var([ 'login' ]);
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - returns the password selector

sub _password_selector {
	my ( $self ) = @_;

	my $hash = $self->_hash();

	return $hash->{password_selector};
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - returns the path to the login page, which may be undefined

sub _path {
	my ( $self ) = @_;

	my $hash = $self->_hash();

	return $hash->{path};
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - returns the session cookie regex

sub _session_cookie_regex {
	my ( $self ) = @_;

	my $hash = $self->_hash();

	return $hash->{session_cookie_regex};
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - returns the submit selector

sub _submit_selector {
	my ( $self ) = @_;

	my $hash = $self->_hash();

	return $hash->{submit_selector};
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - returns the login selector

sub _username_selector {
	my ( $self ) = @_;

	my $hash = $self->_hash();

	return $hash->{username_selector};
}

### Public methods

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - whether this role is defined

sub isDefined {
	my ( $self ) = @_;

	my $ref = $self->_hash();

	return defined $ref &&
		defined $self->_username_selector() &&
		defined $self->_password_selector() &&
		defined $self->_submit_selector();
}

# -------------------------------------------------------------------------------------------------
# Logs a user to the website.
# (I):
# - the relevant TTP::HTTP::Compare::Browser object
# - the username
# - the associated password
# (O):
# - returns the session cookie

sub logIn {
	my ( $self, $browser, $username, $password  ) = @_;

	my $url = $browser->urlBase();
	my $session_cookie = undef;
	msgVerbose( "logging-in '$username' user to $url..." );

	my $path = $self->_path();
	if( $path ){
		my $driver = $browser->driver();
		$driver->get( $url . $path );
		my $login_selector = $self->_username_selector();
		my $element = $driver->find_element_by_css( $login_selector );
		if( !$element ){
			msgWarn( "unable to find '$login_selector' element, cancelling" );
		} else {
			$element->clear();
			$element->send_keys( $username );
			my $password_selector = $self->_password_selector();
			$element = $driver->find_element_by_css( $password_selector );
			if( !$element ){
				msgWarn( "unable to find '$password_selector' element, cancelling" );
			} else {
				$element->clear();
				$element->send_keys( $password );
				my $before = $driver->get_current_url();
				my $submit_selector = $self->_submit_selector();
				$element = $driver->find_element_by_css( $submit_selector );
				if( !$element ){
					msgWarn( "unable to find '$submit_selector' element, cancelling" );
				} else {
					$element->click();
					$browser->wait_for_url_change( $before );
					# get the session cookie (if any)
					my $cookies = $driver->get_all_cookies();
					my $re = $self->_session_cookie_regex();
					if( $re ){
						foreach my $cookie ( @{$cookies} ){
							if( $cookie->{name} =~ m/$re/i ){
								msgVerbose( "got '$cookie->{name}' session cookie by configured regex for $username\@$url" );
								$session_cookie = $cookie;
								last;
							}
						}
					# if no regex is configured, then try to get the first found after exclusion(s)
					} else {
						my $excluded_cookies = $self->_excluded_cookies();
						foreach my $cookie ( @{$cookies} ){
							my $excluded = false;
							foreach my $re ( @{$excluded_cookies} ){
								if( $cookie->{name} =~ m/$re/i ){
									$excluded = true;
									last;
								}
							}
							if( $excluded ){
								msgVerbose( "$cookie->{name} cookie is excluded by code" );
							} else {
								msgVerbose( "keeping first found '$cookie->{name}' session cookie for $username\@$url");
								$session_cookie = $cookie;
								last;
							}
						}
					}
				}
			}
		}
	}
	#print STDERR "session_cookie ".Dumper( $session_cookie );
	return $session_cookie;
}

### Class methods

# -------------------------------------------------------------------------------------------------
# Constructor
# (I):
# - the TTP::EP entry point
# - the TTP::HTTP::Compare::Config configuration object
# (O):
# - this object

sub new {
	my ( $class, $ep, $conf ) = @_;
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

	return $self;
}

### Global functions
### Note for the developer: while a global function doesn't take any argument, it can be called both
### as a class method 'TTP::Package->method()' or as a global function 'TTP::Package::method()',
### the former being preferred (hence the writing inside of the 'Class methods' block which brings
### the class as first argument).

1;
