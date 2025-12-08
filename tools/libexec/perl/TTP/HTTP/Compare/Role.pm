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
use JSON;
use List::Util qw( any );
use MIME::Base64 qw( encode_base64 );
use Path::Tiny qw( path );
use POSIX qw( strftime );
use Scalar::Util qw( blessed );
use Test::More;
use Time::Moment;
use URI;

use TTP;
use vars::global qw( $ep );

use TTP::Constants qw( :all );
use TTP::HTTP::Compare::Capture;
use TTP::HTTP::Compare::DaemonInterface;
use TTP::HTTP::Compare::Facer;
use TTP::HTTP::Compare::Form;
use TTP::HTTP::Compare::QueueItem;
use TTP::HTTP::Compare::Utils;
use TTP::Message qw( :all );
#use TTP::Test qw( :all );

use constant {
	DEFAULT_ROLE_ENABLED => true
};

my $Const = {
	crawlModes => [
		'click',
		'link'
	],
	intermediateResults => 100
};

### Private methods

# -------------------------------------------------------------------------------------------------
# we enter with the next route to examine
# activate all links and click everywhere here
# go on until having reached first of max_depth, or max_links, or max_pages
# (I):
# - the current queue_item
# (O):
# - false if cannot continue with this role

sub _do_crawl {
    my ( $self, $queue_item, $args ) = @_;
	$args //= {};
	my $role = $self->name();
	msgVerbose( "by '$role' Role::do_crawl() now is ".Time::Moment->now->strftime( '%Y-%m-%d %H:%M:%S.%6N %:z' ));

	# test the key signature before incrementing the visited count
	my $key = $queue_item->signature();
	msgVerbose( "by '$role' Role::do_crawl() queue signature='$key'" );
	# if already seen, go next
	if( $self->{_result}{seen}{$key} ){
		msgVerbose( "by '$role' Role::do_crawl() already seen, returning" );
		return true;
	}

	# increments before visiting so that all the dumped files are numbered correctly
	$self->{_result}{count}{visited} += 1;
	$queue_item->visited( $self->{_result}{count}{visited} );
	msgVerbose( "by '$role' Role::do_crawl() visiting=".$queue_item->visited(). " (queue size=".scalar( @{ $self->{_queue} } ).")" );

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

	my $captureRef = undef;
	my $captureNew = undef;
	my $reason = undef;
	my $continue = true;

	# we get both a capture on both the websites, or a reason for not having them
	( $captureRef, $captureNew, $reason ) = @{ $self->_do_crawl_by_click( $queue_item ) } if $from eq 'click';
	( $captureRef, $captureNew, $reason ) = @{ $self->_do_crawl_by_link( $queue_item ) } if $from eq 'link';

	if( $captureRef && $captureNew ){

		my $path = $captureRef->path();

		# check HTTP status
		my $status_ref = $captureRef->status();
		my $status_new = $captureNew->status();

		# if we get the same error both on ref and new, then just cancel this one path, and go to next
		if( $status_ref >= 400 && $status_ref == $status_new ){
			msgVerbose( "[".$self->name()." ($path)] same error code, so just cancel this path" );
			$self->_record_result( $queue_item, $captureRef, $captureNew );
			return $continue;
		}

		# check that status is OK and same for the two sites

		is( $status_ref, 200, "[".$self->name()." ($path)] ref website returns '200' status code" );
		is( $status_new, $status_ref, "[".$self->name()." ($path)] new website got same status code ($status_ref)" );

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

		# reset count of successive errors
		$self->_successive_errors_reset();

	} elsif( !defined( $captureRef ) && !defined( $captureNew )){
		msgVerbose( "by '$role' Role::do_crawl() all values are undef, just skip" );
		if( $reason ){
			$self->{_result}{cancelled}{$reason} //= [];
			push( @{$self->{_result}{cancelled}{$reason}}, $queue_item );
			$continue = $self->_successive_errors_inc( $reason );
		} else {
			# a reason is mandatory, so this is unexpected
			msgWarn( "by '$role' Role::do_crawl() reason is not defined, this is NOT expected" );
			$self->{_result}{unexpected}{no_reason} //= [];
			push( @{$self->{_result}{unexpected}{no_reason}}, $queue_item );
			$continue = $self->_successive_errors_inc( "unexpected_no_reason" );
		}

	} else {
		msgWarn( "by '$role' Role::do_crawl() at least one of captureRef or captureNew is not defined, this is NOT expected" );
		$self->{_result}{unexpected}{not_all_undef} //= [];
		push( @{$self->{_result}{unexpected}{not_all_undef}}, $queue_item );
			$continue = $self->_successive_errors_inc( "unexpected_not_all_undef" );
	}

	# try to print an intermediate result each 100 visits
	$self->_try_to_print_intermediate_results();

	return $continue;
}

# -------------------------------------------------------------------------------------------------
# the queue item comes from a 'click'
# (O):
# - TTP::HTTP::Compare::Capture object of reference site
# - TTP::HTTP::Compare::Capture object of new site
# - current path

sub _do_crawl_by_click {
    my ( $self, $queue_item ) = @_;
	my $role = $self->name();
	msgVerbose( "by '$role' Role::do_crawl_by_click()" );

	# must have an origin and a xpath
	my $origin = $queue_item->origin();
	if( !$origin ){
		msgErr( "by '$role' Role::do_crawl_by_click() queue item without origin" );
		return [ undef, undef, "no origin" ];
	}
	my $xpath = $queue_item->xpath();
	if( !$xpath ){
		if( !$queue_item->{xpath} ){
			msgErr( "by '$role' Role::do_crawl_by_click() queue item without xpath" );
		}
		return [ undef, undef, "no xpath" ];
	}

	my $captureRef = undef;
	my $captureNew = undef;

	# ask the browsers to do the job
	# maybe one of them will have to re-login: handle that here
	# as this may arrive once a day, optimisation is not an issue
	my $results = TTP::HTTP::Compare::DaemonInterface::execute( $self, 'click_and_capture',
		{ queue_item => encode_base64( $queue_item->snapshot()), args => {} },
		{ ref => $self->{_daemons}{ref}, new => $self->{_daemons}{new} },
		{ relogin => \&try_to_relogin }
	);
	if( $results->{ref}{result}{success} && $results->{new}{result}{success} ){
		$captureRef = TTP::HTTP::Compare::Capture->new( $ep, $self->{_facers}{ref}, $results->{ref}{result}{answer} );
		$captureNew = TTP::HTTP::Compare::Capture->new( $ep, $self->{_facers}{new}, $results->{new}{result}{answer} );
	} else {
		return [ undef, undef, "crawl_by_click ref $results->{ref}{result}{reason}" ] if !$results->{ref}{result}{success};
		return [ undef, undef, "crawl_by_click new $results->{new}{result}{reason}" ] if !$results->{new}{result}{success};
	}

	# manage counters
	$self->{_result}{count}{clicks} += 1;

	return [ $captureRef, $captureNew, undef ];
}

# -------------------------------------------------------------------------------------------------
# the queue item comes from a 'link'
# (O):
# - TTP::HTTP::Compare::Capture object of reference site
# - TTP::HTTP::Compare::Capture object of new site
# - the reason when the two previous are undef

sub _do_crawl_by_link {
    my ( $self, $queue_item ) = @_;
	my $role = $self->name();
	msgVerbose( "by '$role' Role::do_crawl_by_link()" );

	# do we have a path to navigate to ?
	my $path = $queue_item->path();
	if( !$path ){
		msgErr( "by '$role' Role::do_crawl_by_link() queue item without path" );
		return [ undef, undef, "no path" ];
	}

	my $captureRef = undef;
	my $captureNew = undef;

	# navigate and capture
	my $results = TTP::HTTP::Compare::DaemonInterface::execute( $self, 'navigate_and_capture',
		{ path => $path },
		{ ref => $self->{_daemons}{ref}, new => $self->{_daemons}{new} }
	);
	if( $results->{ref}{result}{success} && $results->{new}{result}{success} ){
		$captureRef = TTP::HTTP::Compare::Capture->new( $ep, $self->{_facers}{ref}, $results->{ref}{result}{answer} );
		$captureNew = TTP::HTTP::Compare::Capture->new( $ep, $self->{_facers}{new}, $results->{new}{result}{answer} );
	} else {
		return [ undef, undef, "crawl_by_link $results->{ref}{result}{reason}" ] if !$results->{ref}{result}{success};
		return [ undef, undef, "crawl_by_link $results->{new}{result}{reason}" ] if !$results->{new}{result}{success};
	}

	# make sure we have a valid dest as initial routes (which are always by 'link' by definition) do not have origin
	$queue_item->dest( $captureRef->signature()) if !$queue_item->origin();
	$self->{_result}{count}{links} += 1;

	return [ $captureRef, $captureNew, undef ];
}

# -------------------------------------------------------------------------------------------------
# Register clickables area
# After a by-scan-id test, prefer by-xpath
# (I):
# - the current capture from reference site as a TTP::HTTP::Compare::Capture object
# - the current queue item

sub _enqueue_clickables {
    my ( $self, $capture, $queue_item ) = @_;

	my $role = $self->name();
	my $page_signature = $capture->signature();
	msgVerbose( "by '$role' Role::enqueue_clickables() got page_signature='$page_signature'" );
	my $targets = $capture->facer()->daemon()->send_and_get( 'clickable_discover_targets_xpath' );
	my $count = 0;
	#print STDERR "targets: ".Dumper( $targets );
	# - targets are like:
	#   {
	#     "xpath": "//*[@id=\"menu\"]//a[3]",
	#     "text": "Mes rapports et attestations :",
	#     "href": "/bo/44375/14450",
	#     "kind": "a",
	#     "onclick": "",
	#     "docKey": "top" | "iframe[1]:/path",
	#     "frameSrc": "/path/of/iframe"
	#   }
    for my $a ( @{$targets} ){
		next if !$self->_enqueue_clickables_href_allowed( $a->{href} );
		next if !$self->_enqueue_clickables_text_allowed( $a->{text} );
		next if !$self->_enqueue_clickables_xpath_allowed( $a->{xpath} );
		$a->{origin} = $page_signature;
		$a->{from} = 'click';
		$a->{chain} = $queue_item->chain_plus();
		#print STDERR "a ".Dumper( $a->{chain} );
		my $item = TTP::HTTP::Compare::QueueItem->new( $self->ep(), $self->conf(), $a );
		push( @{$self->{_queue}}, $item );
		msgVerbose( "by '$role' Role::enqueue_clickables() enqueuing '".$item->signature()."' (text='$a->{text}')" );
		msgVerbose( "by '$role' Role::enqueue_clickables() -> with chain [ '".join( "', '", @{$item->chain_signatures()} )."' ]" );
		#$item->dump({ prefix => "enqueuing" });
		$count += 1;
    }
	msgVerbose( "by '$role' Role::enqueue_clickables() got $count target(s)" );
}

# -------------------------------------------------------------------------------------------------
# Whether the href is allowed
# (I):
# - the candidate href

sub _enqueue_clickables_href_allowed {
    my ( $self, $href ) = @_;

	my $role = $self->name();

	if( $href ){
		my $denied = $self->conf()->runCrawlByClickHrefDenyPatterns() || [];
		if( scalar( @{$denied} )){
			if( any { $href =~ $_ } @{ $denied } ){
				msgVerbose( "by '$role' Role::enqueue_clickables_href_allowed() '$href' denied by regex" );
				return false;
			}
		}
	}

	return true;
}

# -------------------------------------------------------------------------------------------------
# Whether the text is allowed
# (I):
# - the candidate text

sub _enqueue_clickables_text_allowed {
    my ( $self, $text ) = @_;

	my $role = $self->name();

	if( $text ){
		my $denied = $self->conf()->runCrawlByClickTextDenyPatterns() || [];
		if( scalar( @{$denied} )){
			if( any { $text =~ $_ } @{ $denied } ){
				msgVerbose( "by '$role' Role::enqueue_clickables_text_allowed() '$text' denied by regex" );
				return false;
			}
		}
	}

	return true;
}

# -------------------------------------------------------------------------------------------------
# Whether the xpath is allowed
# (I):
# - the candidate xpath

sub _enqueue_clickables_xpath_allowed {
    my ( $self, $xpath ) = @_;

	my $role = $self->name();

	if( $xpath ){
		my $denied = $self->conf()->runCrawlByClickXpathDenyPatterns() || [];
		if( scalar( @{$denied} )){
			if( any { $xpath =~ $_ } @{ $denied } ){
				msgVerbose( "by '$role' Role::enqueue_clickables_xpath_allowed() '$xpath' denied by regex" );
				return false;
			}
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

	my $role = $self->name();

	# collect links from the capture
	my $links = $capture->extract_links();
	my $count = 0;

	# queue next layer
	my $page_signature = $capture->signature();
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
			msgVerbose( "by '$role' Role::enqueue_links() enqueuing '$p'" );
			$count += 1;
		}
	}

	msgVerbose( "by '$role' Role::enqueue_links() got $count target(s)" );
}

# -------------------------------------------------------------------------------------------------
# Handle the provided form
# (I):
# - the form selector
# - the form description

sub _handle_form {
    my ( $self, $selector, $description ) = @_;

	my $formRef = undef;
	my $formNew = undef;

	my $results = TTP::HTTP::Compare::DaemonInterface::execute( $self, 'handle_form',
		{ selector => $selector, description => $description },
		{ ref => $self->{_daemons}{ref}, new => $self->{_daemons}{new} }
	);
	if( $results->{ref}{result}{success} && $results->{new}{result}{success} ){
		$formRef = TTP::HTTP::Compare::Form->new( $ep, $self->{_daemons}{ref}, $results->{ref}{result}{answer} );
		$formNew = TTP::HTTP::Compare::Form->new( $ep, $self->{_daemons}{new}, $results->{new}{result}{answer} );
	#} else {
	#	return [ undef, undef, undef, "crawl_by_link $results->{ref}{result}{reason}" ] if !$results->{ref}{result}{success};
	#	return [ undef, undef, undef, "crawl_by_link $results->{new}{result}{reason}" ] if !$results->{new}{result}{success};
	}
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
			msgVerbose( "initialize() route='$route'" );
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

	my $role = $self->name();

	# build the pushed object
	my $data = {
		place    => $queue_item,
		# capture has grown to about 150k when splitting the work in per-website daemons
		# so do not keep them as a role full work is more than 15000 iterations
		#ref	     => $ref,
		#new      => $new
	};
	$data->{compare} = $args->{compare} if defined $args->{compare};

	# record all results in a single array
	my $key = $queue_item->signature();
	$self->{_result}{seen}{$key} = $data;
	msgVerbose( "by '$role' Role::record_result() queue_signature='$key'" );

	# have an array per reference status
	my $status_ref = $ref->status();
	$self->{_result}{status}{$status_ref} //= [];
	push( @{$self->{_result}{status}{$status_ref}}, $data );

	# record pages with a full entry and at least an error
	push( @{$self->{_result}{errors}}, $data ) if defined $args->{compare} && scalar( @{$args->{compare}} );
}

# -------------------------------------------------------------------------------------------------
# (I):
# - the error reason when a queue item cannot be treated
# (O):
# - whether we can continue with this role: true|false

sub _successive_errors_inc {
    my ( $self, $reason ) = @_;

	my $continue = true;

	$self->{_result}{successive}{$reason} //= 0;
	$self->{_result}{successive}{$reason} += 1;
	$continue = false if $self->{_result}{successive}{$reason} >= $self->conf()->confCrawlByClickSuccessiveLast();

	return $continue;
}

# -------------------------------------------------------------------------------------------------
# Reset the count of successive errors each time a queue item is successfullly dealt with
# (I):
# - nothing
# (O):
# - nothing

sub _successive_errors_reset {
    my ( $self ) = @_;

	# delete the whole key
	delete $self->{_result}{successive};
	# and recreate it
	$self->{_result}{successive} = {};
}

# -------------------------------------------------------------------------------------------------
# try to print an intermediate result for the role
# each 100 visits
# (I):
# - nothing

sub _try_to_print_intermediate_results {
	my ( $self ) = @_;

	my $visits = $self->{_result}{count}{visited};

	if( $visits % $Const->{intermediateResults} == 0 ){
		$self->print_results_summary();
	}
}

### Public methods

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - the args passed to doCompare() method

sub compareArgs {
    my ( $self ) = @_;

	return $self->{_args};
}

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
# Starting with v4.26.0, role comparison between 'ref' and 'new' sites relies on a multi-threads code.
# A thread is created for each of 'ref' and 'new' browser when starting the role comparison, and
# terminated at the end of the comparison.
# (I):
# - the output root directory
# - the worker path
# - an optional options hash with following keys:
#   > debug: whether we want run thr browser drivers in debug mode, defaulting to false
# (O):
# - nothing

sub doCompare {
	my ( $self, $rootdir, $worker, $args ) = @_;
	$args //= {};

	# initial parameters
	$self->{_args} = {};
	$self->{_args}{rootdir} = $rootdir;
	$self->{_args}{worker} = $worker;
	$self->{_args}{args} = $args;
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
	$self->{_result}{successive} = {};		# count of successive errors

	# allocate a Facer for each the two sites
	# the Facer handles for each site the main properties of the role/which run
	$self->{_facers} = {
		ref => TTP::HTTP::Compare::Facer->new( $ep, $self->conf(), $self, { which => 'ref', port => $self->conf()->confBasesRefPort(), baseUrl => $self->conf()->confBasesRefUrl() }),
		new => TTP::HTTP::Compare::Facer->new( $ep, $self->conf(), $self, { which => 'new', port => $self->conf()->confBasesNewPort(), baseUrl => $self->conf()->confBasesNewUrl() })
	};

	# start one daemon for each of 'ref' and 'new' sites
	# each process manages its own browser/driver, and the login cookies
	$self->{_daemons} = {
		ref => TTP::HTTP::Compare::DaemonInterface->new( $ep, $self->{_facers}{ref} ),
		new => TTP::HTTP::Compare::DaemonInterface->new( $ep, $self->{_facers}{new} )
	};
	if( TTP::errs()){
		$self->terminate();
		return;
	}
	my $results = TTP::HTTP::Compare::DaemonInterface::execute( $self, 'internal_status',
		undef,
		{ ref => $self->{_daemons}{ref}, new => $self->{_daemons}{new} }
	);
	if( !$results->{ref}{result}{success} ){
		msgErr( "by '".$self->name().":ref' Role::doCompare() daemon didn't start on time" );
		$self->terminate();
		return;
	}
	if( !$results->{ref}{result}{success} ){
		msgErr( "by '".$self->name().":new' Role::doCompare() daemon didn't start on time" );
		$self->terminate();
		return;
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
			my $continue = $self->_do_crawl( shift @{$self->{_queue}} );
			if( $continue ){
				if( $self->_max_reached()){
					msgVerbose( "cancelling '".$self->name()."' role crawl as due to max limit reached" );
					last;
				}
			} else {
				msgWarn( "cancelling '".$self->name()."' role crawl as due to max successive errors reached" );
				last;
			}
		}
	}

	# nothing to return: all results have been gathered and stored during the crawl execution
	msgOut( "ending with '".$self->name()."' role crawl" );
	$self->terminate();
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
	msgOut( "  total count of unrecoverable erros: $self->{_errs}" );
	#print STDERR "seen: ".Dumper( $self->{_result}{seen} );
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - the top directory of the role output tree

sub roleDir {
	my ( $self ) = @_;

	return $self->{_roledir};
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - the directory where the results have to be written

sub resultsDir {
	my ( $self ) = @_;

	return File::Spec->catdir( $self->roleDir(), "results" );
}

# -------------------------------------------------------------------------------------------------
# Seems that the DESTRUCT Perl phase, which should run the DESTROY sub of the classes, doesn't work
# very well - just call it before while still in RUN phase
# Must make sure that all threads are terminated.

sub terminate {
    my ( $self ) = @_;

	my $role = $self->name();

	if( $self->{_daemons}{ref} ){
		msgVerbose( "by '$role:ref' Role::terminate() terminating..." );
		$self->{_daemons}{ref}->terminate();
		delete $self->{_daemons}{ref};
	}
	if( $self->{_daemons}{new} ){
		msgVerbose( "by '$role:new' Role::terminate() terminating..." );
		$self->{_daemons}{new}->terminate();
		delete $self->{_daemons}{new};
	}
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

# -------------------------------------------------------------------------------------------------
# try to relogin on the site if we have got the signin page
# when relogging in, stop the current daemon and restart a new one
# NB: this is a global function as provided to the daemon as a code ref
# (I):
# - the current TTP::HTTP::Compare::Role instance
# - the command
# - the arguments
# - the hash on involved interfaces
# - the results
# - the involved key name
# (O):
# - true|false

sub try_to_relogin {
	my ( $roleObj, $command, $args, $interfaces, $results, $name ) = @_;

	my $role = $interfaces->{$name}->facer()->roleName();
	my $which = $interfaces->{$name}->facer()->which();

	msgVerbose( "by '$role:$which' Role::try_to_relogin()" );

	# terminate the current daemon
	$interfaces->{$name}->terminate();
	delete $interfaces->{$name};
	# re-allocate a new daemon - will connect to the browser and log-in
	my $interface = TTP::HTTP::Compare::DaemonInterface->new( $ep, $roleObj->{_facers}{$which} );
	$interfaces->{$name} = $interface;
	$roleObj->{_daemons}{$name} = $interface;
	if( !$interface->wait_ready()){
		msgErr( "by '".$role->name().":$name' Role::try_to_relogin() daemon not ready" );
		return false;
	}
	# update the corresponding results part
	$args //= {};
	$args->{relogin} = true;
	my $socket = $interface->send_command( $command, $args );
	if( $socket ){
		$results->{$name}{'TTP::HTTP::Compare::DaemonInterface'}{socket} = $socket;
	} else {
		msgErr( "by '$role:$name' Role::try_to_relogin() unable to send command" );
		return false;
	}

	return true;
}

1;
