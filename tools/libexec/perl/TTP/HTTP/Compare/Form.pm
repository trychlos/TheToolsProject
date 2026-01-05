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
# Forms handling.

package TTP::HTTP::Compare::Form;
die __PACKAGE__ . " must be loaded as TTP::HTTP::Compare::Form\n" unless __PACKAGE__ eq 'TTP::HTTP::Compare::Form';

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
};

my $Const = {
};

### Private methods

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - returns true|false

sub _handle_select {
	my ( $self ) = @_;

    my $driver = $self->{_browser}->driver();
    my $select = eval { $self->find_element( 'select', 'css' ) };
    if( $select ){
        my $selector = $self->{_selector};
        my $description = $self->{_description};
        my $form = $self->{_form};
        msgWarn( "handling '$selector' form" ); # just to be visible in the outpout

        # collect candidate option values (skip disabled/empty)
        my @opts = eval { $select->find_elements( 'option' ) } // ();
        my @vals;
        for my $o (@opts) {
            my $dis = eval { $o->get_attribute('disabled') } // '';
            next if $dis;
            my $v = eval { $o->get_attribute('value') } // '';
            $v = eval { $o->get_text } // '' if !defined($v) || $v eq '';
            next if !defined($v) || $v eq '';
            push @vals, $v;
        }
        if( @vals ){
            # try each value -> submit
            for my $v ( @vals ){
                # set value via JS + change event (most reliable for SPAs)
                my $ok = eval {
                    $driver->exec_js_w3c_sync( q{
                        const sel = arguments[0], val = arguments[1];
                        let found = false;
                        for (const opt of sel.options) {
                            if (opt.value == val || opt.text.trim() == val) { sel.value = opt.value; found = true; break; }
                        }
                        if (found) sel.dispatchEvent(new Event('change', {bubbles:true}));
                        return found;
                    }, $select, $v );
                } // false;
                if( !$ok ){
                    msgVerbose( "handleForm() '$selector' unable to set '$v' value, trying next" );
                    next;
                }
                my $submit_selector = $description->{submit_selector};
                if( $submit_selector ){
                    my $submit_element = eval { $form->find_element( $submit_selector, 'css' ) };
                    if( $submit_element ){
                        $submit_element->click();
                    } else {
                        msgVerbose( "submit_selector='$submit_selector' not found, trying next" );
                        next;
                    }
                } else {
                    msgVerbose( "submit_selector is not defined, expect a 'change' event" );
                }

                #usleep(150_000); # 150ms small debounce

                # submit
                #my $submitted = 0;
                #if( $submit_sel ){
                 #    my $btn = eval { $d->find_element($submit_sel, 'css' ) };
                 #   if( $btn ){ eval { $btn->click; $submitted = 1; }; }
                #}
                #if (!$submitted) {
                #    eval {
                #        $d->execute_script(
                #            'arguments[0].requestSubmit ? arguments[0].requestSubmit() : arguments[0].submit();',
                #            $form
                #        );
                #    };
                #}

                #usleep(600_000); # 600ms after submit to let the page settle
            }
        }
    } else {
        msgErr( "select element not found" );
        return false;
    }

    return true;
}

### Public methods

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - 

sub handle {
	my ( $self ) = @_;

    # if the form is primarily identified as a select, then just select
    my $selector = $self->{_selector};
    if( $selector =~ m/^select/i ){
        $self->_handle_select();
    }
}

### Class methods

# -------------------------------------------------------------------------------------------------
# Constructor
# (I):
# - the TTP::EP entry point
# - the TTP::HTTP::Compare::DaemonInterface object
# - the form CSS selector as configured
# - the form description as configured
# - the form Selenium::Remote::WebElement object - or maybe something else
# - an optional options hash with following keys:
#   >
# (O):
# - this object

sub new {
	my ( $class, $ep, $daemon, $selector, $description, $form, $args ) = @_;
	$class = ref( $class ) || $class;
	$args //= {};

	if( !$daemon || !blessed( $daemon ) || !$daemon->isa( 'TTP::HTTP::Compare::DaemonInterface' )){
		msgErr( "unexpected daemon: ".TTP::chompDumper( $daemon ));
		TTP::stackTrace();
	}
	#if( !$form || !blessed( $form ) || !$form->isa( 'Selenium::Remote::WebElement' )){
	#	msgErr( "unexpected form: ".TTP::chompDumper( $form ));
	#	TTP::stackTrace();
	#}

	my $self = $class->SUPER::new( $ep, $args );
	bless $self, $class;
	#msgDebug( __PACKAGE__."::new() selector='$selector'" );
	#msgVerbose( __PACKAGE__."::new() selector='$selector'" );

	$self->{_daemon} = $daemon;
	$self->{_selector} = $selector;
	$self->{_description} = $description;
	$self->{_form} = $form;

	return $self;
}

### Global functions
### Note for the developer: while a global function doesn't take any argument, it can be called both
### as a class method 'TTP::Package->method()' or as a global function 'TTP::Package::method()',
### the former being preferred (hence the writing inside of the 'Class methods' block which brings
### the class as first argument).

1;
