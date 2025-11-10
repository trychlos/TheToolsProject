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
# http.pl compare configuration.

package TTP::HTTP::Compare::Role;
die __PACKAGE__ . " must be loaded as TTP::HTTP::Compare::Role\n" unless __PACKAGE__ eq 'TTP::HTTP::Compare::Role';

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Data::Dumper;
use File::Path qw( make_path );
use File::Spec;
use List::Util qw( any );
use Scalar::Util qw( blessed );
use Test::More;
use URI;

use TTP;
use vars::global qw( $ep );

use TTP::Constants qw( :all );
use TTP::HTTP::Compare::Browser;
use TTP::HTTP::Compare::Login;
use TTP::HTTP::Compare::QueueItem;
use TTP::HTTP::Compare::Utils;
use TTP::Message qw( :all );

use constant {
	DEFAULT_ROLE_ENABLED => true
};

my $Const = {
	crawlModes => [
		'click',
		'link'
	]
};

### Private methods

# -------------------------------------------------------------------------------------------------
# we enter with the next route to examine
# activate all links and click everywhere here
# go on until having reached first of max_depth, or max_links, or max_pages
# (I):
# - the current queue_item

sub _do_crawl {
    my ( $self, $queue_item, $args ) = @_;
	$args //= {};
	msgVerbose( "do_crawl() role='".$self->name()."'" );

	# test the key signature before incrementing the visited count
	my $key = $queue_item->signature();
	msgVerbose( "do_crawl() queue signature='$key'" );
	# if already seen, go next
	if( $self->{_result}{seen}{$key} ){
		msgVerbose( "do_crawl() already seen, returning" );
		return;
	}

	# increments before visiting so that all the dumped files are numbered correctly
	$self->{_result}{count}{visited} += 1;
	$queue_item->visited( $self->{_result}{count}{visited} );
	msgVerbose( "do_crawl() visiting=".$queue_item->visited(). " (queue size=".scalar( @{ $self->{_queue} } ).")" );

	# items in queue are hashes with following keys:
	# - from: whether the item comes by 'link' or by 'click', defaulting to 'link'
	# for link's:
	# - path: the path of the route to navigate to
	# - depth: the recursion level, defaulting to zero
	# for click's:
	# - origin: the origin state key
	# - href
	# - text
	# - frameSrc
	# - id|xpath
	# - docKey
	# - kind
	# - onclick
	$queue_item->dump();

	# what sort of loop item do we have ?
	my $from = $queue_item->from();

	my $path = undef;
	my $captureRef = undef;
	my $captureNew = undef;
	my $reason = undef;

	( $captureRef, $captureNew, $path, $reason ) = @{ $self->_do_crawl_by_click( $queue_item ) } if $from eq 'click';
	( $captureRef, $captureNew, $path, $reason ) = @{ $self->_do_crawl_by_link( $queue_item ) } if $from eq 'link';

	if( $captureRef && $captureNew && $path ){

		# check that status is OK and same for the two sites
		my $status_ref = $captureRef->status();
		is( $status_ref, 200, "[".$self->name()." ($path)] ref website returns '200' status code" );
		my $status_new = $captureNew->status();
		is( $status_new, $status_ref, "[".$self->name()." ($path)] new website got same status code ($status_ref)" );

		# if we get the same error both on ref and new, then just cancel this one path, and go to next
		if( $status_ref >= 400 && $status_ref == $status_new ){
			msgVerbose( "same error code, so just cancel this path" );
			$self->_record_result( $queue_item, $captureRef, $captureNew );
			return;
		}

		# write HTML and screenshots if that must be handled
		# to be done before the comparison in order to re-use the screenshots if possible
		$captureRef->writeHtml( $queue_item, { dir => $self->{_roledir}});
		$captureRef->writeScreenshot( $queue_item, { dir => $self->{_roledir}});

		$captureNew->writeHtml( $queue_item, { dir => $self->{_roledir}});
		$captureNew->writeScreenshot( $queue_item, { dir => $self->{_roledir}});

		# compare the two captures
		# saving the screenshots if a difference is detected
		my $res = $captureRef->compare( $captureNew, { dir => $self->{_roledir}, item => $queue_item });
		$self->_record_result( $queue_item, $captureRef, $captureNew, { compare => $res });

		# collect links from ref and queue them
		# clickables which would be found in new but would be absent from ref are ignored (as new features)
		$self->_enqueue_clickables( $captureRef, $queue_item ) if $self->conf()->runCrawlByClickEnabled();

		# collect links from ref and enqueue them
		# links which would be found in new but would be absent from ref are ignored (as new features)
		$self->_enqueue_links( $captureRef, $queue_item ) if $self->conf()->runCrawlByLinkEnabled();

		# do we have forms to be handled ?
		$self->_handle_forms( $self->conf()->confForms());

	} elsif( !defined( $captureRef ) && !defined( $captureNew ) && !defined( $path )){
		msgVerbose( "do_crawl() all values are undef, just skip" );
		if( $reason ){
			$self->{_result}{cancelled}{$reason} //= [];
			push( @{$self->{_result}{cancelled}{$reason}}, $queue_item );
		} else {
			# a reason is mandatory, so this is unexpected
			msgWarn( "do_crawl() reason is not defined, this is NOT expected" );
			$self->{_result}{unexpected}{no_reason} //= [];
			push( @{$self->{_result}{unexpected}{no_reason}}, $queue_item );
		}

	} else {
		msgWarn( "do_crawl() at least one of captureRef, captureNew or path is not defined, this is NOT expected" );
		$self->{_result}{unexpected}{not_all_undef} //= [];
		push( @{$self->{_result}{unexpected}{not_all_undef}}, $queue_item );
	}

	# try to print an intermediate result each 100 visits
	$self->_try_to_print_intermediate_results();
}

# -------------------------------------------------------------------------------------------------
# the queue item comes from a 'click'
# (O):
# - TTP::HTTP::Compare::Capture object of reference site
# - TTP::HTTP::Compare::Capture object of new site
# - current path

sub _do_crawl_by_click {
    my ( $self, $queue_item ) = @_;
	msgVerbose( "do_crawl_by_click()" );

	# must have an origin and a xpath
	my $origin = $queue_item->origin();
	if( !$origin ){
		msgErr( "do_crawl() click loop item without origin" );
		return [ undef, undef, undef, "no origin" ];
	}
	my $xpath = $queue_item->xpath();
	if( !$xpath ){
		if( !$queue_item->{xpath} ){
			msgErr( "do_crawl() click loop item without xpath" );
		}
		return [ undef, undef, undef, "no xpath" ];
	}

	my $path = undef;
	my $captureRef = undef;
	my $captureNew = undef;

	# and try to restore the origin clicks chain if we do not have the same frames
	if( $self->_restore_chain( $queue_item )){
		$captureRef = $self->{_browsers}{ref}->wait_and_capture();
		# re-discover a clickable with same visible text (best effort) and click there too
		if( !$self->{_browsers}{new}->click_by_xpath( $queue_item->xpath())){
			msgVerbose( "xpath='".$queue_item->xpath()."' not available on new site" );
			my $match_new = $self->{_browsers}{new}->clickable_find_equivalent_xpath( $queue_item );
			if( $match_new ){
				if( $self->{_browsers}{new}->click_by_xpath( $match_new )){
					msgVerbose( "match found '$match_new' on new site" );
				} else {
					msgVerbose( "unable to find a equivalent match for '".$queue_item->xpath()."', cancelling" );
					return [ undef, undef, undef, "no new xpath" ];
				}
			}
		}
		$captureNew = $self->{_browsers}{new}->wait_and_capture();
	} else {
		msgWarn( "unable to restore the clicks chain" );
		return [ undef, undef, undef, "restore_chain" ];
	}

	# manage the display
	$path = $self->{_browsers}{ref}->current_path();

	# manage counters
	$self->{_result}{count}{clicks} += 1;

	return [ $captureRef, $captureNew, $path, undef ];
}

# -------------------------------------------------------------------------------------------------
# the queue item comes from a 'link'
# (O):
# - TTP::HTTP::Compare::Capture object of reference site
# - TTP::HTTP::Compare::Capture object of new site
# - current path
# - the reason when the three previous are undef

sub _do_crawl_by_link {
    my ( $self, $queue_item ) = @_;
	msgVerbose( "do_crawl_by_link()" );

	# do we have a path to navigate to ?
	my $path = $queue_item->path();
	if( !$path ){
		msgErr( "do_crawl() link queued item without path" );
		return [ undef, undef, undef, "no path" ];
	}

	# navigate and capture
	my $captureRef = $self->{_browsers}{ref}->navigate_and_capture( $path );
	my $captureNew = $self->{_browsers}{new}->navigate_and_capture( $path );

	# make sure we have a valid dest as initial routes (which are always by 'link' per definition) do not have origin
	my $page_signature = $self->{_browsers}{ref}->signature();
	$queue_item->dest( $page_signature ) if !$queue_item->origin();

	$self->{_result}{count}{links} += 1;

	return [ $captureRef, $captureNew, $path, undef ];
}

# -------------------------------------------------------------------------------------------------
# Register clickables area
# After a by-scan-id test, prefer by-xpath
# (I):
# - the current capture from reference site as a TTP::HTTP::Compare::Capture object
# - the current queue item

sub _enqueue_clickables {
    my ( $self, $capture, $queue_item ) = @_;

	my $page_signature = $capture->browser()->signature();
	msgVerbose( "enqueue_clickables() got page_signature='$page_signature'" );
	my $targets = $capture->browser()->clickable_discover_targets_xpath();
	my $count = 0;
	#print STDERR "targets: ".Dumper( $targets );
    for my $a ( @{$targets} ){
		next if !$self->_enqueue_clickables_href_allowed( $a->{href} );
		next if !$self->_enqueue_clickables_xpath_allowed( $a->{xpath} );
		$a->{origin} = $page_signature;
		$a->{from} = 'click';
		$a->{chain} = $queue_item->chain_plus();
		#print STDERR "a ".Dumper( $a->{chain} );
		my $item = TTP::HTTP::Compare::QueueItem->new( $self->ep(), $self->conf(), $a );
		push( @{$self->{_queue}}, $item );
		msgVerbose( "enqueue_clickables() enqueuing '".$item->signature()."'" );
		$item->dump({ prefix => "enqueuing" });
		$count += 1;
    }
	msgVerbose( "enqueue_clickables() got $count targets" );
}

# -------------------------------------------------------------------------------------------------
# Whether the href is allowed
# (I):
# - the candidate href

sub _enqueue_clickables_href_allowed {
    my ( $self, $href ) = @_;

	my $denied = $self->conf()->runCrawlByClickHrefDenyPatterns() || [];
    if( scalar( @{$denied} )){
        if( any { $href =~ $_ } @{ $denied } ){
			msgVerbose( "_enqueue_clickables_href_allowed() '$href' denied by regex" );
			return false;
		}
    }

	return true;
}

# -------------------------------------------------------------------------------------------------
# Whether the xpath
# After a by-scan-id test, prefer by-xpath
# (I):
# - the candidate xpath

sub _enqueue_clickables_xpath_allowed {
    my ( $self, $xpath ) = @_;

	my $denied = $self->conf()->runCrawlByClickXpathDenyPatterns() || [];
    if( scalar( @{$denied} )){
        if( any { $xpath =~ $_ } @{ $denied } ){
			msgVerbose( "_enqueue_clickables_xpath_allowed() '$xpath' denied by regex" );
			return false;
		}
    }

	return true;
}

# -------------------------------------------------------------------------------------------------
# Extract links from the 'ref' site current page, and enqueue them if not already seen
# Each link enqueing operation increments the current depth recursion level
# (I):
# - the current capture from reference site as a TTP::HTTP::Compare::Capture object
# - the current queue item

sub _enqueue_links {
    my ( $self, $capture, $queue_item ) = @_;

	# collect links from the capture
	my $links = $capture->extract_links();

	# queue next layer
	my $page_signature = $capture->browser()->signature();
	if( scalar( @{$links} )){
		$self->{_result}{count}{depth} += 1;
		foreach my $p ( @{$links} ){
			my $u = URI->new( $p );
			push( @{$self->{_queue}},
				TTP::HTTP::Compare::QueueItem->new(
					$self->ep(),
					$self->conf(),
					{ path => $u->path_query || '/', depth => $self->{_result}{count}{depth}, from => 'link', origin => $page_signature, chain => $queue_item->chain_plus() }
			));
			msgVerbose( "enqueuing '$p'" );
		}
	}
}

# -------------------------------------------------------------------------------------------------
# Handle the provided form
# (I):
# - the form selector
# - the form description

sub _handle_form {
    my ( $self, $selector, $description ) = @_;

	my $formRef = $self->{_browsers}{ref}->handleForm( $selector, $description );
	my $formNew = $formRef ? $self->{_browsers}{new}->handleForm( $selector, $description ) : undef;
}

# -------------------------------------------------------------------------------------------------
# Handle the forms in the page
# (I):
# - the configured forms

sub _handle_forms {
    my ( $self, $forms ) = @_;

	for my $form_selector ( sort keys %{$forms} ){
		$self->_handle_form( $form_selector, $forms->{$form_selector} );
	}
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - a ref to the configuration hash

sub _hash {
    my ( $self ) = @_;

	return $self->{conf}->var([ 'roles', $self->name() ]);
}

# -------------------------------------------------------------------------------------------------
# Initialize the queue items by queue signatures, or by the routes
# - routes is a list of initial routes as strings
# - signatures is a list of initial queue chains, as an array of objects

sub _initialize {
	my ( $self ) = @_;

	my $initial_signatures = $self->_hash()->{signatures} // [];
	if( scalar( @{ $initial_signatures } )){
		foreach my $chain_object ( @{ $initial_signatures }){
			my $label = $chain_object->{label} // '';
			msgVerbose( "initialize() signature for '$label'" );
			if( scalar( @{ $chain_object->{chain} })){
				my $item = TTP::HTTP::Compare::QueueItem->new_by_chain( $self->ep(), $self->conf(), $chain_object->{chain} );
				#$item->dump();
				push( @{ $self->{_queue} }, $item );
			} else {
				msgVerbose( "chain is empty" );
			}
		}
	} else {
		my $initial_routes = $self->_hash()->{routes} || [ '/' ];
		foreach my $route ( @{ $initial_routes }){
			# make sure the path is absolute
			$route = "/$route" if $route !~ /^\//;
			# and push
			push( @{ $self->{_queue} }, TTP::HTTP::Compare::QueueItem->new( $self->ep(), $self->conf(), { path => $route }));
		}
	}
}

# -------------------------------------------------------------------------------------------------
# Returns true if a max has been reached
# (I):
# - the current role

sub _max_reached {
	my ( $self ) = @_;
	return true if $self->{_result}{count}{visited} >= $self->conf()->runCrawlMaxVisited() && $self->conf()->runCrawlMaxVisited() > 0;
	return false;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - the password of account

sub _password {
	my ( $self ) = @_;

	my $hash = $self->_hash();
	$hash->{credentials} //= {};

	return $hash->{credentials}{password};
}

# -------------------------------------------------------------------------------------------------
# record a result step:
# (I):
# - the current queue item
# - capture from reference site
# - capture from new site
# - an optional options hash with following keys:
#   > compare: the comparison result (an array ref of error messages)

sub _record_result {
    my ( $self, $queue_item, $ref, $new, $args ) = @_;
	$args //= {};

	# build the pushed object
	my $data = {
		place    => $queue_item,
		ref	     => $ref,
		new      => $new
	};
	$data->{compare} = $args->{compare} if defined $args->{compare};

	# record all results in a single array
	my $key = $queue_item->signature();
	$self->{_result}{seen}{$key} = $data;
	msgVerbose( "record_result() queue_signature='$key'" );

	# have an array per reference status
	my $status_ref = $ref->status();
	$self->{_result}{status}{$status_ref} //= [];
	push( @{$self->{_result}{status}{$status_ref}}, $data );

	# record pages with a full entry and at least an error
	push( @{$self->{_result}{errors}}, $data ) if defined $args->{compare} && scalar( @{$args->{compare}} );
}

# -------------------------------------------------------------------------------------------------
# To be sure the shifted queue item is applyable, try to restore the origin clicks chain.
# The site is expected to already have been navigated to so do not look at the path but only consider frames
# We loop into the chain until getting the same page signature than the origin one.
# (I):
# - the current queue item
# - an optional options hash with following keys:
#   > relogin: true when run for the second time, so do not try to re-login another time, defaulting to false
# (O):
# - whether we have successively restored the clicks chain, and clicked on this ref site target, so true|false

sub _restore_chain {
	my ( $self, $queue_item, $args ) = @_;
	$args //= {};
	msgVerbose( "restore_chain()" );

	# make sure we have the same origin frames signature
	my $origin_signature = $queue_item->origin() || $queue_item->dest();
	my $current_signature = $self->{_browsers}{ref}->signature({ label => 'current' });

	# reapply each and every queued item from the saved chain on both ref and new sites
	if( $current_signature ne $origin_signature ){
		msgVerbose( "expected signature='$origin_signature'" );
		foreach my $qi ( @{ $queue_item->chain() }){
			msgVerbose( "restore_chain() restoring qi='".$qi->signature()."'" );
			# navigate by link
			my $current_path = TTP::HTTP::Compare::Utils::page_signature_to_path( $current_signature );
			my $origin_path = TTP::HTTP::Compare::Utils::page_signature_to_path( $queue_item->origin() || $queue_item->dest());
			if( $qi->isLink() || $current_path ne $origin_path ){
				$self->{_browsers}{ref}->navigate( $origin_path );
				$self->{_browsers}{new}->navigate( $origin_path );
			# navigate by click
			} elsif( $qi->isClick()){
				if( !$self->{_browsers}{ref}->click_by_xpath( $qi->xpath() )){
					msgVerbose( "restore_chain() unable to click on ref for '".$qi->xpath()."'" );
					return false;
				}
				if( !$self->{_browsers}{new}->click_by_xpath( $qi->xpath() )){
					msgVerbose( "restore_chain() unable to click on new for '".$qi->xpath()."'" );
					return false;
				}
			} else {
				msgWarn( "unexpected from='".$qi->from()."'" );
				return false;
			}
			# wait for page ready
			$self->{_browsers}{ref}->wait_for_page_ready();
			$self->{_browsers}{new}->wait_for_page_ready();
			# take a screenshot post-navigate
			if( $self->conf()->confCrawlByClickIntermediateScreenshots()){
				# prepare the post-navigation label
				my $label = sprintf( "restored_%06d", $qi->visited());
				my $cap = $self->{_browsers}{ref}->wait_and_capture({ wait => false });
				$cap->writeScreenshot( $queue_item, { dir => $self->{_roledir}, suffix => $label, subdir => 'restored' });
				# and same on new site
				$cap = $self->{_browsers}{new}->wait_and_capture({ wait => false });
				$cap->writeScreenshot( $queue_item, { dir => $self->{_roledir}, suffix => $label, subdir => 'restored' });
			}
			# check the new signature exiting this restore loop as soon as we have got the right signature on the both sites
			$current_signature = $self->{_browsers}{ref}->signature({ label => 'current' });
			my $new_signature = $self->{_browsers}{new}->signature({ label => 'new' });
			last if $current_signature eq $origin_signature && TTP::HTTP::Compare::Utils::page_signature_are_same( $current_signature, $new_signature );
			# retry this same restore chain once if a cookie have expired
			my $relogin = $args->{relogin} // false;
			if( !$relogin && ( $self->_try_to_relogin( 'ref', $current_signature ) || $self->_try_to_relogin( 'new', $new_signature ))){
				return $self->_restore_chain( $queue_item, { relogin => true });
			}
		}
	}

	# check the result
	if( $current_signature ne $origin_signature ){
		msgVerbose( "restore_chain() unsuccessful (got signature='$current_signature')" );
		return false;
	} else {
		msgVerbose( "restore_chain() success" );
	}

	return $self->{_browsers}{ref}->click_by_xpath( $queue_item->xpath());
}

# -------------------------------------------------------------------------------------------------
# When about to click somewhere, we have to verify that the click will be applyable.
# In other terms, restore the context where the click was valid.
# (I):
# - the current queue item
# - an optional options hash with following keys:
#   > force: whether we force the nvagation, defaulting to false
#   > signature: the current page signature, defaulting to none
# (O):
# - whether we have successively restored the origin path

sub _restore_path {
	my ( $self, $queue_item, $args ) = @_;
	$args //= {};

	my $force = false;
	$force = $args->{force} if defined $args->{force};

	# make sure we have the origin top path
	my $current_signature = $args->{signature} // $self->{_browsers}{ref}->signature();
	my $current_p = TTP::HTTP::Compare::Utils::page_signature_to_path( $current_signature );
	my $origin_p = TTP::HTTP::Compare::Utils::page_signature_to_path( $queue_item->origin() || $queue_item->dest());

	if( $force || $current_p ne $origin_p ){
		msgVerbose( "restore_path() ref path has changed to '$current_p' (or force=$force), try to re-navigate to '$origin_p'" );
		# navigate on ref
		$self->{_browsers}{ref}->navigate( $origin_p );
		$self->{_browsers}{ref}->wait_for_page_ready();
		# navigate on new
		$self->{_browsers}{new}->navigate( $origin_p );
		$self->{_browsers}{new}->wait_for_page_ready();
		# check the navigation result
		$current_signature = $self->{_browsers}{ref}->signature();
		$current_p = TTP::HTTP::Compare::Utils::page_signature_to_path( $current_signature );
		if( $current_p ne $origin_p ){
			msgVerbose( "restore_path() unsuccessful (got path='$current_p')" );
			return false;
		}
	} else {
		msgVerbose( "restore_path() origin='$origin_p' current='$current_p': fine" );
	}

	return true;
}

# -------------------------------------------------------------------------------------------------
# try to print an intermediate result for the role
# each 100 visits
# (I):
# - nothing

sub _try_to_print_intermediate_results {
	my ( $self ) = @_;

	my $visits = $self->{_result}{count}{visited};

	if( $visits % 100 == 0 ){
		$self->print_results_summary();
	}
}

# -------------------------------------------------------------------------------------------------
# try to relogin on the site if we have got the signin page
# (I):
# - the which site 'ref'|'new'
# - the page signature
# (O):
# - true if we had to re-login and this re-login has been successful, so wants to re-run the restore chain
# - false else (just continue as we can)

sub _try_to_relogin {
	my ( $self, $which, $page_signature ) = @_;

	my $rerun = false;
	my $page_path = TTP::HTTP::Compare::Utils::page_signature_to_path( $page_signature );
	my $frames_paths = TTP::HTTP::Compare::Utils::page_signature_to_frames_path( $page_signature );
	my $loginConf = $self->conf()->var( 'login' ) // {};
	my $loginPath = $loginConf->{path} // '';

	if( $page_path eq $loginPath || grep( /$loginPath/, @{ $frames_paths })){
		# yes the site has reached a login page, most probably because the cookie has expired
		# renew the login
		msgVerbose( "trying to re-login" );
		my $loginObj = TTP::HTTP::Compare::Login->new( $self->ep(), $self->conf());
		if( !TTP::errs() && $loginObj->isDefined() && $self->_wants_login()){
			$self->{_logins}{$which} = $loginObj->logIn( $self->{_browsers}{$which}, $self->_username(), $self->_password());
			if( !$self->{_logins}{$which} ){
				msgErr( "unable to log-in/authenticate on '$which' site" );
				# login unsuccessful: just continue as we can
				return false;
			} else {
				msgVerbose( "successful re-login" );
				$rerun = true;
			}
		}
	}

	return $rerun;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - the name of account

sub _username {
	my ( $self ) = @_;

	my $hash = $self->_hash();
	$hash->{credentials} //= {};

	return $hash->{credentials}{username};
}

# -------------------------------------------------------------------------------------------------
# Determines if this role can log-in to the sites.
# True if we have both a login and a password.
# (I):
# - nothing
# (O):
# - whether the role must log-in

sub _wants_login {
	my ( $self ) = @_;

	my $can = false;

	if( $self->_username()){
		if( $self->_password()){
			$can = true;
		} else {
			msgVerbose( "password is not set" );
		}
	} else {
		msgVerbose( "username is not set")
	}

	return $can;
}

### Public methods

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - a ref to the TTP::HTTP::Compare::Config configuration object as provided at instanciation time

sub conf {
    my ( $self ) = @_;

	return $self->{conf};
}

# -------------------------------------------------------------------------------------------------
# Seems that the DESTRUCT Perl phase, which should run the DESTROY sub of the classes, doesn't work
# very well - just call it before while still in RUN phase

sub destroy {
    my ( $self ) = @_;

	$self->{_browsers}{ref}->destroy();
	$self->{_browsers}{new}->destroy();
}

# -------------------------------------------------------------------------------------------------
# Compare the provided URLs for the role.
# (I):
# - the output root directory
# - an optional options hash with following keys:
#   > debug: whether we want run thr browser drivers in debug mode, defaulting to false
#   > signatures: a TTP::HTTP::Compare::Signatures object or undef
# (O):
# - the comparison result as a ref to a hash

sub doCompare {
	my ( $self, $rootdir, $args ) = @_;
	$args //= {};

	# the output result
	$self->{_roledir} = File::Spec->catdir( $rootdir, "byRole", $self->name());
	$self->{_result} = {};
	# counters
	$self->{_result}{count} = {};
	$self->{_result}{count}{depth} = 0;		# the recursion level, starting from zero
	$self->{_result}{count}{visited} = 0;	# the total count of visited places, incremented both when crawling by link or by click
	$self->{_result}{count}{clicks} = 0;	# the count of tried crawl by clicks
	$self->{_result}{count}{links} = 0;		# the count of tried crawl by links
	#
	$self->{_result}{seen} = {};		    # the result of each and every seen place a hash of queue_items signature -> result
	$self->{_result}{status} = {};			# results per http status
	$self->{_result}{errors} = [];			# list of full results which have at least an error
	$self->{_result}{cancelled} = {};		# list of cancelled queue items
	$self->{_result}{unexpected} = {};		# list of unexpected errors
	$self->{_result}{clicked} = [];			# the list of clicked events for the current url

	# instanciates our internal browsers
	# errors here end the program (most often a chromedrive version issue or a path mismatch)
	if( !TTP::errs()){
		$self->{_browsers} = {
			ref => TTP::HTTP::Compare::Browser->new( $self->ep(), $self, 'ref', $args ),
			new => TTP::HTTP::Compare::Browser->new( $self->ep(), $self, 'new', $args )
		};
		if( !$self->{_browsers}{ref} ){
			msgErr( "unable to instanciate a browser driver on 'ref' site" );
		}
		if( !$self->{_browsers}{new} ){
			msgErr( "unable to instanciate a browser driver on 'new' site" );
		}
	}

	# do we must log-in the sites ?
	# yes if we have both a login, a password and a login object which provides the needed selectors
	my $loginObj = TTP::HTTP::Compare::Login->new( $self->ep(), $self->conf());
	if( !TTP::errs() && $loginObj->isDefined() && $self->_wants_login()){
		$self->{_logins} = {
			ref => $loginObj->logIn( $self->{_browsers}{ref}, $self->_username(), $self->_password()),
			new => $loginObj->logIn( $self->{_browsers}{new}, $self->_username(), $self->_password())
		};
		if( !$self->{_logins}{ref} ){
			msgErr( "unable to log-in/authenticate on 'ref' site" );
		}
		if( !$self->{_logins}{new} ){
			msgErr( "unable to log-in/authenticate on 'new' site" );
		}
	}

	# continue if we are logged-in on each site (or login is not required)
	if( !TTP::errs()){
		# make sure the role has its output dirs
		# diffs, htmls and screenshots dirs are configured and of the form 'which=ref|new/diffs|html|screenshots'
		make_path( $self->resultsDir());

		# initialize the queue with the configured routes (making sure we have absolute paths)
		$self->_initialize();

		# and crawl until the queue is empty
		while ( @{$self->{_queue}} ){
			$self->_do_crawl( shift @{$self->{_queue}} );
			last if $self->_max_reached();
		}
	}

	return $self->{_result};
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - whether this role is defined

sub isDefined {
	my ( $self ) = @_;

	my $ref = $self->_hash();

	return defined $ref;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - whether this role is enabled

sub isEnabled {
	my ( $self ) = @_;

	my $enabled = $self->_hash()->{enabled};
	$enabled = DEFAULT_ROLE_ENABLED if !defined( $enabled );

	return $enabled;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - the name of this role

sub name {
	my ( $self ) = @_;

	return $self->{_role};
}

# -------------------------------------------------------------------------------------------------
# at end, print a results summary

sub print_results_summary {
	my ( $self ) = @_;
	msgOut( "  output directory: $self->{_roledir}" );
	msgOut( "  visited places count: $self->{_result}{count}{visited}" );
	msgOut( "  - by click: $self->{_result}{count}{clicks}" );
	msgOut( "  - by link: $self->{_result}{count}{links}" );
	msgOut( "  count per HTTP status:" );
	foreach my $status ( sort keys %{$self->{_result}{status}} ){
		msgOut( "  - $status: ".( scalar( @{$self->{_result}{status}{$status}} )));
	}
	# cancelled is a hash of reason -> [ queue_item's ]
	msgOut( "  cancelled places reasons count: ".( scalar( keys %{$self->{_result}{cancelled}} )));
	if( scalar( keys %{$self->{_result}{cancelled}} )){
		foreach my $reason ( sort keys %{$self->{_result}{cancelled}} ){
			msgOut( "  > $reason: ".scalar( @{$self->{_result}{cancelled}{$reason}} ));
			my @c = ();
			foreach my $iq ( @{$self->{_result}{cancelled}{$reason}} ){
				push( @c, $iq->visited());
			}
			msgOut( "    [".join( ", ", sort { $a <=> $b } @c )."]");
		}
	}
	# errors is an array of comparison results
	msgOut( "  differences total count: ".( scalar( @{$self->{_result}{errors}} )));
	my $errs = {};
	foreach my $data ( @{$self->{_result}{errors}} ){
		foreach my $e ( @{$data->{compare}} ){
			$errs->{$e} //= [];
			push( @{$errs->{$e}}, $data );
		}
	}
	msgOut( "  differences reasons count: ".( scalar( keys %{$errs} )));
	foreach my $reason ( sort keys %{$errs} ){
		msgOut( "  - $reason: count=".scalar( @{ $errs->{$reason}} ));
		my @c = ();
		foreach my $data ( @{ $errs->{$reason}} ){
			push( @c, $data->{place}->visited());
		}
		msgOut( "    [".join( ", ", sort { $a <=> $b } @c )."]");
	}
	# unexpected is a hash of reason -> [ queue_item's ]
	msgOut( "  unexpected count: ".( scalar( keys %{$self->{_result}{unexpected}} )));
	if( scalar( keys %{$self->{_result}{unexpected}} )){
		foreach my $reason ( sort keys %{$self->{_result}{unexpected}} ){
			msgOut( "  > $reason: ".scalar( @{$self->{_result}{unexpected}{$reason}} ));
			my @c = ();
			foreach my $iq ( @{$self->{_result}{unexpected}{$reason}} ){
				push( @c, $iq->visited());
			}
			msgOut( "    [".join( ", ", sort { $a <=> $b } @c )."]");
		}
	}
	#print STDERR "seen: ".Dumper( $self->{_result}{seen} );
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - the directory where the results have to be written

sub resultsDir {
	my ( $self ) = @_;

	return File::Spec->catdir( $self->{_roledir}, "results" );
}

### Class methods

# -------------------------------------------------------------------------------------------------
# Constructor
# (I):
# - the TTP::EP entry point
# - the role name
# - the TTP::HTTP::Compare::Config configuration object
# (O):
# - this object

sub new {
	my ( $class, $ep, $role, $conf ) = @_;
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
	msgDebug( __PACKAGE__."::new() role='$role'" );

	$self->{_role} = $role;
	$self->{conf} = $conf;

	return $self;
}

### Global functions
### Note for the developer: while a global function doesn't take any argument, it can be called both
### as a class method 'TTP::Package->method()' or as a global function 'TTP::Package::method()',
### the former being preferred (hence the writing inside of the 'Class methods' block which brings
### the class as first argument).

1;
