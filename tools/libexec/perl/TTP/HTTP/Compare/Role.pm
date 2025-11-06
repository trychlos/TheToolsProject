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
# Capture both on ref and new site.
# (I):
# - the current queue item, which is expected to have been already successfully clicked
# (O):
# - capture from ref site
# - capture from new site

sub _capture_by_click {
	my ( $self, $queue_item ) = @_;

	my $cap_ref = $self->{_browsers}{ref}->wait_and_capture();

	# Re-discover a clickable with same visible text (best effort) and click there too
	if( !$self->{_browsers}{new}->click_by_xpath( $queue_item->xpath())){
		msgVerbose( "xpath='".$queue_item->xpath()."' not available on new site" );
		my $match_new = $self->{_browsers}{new}->clickable_find_equivalent_xpath( $queue_item );
		if( $match_new ){
			if( $self->{_browsers}{new}->click_by_xpath( $match_new )){
				msgVerbose( "match found '$match_new' on new site" );
			} else {
				msgVerbose( "unable to find a equivalent match for '".$queue_item->xpath()."', cancelling" );
				return [ undef, undef ];
			}
		}
	}

	my $cap_new = $self->{_browsers}{new}->wait_and_capture();

	return [ $cap_ref, $cap_new ];
}

# -------------------------------------------------------------------------------------------------
# we enter with the next route to examine
# activate all links and click everywhere here
# go on until having reached first of max_depth, or max_links, or max_pages
# (I):
# - the current queue_item

sub _do_crawl {
    my ( $self, $queue_item, $args ) = @_;
	$args //= {};

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

	# if already seen, go next
	my $key = $queue_item->signature();
	if( $self->{_result}{seen}{$key} ){
		msgVerbose( "already seen: '$key'" );
		return;
	}

	# what sort of loop item do we have ?
	my $from = $queue_item->from();

	# increments before visiting so that all the dumped files are numbered correctly
	$self->{_result}{count}{visited} += 1;
	$queue_item->visited( $self->{_result}{count}{visited} );
	msgVerbose( "do_crawl() from='$from' visiting=".$queue_item->visited());

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
		$self->_enqueue_clickables( $captureRef, $queue_item ) if $self->conf()->runCrawlByClick();

		# collect links from ref and enqueue them
		# links which would be found in new but would be absent from ref are ignored (as new features)
		$self->_enqueue_links( $captureRef, $queue_item ) if $self->conf()->runCrawlByLink();

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
}

# -------------------------------------------------------------------------------------------------
# the queue item comes from a 'click'
# (O):
# - TTP::HTTP::Compare::Capture object of reference site
# - TTP::HTTP::Compare::Capture object of new site
# - current path

sub _do_crawl_by_click {
    my ( $self, $queue_item ) = @_;

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

	my $key = $queue_item->signature();
	msgVerbose( "do_crawl_by_click() role='".$self->name()."' key='$key'" );
	$queue_item->dump();

	my $path = undef;
	my $captureRef = undef;
	my $captureNew = undef;

	# and try to restore the origin clicks chain if we do not have the same frames
	if( $self->_restore_chain( $queue_item )){
		( $captureRef, $captureNew ) = @{ $self->_capture_by_click( $queue_item ) };
		return [ undef, undef, undef, "no_capture" ] if !$captureRef || !$captureNew;

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

	# do we have a path to navigate to ?
	my $path = $queue_item->path();
	if( !$path ){
		msgErr( "do_crawl() link queued item without path" );
		return [ undef, undef, undef, "no path" ];
	}

	# navigate and capture
	my $key = $queue_item->signature();
	msgVerbose( "do_crawl_by_link() role='".$self->name()."' key='$key'" );
	$queue_item->dump();

	my $captureRef = $self->{_browsers}{ref}->navigate_and_capture( $path );
	my $captureNew = $self->{_browsers}{new}->navigate_and_capture( $path );

	# make sure we have a valid dest as initial routes (which are always by 'link' per definition) do not have origin
	my $page_signature = $self->{_browsers}{ref}->signature();
	$queue_item->dest( $page_signature );

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
	#print STDERR "targets: ".Dumper( $targets );
	my $count = 0;
    for my $a ( @{$targets} ){
		# each it from clickable_discover_targets_xpath() is a hash { href, text, frameSrc, xpath, docKey, kind, onclick }
		if( !$self->_match_auto_referenced( $a->{href} ) && !$self->_match_excluded_pattern( $a->{xpath} )){
			$count += 1;
			$a->{origin} = $page_signature;
			$a->{from} = 'click';
			$a->{chain} = $queue_item->chain_plus();
			#print STDERR "a ".Dumper( $a->{chain} );
			push( @{$self->{_queue}}, TTP::HTTP::Compare::QueueItem->new( $self->ep(), $self->conf(), $a ));
		}
    }
	msgVerbose( "enqueue_clickables() got $count targets" );
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

	# from each link, get the full absolute path, maybe with its query fragment
	my @next_paths;
	my $prefixes = $self->conf()->crawlPrefixPath() || [ '' ];
	my $follow_query = $self->conf()->crawlFollowQuery();

	for my $abs ( @{$links} ){
		# whether to follow only the path or also the query fragment
    	my $u = URI->new( $abs );
    	$u->fragment( undef );
		my $p = $follow_query ? $u->path_query : $u->path;
		next if $p eq '';
		next if $p =~ m{^/logout\b}i; # extra guard
		next unless $self->_url_allowed( $p );
		# honor candidate path prefixes
		foreach my $prefix ( @{$prefixes} ){
			my $key = "link|$prefix.$p";
			if( !$self->{_result}{seen}{$key} ){
				push( @next_paths, "$prefix$p" );
			}
		}
	}

	# queue next layer
	my $page_signature = $capture->browser()->signature();
	if( scalar( @next_paths )){
		$self->{_result}{count}{depth} += 1;
		foreach my $p ( @next_paths ){
			push( @{$self->{_queue}},
				TTP::HTTP::Compare::QueueItem->new(
					$self->ep(),
					$self->conf(),
					{ path => $p, depth => $self->{_result}{count}{depth}, from => 'link', origin => $page_signature, chain => $queue_item->chain_plus() }
			));
			msgVerbose( "enqueuing '$p'" );
		}
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
# (I):
# - nothing
# (O):
# - the configured routes, always at least a '/' one

sub _initial_routes {
	my ( $self ) = @_;

	my $hash = $self->_hash();

	return $hash->{routes} || [ '/' ];
}

# -------------------------------------------------------------------------------------------------
# Returns true if the provided href match an auto-referenced link, i.e. something like href='#xxx'
# (I):
# - a 'href' attribute
# (O):
# - whether we match an exclusion

sub _match_auto_referenced {
	my ( $self, $href ) = @_;

	# remove id=#.. (auto-referenced)
	if( $href =~ m/^#/ ){
		msgVerbose( "matched href='$href' against auto-referenced '^#'" );
		return true;
	}

	return false;
}

# -------------------------------------------------------------------------------------------------
# Returns true if the provided xpath match an excluded pattern
# (I):
# - a xpath
# (O):
# - whether we match an exclusion

sub _match_excluded_pattern {
	my ( $self, $xpath ) = @_;

	my $excluded = $self->conf()->runExcludePatterns();
	for my $rx ( @{$excluded} ){
		if( $xpath =~ m/$rx/i ){
			msgVerbose( "matched xpath='$xpath' against excluded '$rx'" );
			return true;
		}
	}

	return false;
}

# -------------------------------------------------------------------------------------------------
# Returns true if a max has been reached
# (I):
# - the current role

sub _max_reached {
	my ( $self ) = @_;
	return true if $self->{_result}{count}{visited} >= $self->conf()->runMaxVisited() && $self->conf()->runMaxVisited() > 0;
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
# (O):
# - whether we have successively restored the clicks chain, and clicked on this ref site target

sub _restore_chain {
	my ( $self, $queue_item ) = @_;
	msgVerbose( "restore_chain()" );

	# make sure we have the same origin frames signature
	my $origin_signature = $queue_item->origin() || $queue_item->dest();
	my $current_signature = $self->{_browsers}{ref}->signature();

	# reapply each and every queued item from the saved chain
	if( $current_signature ne $origin_signature ){
		foreach my $qi ( @{ $queue_item->chain() }){
			# navigate by link
			my $current_path = TTP::HTTP::Compare::Utils::page_signature_to_path( $current_signature );
			my $origin_path = TTP::HTTP::Compare::Utils::page_signature_to_path( $queue_item->origin() || $queue_item->dest());
			if( $qi->isLink() || $current_path ne $origin_path ){
				#$self->_restore_path( $qi, { force => true, signature => $current_signature });
				$self->{_browsers}{ref}->navigate( $origin_path );
				$self->{_browsers}{new}->navigate( $origin_path );
			# navigate by click
			} elsif( $qi->isClick()){
				if( !$self->{_browsers}{ref}->click_by_xpath( $qi->xpath() )){
					msgVerbose( "restore_chain() unable to click on ref for '".$qi->xpath()."'" );
					return false;
				}
				my $match_new = $self->{_browsers}{new}->clickable_find_equivalent_xpath( $qi );
				if( !$match_new ){
					msgVerbose( "restore_chain() unable to find a new equivalent for '".$qi->xpath()."'" );
					return false;
				}
				if( !$self->{_browsers}{new}->click_by_xpath( $match_new )){
					msgVerbose( "restore_chain() unable to click on new for '$match_new'" );
					return false;
				}
			} else {
				msgWarn( "unexpected from='".$qi->from()."'" );
			}
			# prepare the post-navigation label
			my $label = sprintf( "restored_%06d", $qi->visited());
			# take a screenshot post-navigate
			my $cap = $self->{_browsers}{ref}->wait_and_capture();
			$cap->writeScreenshot( $queue_item, { dir => $self->{_roledir}, suffix => $label });
			# and same on new site
			$cap = $self->{_browsers}{new}->wait_and_capture();
			$cap->writeScreenshot( $queue_item, { dir => $self->{_roledir}, suffix => $label });
			# check the new signature
			$current_signature = $self->{_browsers}{ref}->signature();
			last if $current_signature eq $origin_signature;
		}
	}

	# check the result
	if( $current_signature ne $origin_signature ){
		msgVerbose( "restore_chain() unsuccessful (got signature='$current_signature')" );
		return false;
	} else {
		msgVerbose( "restore_chain() origin='$origin_signature' current='$current_signature': fine" );
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
# (I):
# - the candidate url
# (O):
# - whether the url is allowed to be crawled

sub _url_allowed {
	my ( $self, $url ) = @_;

    # Deny first
	my $denied = $self->conf()->runUrlDeniedRegex() || [];
    if( scalar( @{$denied} )){
        return false if any { $url =~ $_ } @{ $denied };
    }

    # If no allow patterns provided/compiled -> allow everything (default)
    return true if $self->conf()->runUrlAllowedAll();

    # Else require at least one allow match
    return any { $url =~ $_ } @{ $self->conf()->runUrlAllowedRegex() };
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
# Compare the provided URLs for the role.
# (I):
# - the output root directory
# - an optional options hash with following keys:
#   > debug: whether we want run thr browser drivers in debug mode, defaulting to false
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
		foreach my $route ( @{ $self->_initial_routes() }){
			# make sure the path is absolute
			$route = "/$route" if $route !~ /^\//;
			# and push
			push( @{ $self->{_queue} }, TTP::HTTP::Compare::QueueItem->new( $self->ep(), $self->conf(), { path => $route }));
		}

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
### the former being preferred (hence the writing inside of the 'Class methods' block which brings
### the class as first argument).

1;
