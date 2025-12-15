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

package TTP::HTTP::Compare::Config;
die __PACKAGE__ . " must be loaded as TTP::HTTP::Compare::Config\n" unless __PACKAGE__ eq 'TTP::HTTP::Compare::Config';

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Data::Dumper;
use Digest::SHA qw( sha1_hex );
use File::Spec;
use Role::Tiny::With;
use Scalar::Util qw( blessed );
use Sereal::Decoder;

with 'TTP::IEnableable', 'TTP::IJSONable';

use TTP;
use vars::global qw( $ep );

use TTP::Constants qw( :all );
use TTP::HTTP::Compare::Utils;
use TTP::Message qw( :all );

# first define the constants which are re-used later
use constant {
	COMPARE_SCREENSHOTS_ENABLED_ALWAYS => "always",
	COMPARE_SCREENSHOTS_ENABLED_NEVER => "never",
	COMPARE_SCREENSHOTS_ENABLED_ONERROR => "onerror"
};

# and now other constants (can use already defined constants)
use constant {
	DEFAULT_BROWSER_COMMAND => "chromedriver --port=9515 --url-base=/wd/hub --verbose",
	DEFAULT_BROWSER_HEIGHT => 768,
	DEFAULT_BROWSER_DELAYS_WAIT_FOR_DOM_STABLE => 1.0,
	DEFAULT_BROWSER_DELAYS_WAIT_FOR_NETWORK_IDLE => 1.0,
	DEFAULT_BROWSER_DRIVER_PORT => 9515,
	DEFAULT_BROWSER_DRIVER_SERVER => '127.0.0.1',
	DEFAULT_BROWSER_EXECJS_RETRIES => 5,
	DEFAULT_BROWSER_EXECJS_SLEEP => 5,
	DEFAULT_BROWSER_NAVIGATE_RETRIES => 5,
	DEFAULT_BROWSER_NAVIGATE_SLEEP => 5,
	DEFAULT_BROWSER_TIMEOUTS_EXECUTE => 10.0,
	DEFAULT_BROWSER_TIMEOUTS_GENERIC_WAITER => 10.0,
	DEFAULT_BROWSER_TIMEOUTS_GET_ANSWER => 10.0,
	DEFAULT_BROWSER_TIMEOUTS_HTTP => 10,
	DEFAULT_BROWSER_TIMEOUTS_SEND_COMMAND => 10.0,
	DEFAULT_BROWSER_TIMEOUTS_UA => 10,
	DEFAULT_BROWSER_TIMEOUTS_WAIT_FOR_BODY => 10.0,
	DEFAULT_BROWSER_TIMEOUTS_WAIT_FOR_DOM_STABLE => 10.0,
	DEFAULT_BROWSER_TIMEOUTS_WAIT_FOR_NETWORK_IDLE => 10.0,
	DEFAULT_BROWSER_TIMEOUTS_WAIT_FOR_PAGE_READY => 15.0,
	DEFAULT_BROWSER_TIMEOUTS_WAIT_FOR_URL_CHANGE => 10.0,
	DEFAULT_BROWSER_WIDTH => 1366,
	DEFAULT_COMPARE_HTML_ENABLED => false,
	DEFAULT_COMPARE_HTML_IGNORE_DOM_ATTRIBUTES => [
		"^aria-"
	],
	DEFAULT_COMPARE_HTML_IGNORE_DOM_SELECTORS => [
		"script",
		"style"
	],
	DEFAULT_COMPARE_HTML_IGNORE_TEXT_PATTERNS => [],
	DEFAULT_COMPARE_SCREENSHOTS_ENABLED => COMPARE_SCREENSHOTS_ENABLED_ONERROR,
	DEFAULT_COMPARE_SCREENSHOTS_RMSE => 0.01,
	DEFAULT_COMPARE_SCREENSHOTS_THRESHOLD_COUNT => 150,
	DEFAULT_CRAWL_BY_CLICK_CSS_EXCLUDES => [
		"th > a"
	],
	DEFAULT_CRAWL_BY_CLICK_ENABLED => false,
	DEFAULT_CRAWL_BY_CLICK_FINDERS => [
		"a[href]",
		"[role=\"link\"]",
		"[data-link]",
		"[data-router-link]",
		"button",
		"[onclick]"
	],
	DEFAULT_CRAWL_BY_CLICK_HREF_DENY_PATTERNS => [
		"^#.+|^callto:|^mailto:|^tel:",
		"\.xls\$"
	],
	DEFAULT_CRAWL_BY_CLICK_INTERMEDIATE_SCREENSHOTS => false,
	DEFAULT_CRAWL_BY_CLICK_SUCCESSIVE_LAST => 10,
	DEFAULT_CRAWL_BY_CLICK_TEXT_DENY_PATTERNS => [
	],
	DEFAULT_CRAWL_BY_CLICK_XPATH_DENY_PATTERNS => [
		"\\bexit\\b",
		"\\blogout\\b",
		"\\bdelete\\b",
		"\\bsignin\\b",
		"\\bsignout\\b"
	],
	DEFAULT_CRAWL_BY_LINK_CSS_EXCLUDES => [
		"th > a"
	],
	DEFAULT_CRAWL_BY_LINK_ENABLED => false,
	DEFAULT_CRAWL_BY_LINK_FINDERS => [
		{
			find => "a[href]",
			member => "href"
		}
	],
	DEFAULT_CRAWL_BY_LINK_HONOR_QUERY => true,
	DEFAULT_CRAWL_BY_LINK_HREF_ALLOW_PATTERNS => [],
	DEFAULT_CRAWL_BY_LINK_HREF_DENY_PATTERNS => [
		"^#.+|^javascript:|^callto:|^mailto:|^tel:",
		"\.xls\$"
	],
	DEFAULT_CRAWL_BY_LINK_TEXT_DENY_PATTERNS => [
	],
	DEFAULT_CRAWL_BY_LINK_URL_ALLOW_PATTERNS => [],
	DEFAULT_CRAWL_BY_LINK_URL_DENY_PATTERNS => [
		"\\bexit\\b",
		"\\blogout\\b",
		"\\bdelete\\b",
		"\\bsignin\\b",
		"\\bsignout\\b"
	],
	DEFAULT_CRAWL_KEEP_HTMLS => false,
	DEFAULT_CRAWL_KEEP_SCREENSHOTS => false,
	DEFAULT_CRAWL_MAX_VISITED => 10,
	DEFAULT_CRAWL_MODE => 'link',
	DEFAULT_CRAWL_PREFIX_PATH => [ '' ],
	DEFAULT_CRAWL_SAME_HOST => true,
	DEFAULT_DIRS_HTMLS => {
		diffs => "",
		new => File::Spec->catdir( "new", "htmls" ),
		ref => File::Spec->catdir( "ref", "htmls" ),
		restored => ""
	},
	DEFAULT_DIRS_SCREENSHOTS => {
		diffs => File::Spec->catdir( "diffs", "screenshots" ),
		new => File::Spec->catdir( "new", "screenshots" ),
		ref => File::Spec->catdir( "ref", "screenshots" ),
		restored => File::Spec->catdir( "restored", "screenshots" ),
	},
	DEFAULT_VERBOSITY_CLICKABLES_DENIED => false,
	DEFAULT_VERBOSITY_CLICKABLES_ENQUEUE => false,
	DEFAULT_VERBOSITY_DAEMON_RECEIVED => false,
	DEFAULT_VERBOSITY_DAEMON_SLEEP => false,
	DEFAULT_VERBOSITY_LINKS_DENIED => false,
	DEFAULT_VERBOSITY_LINKS_ENQUEUE => false,

	MIN_BROWSER_HEIGHT => 3,
	MIN_BROWSER_WIDTH => 4
};

my $Const = {
	CompareScreenshotsEnabled => [
		COMPARE_SCREENSHOTS_ENABLED_ALWAYS,
		COMPARE_SCREENSHOTS_ENABLED_NEVER,
		COMPARE_SCREENSHOTS_ENABLED_ONERROR
	]
};

### Private methods

# -------------------------------------------------------------------------------------------------
# Compile at once all the configured regex patterns just after having successfully loaded the config.
# Compiled regular expressions are stored in $self->{_run}, available through runXxx() methods
# (I):
# - nothing
# (O):
# - nothing

sub _compile_regex_patterns {
    my ( $self ) = @_;

	# by click href denied patterns
    my $raw = $self->confCrawlByClickHrefDenyPatterns();
	my @regex = ();
    for my $s (@{ $raw // [] }) {
        next unless defined $s && length $s;
        my $rx = eval { qr/$s/ };
        if ($@) {
            msgWarn( "Invalid deny regex '$s': $@ (skipping)" );
            next;
        }
        push( @regex, $rx );
    }
	$self->{_run}{click_href_deny_rx} = [ @regex ];

	# by click text denied patterns
    $raw = $self->confCrawlByClickTextDenyPatterns();
	@regex = ();
    for my $s (@{ $raw // [] }) {
        next unless defined $s && length $s;
        my $rx = eval { qr/$s/ };
        if ($@) {
            msgWarn( "Invalid deny regex '$s': $@ (skipping)" );
            next;
        }
        push( @regex, $rx );
    }
	$self->{_run}{click_text_deny_rx} = [ @regex ];

	# by click xpath denied patterns
    $raw = $self->confCrawlByClickXpathDenyPatterns();
	@regex = ();
    for my $s (@{ $raw // [] }) {
        next unless defined $s && length $s;
        my $rx = eval { qr/$s/ };
        if ($@) {
            msgWarn( "Invalid deny regex '$s': $@ (skipping)" );
            next;
        }
        push( @regex, $rx );
    }
	$self->{_run}{click_xpath_deny_rx} = [ @regex ];

	# by link href allowed patterns
    $raw = $self->confCrawlByLinkHrefAllowPatterns();
	@regex = ();
    for my $s (@{ $raw // [] }){
        next unless defined $s && length $s;
        my $rx = eval { qr/$s/ };
        if ($@) {
            msgWarn( "Invalid allow regex '$s': $@ (skipping)" );
            next;
        }
        push( @regex, $rx );
    }
	$self->{_run}{link_href_allow_rx} = [ @regex ];
    # add a flag so checks are cheap during crawl
    $self->{_run}{link_href_allow_all} = ( @regex == 0 ) ? true : false;

	# by link href denied patterns
    $raw = $self->confCrawlByLinkHrefDenyPatterns();
	@regex = ();
    for my $s (@{ $raw // [] }) {
        next unless defined $s && length $s;
        my $rx = eval { qr/$s/ };
        if ($@) {
            msgWarn( "Invalid deny regex '$s': $@ (skipping)" );
            next;
        }
        push( @regex, $rx );
    }
	$self->{_run}{link_href_deny_rx} = [ @regex ];

	# by link text denied patterns
    $raw = $self->confCrawlByLinkTextDenyPatterns();
	@regex = ();
    for my $s (@{ $raw // [] }) {
        next unless defined $s && length $s;
        my $rx = eval { qr/$s/ };
        if ($@) {
            msgWarn( "Invalid deny regex '$s': $@ (skipping)" );
            next;
        }
        push( @regex, $rx );
    }
	$self->{_run}{link_text_deny_rx} = [ @regex ];

	# by link url allowed patterns
    $raw = $self->confCrawlByLinkUrlAllowPatterns();
	@regex = ();
    for my $s (@{ $raw // [] }){
        next unless defined $s && length $s;
        my $rx = eval { qr/$s/ };
        if ($@) {
            msgWarn( "Invalid allow regex '$s': $@ (skipping)" );
            next;
        }
        push( @regex, $rx );
    }
	$self->{_run}{link_url_allow_rx} = [ @regex ];
    # add a flag so checks are cheap during crawl
    $self->{_run}{link_url_allow_all} = ( @regex == 0 ) ? true : false;

	# by link url denied patterns
    $raw = $self->confCrawlByLinkUrlDenyPatterns();
	@regex = ();
    for my $s (@{ $raw // [] }) {
        next unless defined $s && length $s;
        my $rx = eval { qr/$s/ };
        if ($@) {
            msgWarn( "Invalid deny regex '$s': $@ (skipping)" );
            next;
        }
        push( @regex, $rx );
    }
	$self->{_run}{link_url_deny_rx} = [ @regex ];
}

# -------------------------------------------------------------------------------------------------
# Load the configuration path
# Honors the '--dummy' verb option by using msgWarn() instead of msgErr() when checking the configuration
# (I):
# - the absolute path to the JSON configuration file
# - an optional options hash with following keys:
#   > max_pages: the maximum count of pages to visit specified in the command-line, defaulting to the configured one
#   > mode: the mode specified in the command-line, defaulting to the configured one
# (O):
# - true|false whether the configuration has been successfully loaded

sub _loadConfig {
	my ( $self, $path, $args ) = @_;
	$args //= {};
	#print STDERR "args: ".Dumper( $args );

	# IJSONable role takes care of validating the acceptability and the enable-ity
	my $loaded = $self->jsonLoad({ path => $path });
	# evaluate the data if success
	if( $loaded ){
		$self->evaluate();
		msgDebug( __PACKAGE__."::_loadConfig() evaluated to ".TTP::chompDumper( $self->jsonData()));

		# honors the '--dummy' verb option by using msgWarn() instead of msgErr()
		my $msgRef = $self->ep()->runner()->dummy() ? \&msgWarn : \&msgErr;

		# must have ref and new URLs
		my $bases_ref = $self->confBasesRefUrl();
		if( !$bases_ref ){
			$msgRef->( "$path: bases.ref URL is not specified" );
		}
		my $bases_new = $self->confBasesNewUrl();
		if( !$bases_new ){
			$msgRef->( "$path: bases.new URL is not specified" );
		}
		# check browser width and height as these data are needed to handle it
		my $width = $self->confBrowserWidth();
		if( $width <= MIN_BROWSER_WIDTH ){
			$msgRef->( "browser.width='$width' is less or equal to the minimum accepted (".MIN_BROWSER_WIDTH.")" );
		}
		my $height = $self->confBrowserHeight();
		if( $height <= MIN_BROWSER_HEIGHT ){
			$msgRef->( "browser.height='$height' is less or equal to the minimum accepted (".MIN_BROWSER_HEIGHT.")" );
		}
		# check chromedriver address and port
		my $server = $self->confBrowserDriverServer();
		if( !$server ){
			$msgRef->( "browser.driver_server is not defined" );
		}
		my $port = $self->confBrowserDriverPort();
		if( !$port || $port < 1 ){
			$msgRef->( "browser.driver_port=".( $port || '(undef)' )." is not defined or invalid" );
		}
		#
		# the options which are overridable in verb command-line have a 'run' version
		#
		# check max visited count
		my $max_visited = $args->{max_visited} // $self->confCrawlMaxVisited();
		if( $max_visited < 0 ){
			$msgRef->( "crawl.max_visited='$max_visited' is invalid (less than zero)" );
		} else {
			msgVerbose( "loadConfig() runtime max_visited='$max_visited'" );
			$self->{_run}{max_visited} = $max_visited;
		}
		# whether crawl by click
		my $mode = $self->confCrawlByClickEnabled();
		$mode = $args->{by_click} if defined $args->{by_click};
		$self->{_run}{crawl_by_click} = $mode;
		# whether crawl by link
		$mode = $self->confCrawlByLinkEnabled();
		$mode = $args->{by_link} if defined $args->{by_link};
		$self->{_run}{crawl_by_link} = $mode;
		# browser working directory
		my $workdir = $self->confBrowserWorkdir();
		$workdir = $args->{browser_workdir} if defined $args->{browser_workdir};
		$self->{_run}{browser_workdir} = $workdir;

		# if the JSON configuration has been checked but misses some informations, then says we cannot load
		if( TTP::errs()){
			$self->jsonLoaded( false );
		}
	}

	return $self->jsonLoaded();
}

### Public methods

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the listening TCP port number of the daemon which manages the 'new' site

sub confBasesNewPort {
	my ( $self ) = @_;

	my $port = $self->var([ 'bases', 'new', 'port' ]);
	if( !$port ){
		$port = $self->confBasesRefPort();
		$port += 1;
	}

	return $port;
}

# ------------------------------------------------------------------------------------------------
# Returns the base new URL.
# (I):
# - none
# (O):
# - returns the configured base new URL

sub confBasesNewUrl {
	my ( $self ) = @_;

	my $url = $self->var([ 'bases', 'new', 'url' ]);

	return $url;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the listening TCP port number of the daemon which manages the 'ref' site
#   defaulting to the chromedriver listening port number plus 1

sub confBasesRefPort {
	my ( $self ) = @_;

	my $port = $self->var([ 'bases', 'ref', 'port' ]);
	if( !$port ){
		$port = $self->confBrowserDriverPort();
		$port += 1;
	}

	return $port;
}

# ------------------------------------------------------------------------------------------------
# Returns the base reference URL.
# (I):
# - none
# (O):
# - returns the configured base reference URL

sub confBasesRefUrl {
	my ( $self ) = @_;

	my $url = $self->var([ 'bases', 'ref', 'url' ]);

	return $url;
}

# ------------------------------------------------------------------------------------------------
# Returns the worker daemon path.
# (I):
# - none
# (O):
# - returns the worker daemon path, may be undef

sub confBasesWorker {
	my ( $self ) = @_;

	my $path = $self->var([ 'bases', 'worker' ]);

	return $path;
}

# ------------------------------------------------------------------------------------------------
# Returns the configured chromedriver start command.
# (I):
# - none
# (O):
# - returns the configured chromedriver start command

sub confBrowserCommand {
	my ( $self ) = @_;

	my $command = $self->var([ 'browser', 'command' ]);
	$command = DEFAULT_BROWSER_COMMAND if !defined $command;

	return $command;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the configured delay when waiting for a stable DOM, defaulting to 0.5

sub confBrowserDelaysWaitForDomStable {
	my ( $self ) = @_;

	my $delay = $self->var([ 'browser', 'delays', 'wait_for_dom_stable' ]) // DEFAULT_BROWSER_DELAYS_WAIT_FOR_DOM_STABLE;

	return $delay;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the configured delay when waiting for an idle network, defaulting to 0.5

sub confBrowserDelaysWaitForNetworkIdle {
	my ( $self ) = @_;

	my $delay = $self->var([ 'browser', 'delays', 'wait_for_network_idle' ]) // DEFAULT_BROWSER_DELAYS_WAIT_FOR_NETWORK_IDLE;

	return $delay;
}

# ------------------------------------------------------------------------------------------------
# Returns the configured chromedriver listening port, defaulting to 9515.
# (I):
# - none
# (O):
# - returns the configured chromedriver listening port

sub confBrowserDriverPort {
	my ( $self ) = @_;

	my $port = $self->var([ 'browser', 'driver_port' ]);
	$port = DEFAULT_BROWSER_DRIVER_PORT if !defined $port;

	return $port;
}

# ------------------------------------------------------------------------------------------------
# Returns the configured chromedriver server ip addr, defaulting to localhost.
# (I):
# - none
# (O):
# - returns the configured chromedriver server ip addr

sub confBrowserDriverServer {
	my ( $self ) = @_;

	my $server = $self->var([ 'browser', 'driver_server' ]);
	$server = DEFAULT_BROWSER_DRIVER_SERVER if !defined $server;

	return $server;
}

# ------------------------------------------------------------------------------------------------
# Returns the configured browser javascript execution retries count, defaulting to 5.
# (I):
# - none
# (O):
# - returns the configured browser javascript execution retries count

sub confBrowserExecjsRetries {
	my ( $self ) = @_;

	my $count = $self->var([ 'browser', 'exec_js', 'retries' ]);
	$count = DEFAULT_BROWSER_EXECJS_RETRIES if !defined $count;

	return $count;
}

# ------------------------------------------------------------------------------------------------
# Returns the configured browser javascript execution sleep, defaulting to 5 s.
# (I):
# - none
# (O):
# - returns the configured browser javascript execution sleep

sub confBrowserExecjsSleep {
	my ( $self ) = @_;

	my $sleep = $self->var([ 'browser', 'exec_js', 'sleep' ]);
	$sleep = DEFAULT_BROWSER_EXECJS_SLEEP if !defined $sleep;

	return $sleep;
}

# ------------------------------------------------------------------------------------------------
# Returns the configured browser height, defaulting to 768.
# (I):
# - none
# (O):
# - returns the configured browser height

sub confBrowserHeight {
	my ( $self ) = @_;

	my $height = $self->var([ 'browser', 'height' ]);
	$height = DEFAULT_BROWSER_HEIGHT if !defined $height;

	return $height;
}

# ------------------------------------------------------------------------------------------------
# Returns the configured browser navigation retries count, defaulting to 5.
# (I):
# - none
# (O):
# - returns the configured browser navigation retries count

sub confBrowserNavigateRetries {
	my ( $self ) = @_;

	my $count = $self->var([ 'browser', 'navigate', 'retries' ]);
	$count = DEFAULT_BROWSER_NAVIGATE_RETRIES if !defined $count;

	return $count;
}

# ------------------------------------------------------------------------------------------------
# Returns the configured browser navigation sleep, defaulting to 5 s.
# (I):
# - none
# (O):
# - returns the configured browser navigation sleep

sub confBrowserNavigateSleep {
	my ( $self ) = @_;

	my $sleep = $self->var([ 'browser', 'navigate', 'sleep' ]);
	$sleep = DEFAULT_BROWSER_NAVIGATE_SLEEP if !defined $sleep;

	return $sleep;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the configured execute() timeout, defaulting to 10.0 sec.

sub confBrowserTimeoutsExecute {
	my ( $self ) = @_;

	my $timeout = $self->var([ 'browser', 'timeouts', 'execute' ]) // DEFAULT_BROWSER_TIMEOUTS_EXECUTE;

	return $timeout;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the configured generic waiter timeout, defaulting to 5.0 sec.

sub confBrowserTimeoutsGenericWaiter {
	my ( $self ) = @_;

	my $timeout = $self->var([ 'browser', 'timeouts', 'generic_waiter' ]) // DEFAULT_BROWSER_TIMEOUTS_GENERIC_WAITER;

	return $timeout;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the configured timeout when waiting for an answer from the daemon, defaulting to 5.0 sec.

sub confBrowserTimeoutsGetAnswer {
	my ( $self ) = @_;

	my $timeout = $self->var([ 'browser', 'timeouts', 'get_answer' ]) // DEFAULT_BROWSER_TIMEOUTS_GET_ANSWER;

	return $timeout;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the configured HTTP request timeout, defaulting to 10 sec.

sub confBrowserTimeoutsHttp {
	my ( $self ) = @_;

	my $timeout = $self->var([ 'browser', 'timeouts', 'http' ]) // DEFAULT_BROWSER_TIMEOUTS_HTTP;

	return $timeout;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the configured timeout when sending a command to the daemon, defaulting to 5.0 sec.

sub confBrowserTimeoutsSendCommand {
	my ( $self ) = @_;

	my $timeout = $self->var([ 'browser', 'timeouts', 'generic_waiter' ]) // DEFAULT_BROWSER_TIMEOUTS_SEND_COMMAND;

	return $timeout;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the configured Selenium::Remote::Driver LWP user agent timeout, defaulting to 10 sec.

sub confBrowserTimeoutsUa {
	my ( $self ) = @_;

	my $timeout = $self->var([ 'browser', 'timeouts', 'ua' ]) // DEFAULT_BROWSER_TIMEOUTS_UA;

	return $timeout;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the configured timeout when waiting for document body, defaulting to 5.0 sec.

sub confBrowserTimeoutsWaitForBody {
	my ( $self ) = @_;

	my $timeout = $self->var([ 'browser', 'timeouts', 'wait_for_body' ]) // DEFAULT_BROWSER_TIMEOUTS_WAIT_FOR_BODY;

	return $timeout;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the configured timeout when waiting for a stable DOM, defaulting to 5.0 sec.

sub confBrowserTimeoutsWaitForDomStable {
	my ( $self ) = @_;

	my $timeout = $self->var([ 'browser', 'timeouts', 'wait_for_dom_stable' ]) // DEFAULT_BROWSER_TIMEOUTS_WAIT_FOR_DOM_STABLE;

	return $timeout;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the configured timeout when waiting for an idle network, defaulting to 5.0 sec.

sub confBrowserTimeoutsWaitForNetworkIdle {
	my ( $self ) = @_;

	my $timeout = $self->var([ 'browser', 'timeouts', 'wait_for_network_idle' ]) // DEFAULT_BROWSER_TIMEOUTS_WAIT_FOR_NETWORK_IDLE;

	return $timeout;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the configured timeout when waiting for the page be ready, defaulting to 5.0 sec.

sub confBrowserTimeoutsWaitForPageReady {
	my ( $self ) = @_;

	my $timeout = $self->var([ 'browser', 'timeouts', 'wait_for_page_ready' ]) // DEFAULT_BROWSER_TIMEOUTS_WAIT_FOR_PAGE_READY;

	return $timeout;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the configured timeout when waiting for an URL change, defaulting to 5.0 sec.

sub confBrowserTimeoutsWaitForUrlChange {
	my ( $self ) = @_;

	my $timeout = $self->var([ 'browser', 'timeouts', 'wait_for_url_change' ]) // DEFAULT_BROWSER_TIMEOUTS_WAIT_FOR_URL_CHANGE;

	return $timeout;
}

# ------------------------------------------------------------------------------------------------
# Returns the configured browser width, defaulting to 768.
# (I):
# - none
# (O):
# - returns the configured browser width

sub confBrowserWidth {
	my ( $self ) = @_;

	my $width = $self->var([ 'browser', 'width' ]);
	$width = DEFAULT_BROWSER_WIDTH if !defined $width;

	return $width;
}

# ------------------------------------------------------------------------------------------------
# Returns the configured browser working dir.
# (I):
# - none
# (O):
# - returns the configured browser working dir

sub confBrowserWorkdir {
	my ( $self ) = @_;

	my $dir = $self->var([ 'browser', 'workdir' ]) // "";

	return $dir;
}

# ------------------------------------------------------------------------------------------------
# Returns the whether comparison of htmls is enabled.
# (I):
# - none
# (O):
# - returns whether comparison of htmls is enabled

sub confCompareHtmlsEnabled {
	my ( $self ) = @_;

	my $enabled = $self->var([ 'compare', 'htmls', 'enabled' ]);
	$enabled = DEFAULT_COMPARE_HTML_ENABLED if !defined $enabled;

	return $enabled;
}

# ------------------------------------------------------------------------------------------------
# Returns the configured ignored DOM attributes.
# (I):
# - none
# (O):
# - returns the configured ignored DOM attributes

sub confCompareHtmlsIgnoreDOMAttributes {
	my ( $self ) = @_;

	my $ignored = $self->var([ 'compare', 'htmls', 'ignore', 'dom_attributes' ]);
	$ignored = DEFAULT_COMPARE_HTML_IGNORE_DOM_ATTRIBUTES if !defined $ignored || !scalar( @{$ignored // []} );

	return $ignored;
}

# ------------------------------------------------------------------------------------------------
# Returns the configured ignored DOM selectors.
# (I):
# - none
# (O):
# - returns the configured ignored DOM selectors

sub confCompareHtmlsIgnoreDOMSelectors {
	my ( $self ) = @_;

	my $ignored = $self->var([ 'compare', 'htmls', 'ignore', 'dom_selectors' ]);
	$ignored = DEFAULT_COMPARE_HTML_IGNORE_DOM_SELECTORS if !defined $ignored || !scalar( @{$ignored // []} );

	return $ignored;
}

# ------------------------------------------------------------------------------------------------
# Returns the configured ignored text patterns.
# (I):
# - none
# (O):
# - returns the configured ignored text patterns

sub confCompareHtmlsIgnoreTextPatterns {
	my ( $self ) = @_;

	my $ignored = $self->var([ 'compare', 'htmls', 'ignore', 'text_patterns' ]);
	$ignored = DEFAULT_COMPARE_HTML_IGNORE_TEXT_PATTERNS if !defined $ignored || !scalar( @{$ignored // []} );

	return $ignored;
}

# ------------------------------------------------------------------------------------------------
# Returns whether comparison of screenshots is enabled.
# (I):
# - none
# (O):
# - returns whether comparison of screenshots is enabled
#   as a validated value which can be 'always', 'never' or 'onerror'

sub confCompareScreenshotsEnabled {
	my ( $self ) = @_;

	my $enabled = $self->var([ 'compare', 'screenshots', 'enabled' ]);
	$enabled = DEFAULT_COMPARE_SCREENSHOTS_ENABLED if !defined $enabled;
	if( !grep( /$enabled/, @{$Const->{CompareScreenshotsEnabled}} )){
		$enabled = DEFAULT_COMPARE_SCREENSHOTS_ENABLED
	}

	return $enabled;
}

# ------------------------------------------------------------------------------------------------
# Returns the pixel error threshold when comparing screenshots.
# This is a percent, which defaults to 0.01 (1%).
# (I):
# - none
# (O):
# - returns pixel error threshold when comparing screenshots

sub confCompareScreenshotsRmse {
	my ( $self ) = @_;

	my $rmse = $self->var([ 'compare', 'screenshots', 'rmse_threshold' ]);
	$rmse = DEFAULT_COMPARE_SCREENSHOTS_RMSE if !defined $rmse;

	return $rmse;
}

# ------------------------------------------------------------------------------------------------
# When set, this is count of accepted differences between two screenshots.
# Happens that even when two screenshots are visually identical, the Image::Compare package can count
# until about 50 differences...
# (I):
# - none
# (O):
# - returns accepted count of differences, defaulting to one

sub confCompareScreenshotsThresholdCount {
	my ( $self ) = @_;

	my $count = $self->var([ 'compare', 'screenshots', 'threshold_count' ]);
	$count = DEFAULT_COMPARE_SCREENSHOTS_THRESHOLD_COUNT if !defined $count;

	return $count;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the list of CSS deny patterns when crawling by click

sub confCrawlByClickCssExcludes {
	my ( $self ) = @_;

	my $list = $self->var([ 'crawl', 'by_click', 'css_excludes' ]);
	$list = DEFAULT_CRAWL_BY_CLICK_CSS_EXCLUDES if !defined $list;

	return $list;
}

# ------------------------------------------------------------------------------------------------
# Returns whether we crawl by clicks.
# (I):
# - none
# (O):
# - returns whether we crawl by clicks

sub confCrawlByClickEnabled {
	my ( $self ) = @_;

	my $crawl = $self->var([ 'crawl', 'by_click', 'enabled' ]);
	$crawl = DEFAULT_CRAWL_BY_CLICK_ENABLED if !defined $crawl;

	return $crawl;
}

# ------------------------------------------------------------------------------------------------
# Returns the finders
# (I):
# - none
# (O):
# - returns the list of configured finders

sub confCrawlByClickFinders {
	my ( $self ) = @_;

	my $list = $self->var([ 'crawl', 'by_click', 'finders' ]);
	$list = DEFAULT_CRAWL_BY_CLICK_FINDERS if !defined $list;

	return $list;
}

# ------------------------------------------------------------------------------------------------
# Returns the configured href denied patterns, defaulting to the hardcoded list
# (I):
# - none
# (O):
# - returns the configured href denied patterns

sub confCrawlByClickHrefDenyPatterns {
	my ( $self ) = @_;

	my $list = $self->var([ 'crawl', 'by_click', 'href_deny_patterns' ]);
	$list = DEFAULT_CRAWL_BY_CLICK_HREF_DENY_PATTERNS if !defined $list;

	return $list;
}

# ------------------------------------------------------------------------------------------------
# Returns whether to save an intemediate screenshot during the chain restoration.
# (I):
# - none
# (O):
# - returns whether we crawl by clicks

sub confCrawlByClickIntermediateScreenshots {
	my ( $self ) = @_;

	my $enabled = $self->var([ 'crawl', 'by_click', 'intermediate_screenshots' ]);
	$enabled = DEFAULT_CRAWL_BY_CLICK_INTERMEDIATE_SCREENSHOTS if !defined $enabled;

	return $enabled;
}

# ------------------------------------------------------------------------------------------------
# Returns the configured count of successive errors which cancel the role
# (I):
# - none
# (O):
# - returns the configured count of falsy successive errors

sub confCrawlByClickSuccessiveLast {
	my ( $self ) = @_;

	my $count = $self->var([ 'crawl', 'by_click', 'successive_last' ]);
	$count = DEFAULT_CRAWL_BY_CLICK_SUCCESSIVE_LAST if !defined $count;

	return $count;
}

# ------------------------------------------------------------------------------------------------
# Returns the configured text denied patterns, defaulting to the hardcoded list
# (I):
# - none
# (O):
# - returns the configured text denied patterns

sub confCrawlByClickTextDenyPatterns {
	my ( $self ) = @_;

	my $list = $self->var([ 'crawl', 'by_click', 'text_deny_patterns' ]);
	$list = DEFAULT_CRAWL_BY_CLICK_TEXT_DENY_PATTERNS if !defined $list;

	return $list;
}

# ------------------------------------------------------------------------------------------------
# Returns the configured xpath denied patterns, defaulting to the hardcoded list
# (I):
# - none
# (O):
# - returns the configured xpath denied patterns

sub confCrawlByClickXpathDenyPatterns {
	my ( $self ) = @_;

	my $list = $self->var([ 'crawl', 'by_click', 'xpath_deny_patterns' ]);
	$list = DEFAULT_CRAWL_BY_CLICK_XPATH_DENY_PATTERNS if !defined $list;

	return $list;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the list of CSS deny patterns when crawling by link

sub confCrawlByLinkCssExcludes {
	my ( $self ) = @_;

	my $list = $self->var([ 'crawl', 'by_link', 'css_excludes' ]);
	$list = DEFAULT_CRAWL_BY_LINK_CSS_EXCLUDES if !defined $list;

	return $list;
}

# ------------------------------------------------------------------------------------------------
# Returns whether we crawl by links.
# (I):
# - none
# (O):
# - returns whether we crawl by links

sub confCrawlByLinkEnabled {
	my ( $self ) = @_;

	my $crawl = $self->var([ 'crawl', 'by_link', 'enabled' ]);
	$crawl = DEFAULT_CRAWL_BY_LINK_ENABLED if !defined $crawl;

	return $crawl;
}

# ------------------------------------------------------------------------------------------------
# Returns the list of link selectors.
# (I):
# - none
# (O):
# - returns the list of link selectors

sub confCrawlByLinkFinders {
	my ( $self ) = @_;

	my $list = $self->var([ 'crawl', 'by_link', 'finders' ]);
	$list = DEFAULT_CRAWL_BY_LINK_FINDERS if !defined $list;

	return $list;
}

# ------------------------------------------------------------------------------------------------
# Returns whether to follow and honor the query fragments.
# (I):
# - none
# (O):
# - returns whether to follow and honor the query fragments

sub confCrawlByLinkHonorQuery {
	my ( $self ) = @_;

	my $follow = $self->var([ 'crawl', 'by_link', 'honor_query' ]);
	$follow = DEFAULT_CRAWL_BY_LINK_HONOR_QUERY if !defined $follow;

	return $follow;
}

# ------------------------------------------------------------------------------------------------
# Returns the configured href allowed patterns, defaulting to all
# (I):
# - none
# (O):
# - returns the configured href allowed patterns

sub confCrawlByLinkHrefAllowPatterns {
	my ( $self ) = @_;

	my $list = $self->var([ 'crawl', 'by_link', 'href_allow_patterns' ]);
	$list = DEFAULT_CRAWL_BY_LINK_HREF_ALLOW_PATTERNS if !defined $list;

	return $list;
}

# ------------------------------------------------------------------------------------------------
# Returns the configured href denied patterns, defaulting to the hardcoded list
# (I):
# - none
# (O):
# - returns the configured href denied patterns

sub confCrawlByLinkHrefDenyPatterns {
	my ( $self ) = @_;

	my $list = $self->var([ 'crawl', 'by_link', 'href_deny_patterns' ]);
	$list = DEFAULT_CRAWL_BY_LINK_HREF_DENY_PATTERNS if !defined $list;

	return $list;
}

# ------------------------------------------------------------------------------------------------
# Returns the configured text denied patterns, defaulting to the hardcoded list
# (I):
# - none
# (O):
# - returns the configured text denied patterns

sub confCrawlByLinkTextDenyPatterns {
	my ( $self ) = @_;

	my $list = $self->var([ 'crawl', 'by_link', 'text_deny_patterns' ]);
	$list = DEFAULT_CRAWL_BY_LINK_TEXT_DENY_PATTERNS if !defined $list;

	return $list;
}

# ------------------------------------------------------------------------------------------------
# Returns the configured url allowed patterns, defaulting to all
# (I):
# - none
# (O):
# - returns the configured url allowed patterns

sub confCrawlByLinkUrlAllowPatterns {
	my ( $self ) = @_;

	my $list = $self->var([ 'crawl', 'by_link', 'url_allow_patterns' ]);
	$list = DEFAULT_CRAWL_BY_LINK_URL_ALLOW_PATTERNS if !defined $list;

	return $list;
}

# ------------------------------------------------------------------------------------------------
# Returns the configured url denied patterns, defaulting to the hardcoded list
# (I):
# - none
# (O):
# - returns the configured url denied patterns

sub confCrawlByLinkUrlDenyPatterns {
	my ( $self ) = @_;

	my $list = $self->var([ 'crawl', 'by_link', 'url_deny_patterns' ]);
	$list = DEFAULT_CRAWL_BY_LINK_URL_DENY_PATTERNS if !defined $list;

	return $list;
}

# ------------------------------------------------------------------------------------------------
# Returns the configured max count of pages to visit.
# 'visited' here means both when following a link (page count) or when clicking in an area.
# (I):
# - none
# (O):
# - returns the configured max count of pages to visit

sub confCrawlMaxVisited {
	my ( $self ) = @_;

	my $max = $self->var([ 'crawl', 'max_visited' ]);
	$max = DEFAULT_CRAWL_MAX_VISITED if !defined $max;

	return $max;
}

# ------------------------------------------------------------------------------------------------
# Returns whether we must stay inside the same host, defaulting to true.
# (I):
# - none
# (O):
# - returns whether we must stay inside the same host

sub confCrawlSameHost {
	my ( $self ) = @_;

	my $same = $self->var([ 'crawl', 'same_host' ]);
	$same = DEFAULT_CRAWL_SAME_HOST if !defined $same;

	return $same;
}

# -------------------------------------------------------------------------------------------------
# Returns the directory where HTMLs files must be kept
# (I):
# - whether we want the dirs for 'ref' or 'new' site
# (O):
# - the subdirectory of the HTMLs files for this site
#   this may be set empty by configuration, which means doesn't keep

sub confDirsHtmls {
	my ( $self, $which ) = @_;

	my $dirs = DEFAULT_DIRS_HTMLS // {};

	if( !grep( /^$which$/, keys %{$dirs} )){
		msgErr( "unexpected which='$which'" );
		TTP::stackTrace();
	}

	my $subdir = $self->var([ 'dirs', $which, 'htmls' ]) // $dirs->{$which};

	return $subdir;
}

# -------------------------------------------------------------------------------------------------
# Returns the directory where screenshots must be kept
# (I):
# - whether we want the dirs for 'ref' or 'new' site
# (O):
# - the subdirectory of the screenshots for this site
#   this may be set empty by configuration, which means doesn't keep

sub confDirsScreenshots {
	my ( $self, $which ) = @_;

	my $dirs = DEFAULT_DIRS_SCREENSHOTS // {};

	if( !grep( /^$which$/, keys %{$dirs} )){
		msgErr( "unexpected which='$which'" );
		TTP::stackTrace();
	}

	my $subdir = $self->var([ 'dirs', $which, 'screenshots' ]) // $dirs->{$which};

	return $subdir;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - a ref to a hash which contains the forms to be handled, maybe empty

sub confForms {
	my ( $self ) = @_;

	my $ref = $self->var([ 'forms' ]) // {};

	return $ref;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns whether to be verbose not accepting a new clickable

sub confVerbosityClickablesDenied {
	my ( $self ) = @_;

	my $verbose = $self->var([ 'verbosity', 'clickables', 'denied' ]) // DEFAULT_VERBOSITY_CLICKABLES_DENIED;

	return $verbose;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns whether to be verbose when enqueing a new clickable

sub confVerbosityClickablesEnqueue {
	my ( $self ) = @_;

	my $verbose = $self->var([ 'verbosity', 'clickables', 'enqueue' ]) // DEFAULT_VERBOSITY_CLICKABLES_ENQUEUE;

	return $verbose;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns whether to be verbose about received answers, defaulting to false

sub confVerbosityDaemonReceived {
	my ( $self ) = @_;

	my $verbose = $self->var([ 'verbosity', 'daemon', 'received' ]) // DEFAULT_VERBOSITY_DAEMON_RECEIVED;

	return $verbose;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns whether to be verbose when sleeping while waiting, defaulting to false

sub confVerbosityDaemonSleep {
	my ( $self ) = @_;

	my $verbose = $self->var([ 'verbosity', 'daemon', 'sleep' ]) // DEFAULT_VERBOSITY_DAEMON_SLEEP;

	return $verbose;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns whether to be verbose not accepting a new link

sub confVerbosityLinksDenied {
	my ( $self ) = @_;

	my $verbose = $self->var([ 'verbosity', 'links', 'denied' ]) // DEFAULT_VERBOSITY_LINKS_DENIED;

	return $verbose;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns whether to be verbose when enqueing a new link

sub confVerbosityLinksEnqueue {
	my ( $self ) = @_;

	my $verbose = $self->var([ 'verbosity', 'links', 'enqueue' ]) // DEFAULT_VERBOSITY_LINKS_ENQUEUE;

	return $verbose;
}

# -------------------------------------------------------------------------------------------------
# Returns the list of configured roles name, as a sorted list
# (I):
# - nothing
# (O):
# - a ref to the sorted list of roles name

sub roles {
	my ( $self ) = @_;

	my $ref = $self->var([ 'roles' ]);

	return sort keys %{$ref};
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - the browser working directory

sub runBrowserWorkdir {
	my ( $self ) = @_;

	my $dir = $self->{_run}{browser_workdir};

	return $dir;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - whether we want crawl by click

sub runCrawlByClickEnabled {
	my ( $self ) = @_;

	my $crawl = $self->{_run}{crawl_by_click};

	return $crawl;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the configured href denied patterns

sub runCrawlByClickHrefDenyPatterns {
	my ( $self ) = @_;

	my $ref = $self->{_run}{click_href_deny_rx};

	return $ref;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the configured text denied patterns

sub runCrawlByClickTextDenyPatterns {
	my ( $self ) = @_;

	my $ref = $self->{_run}{click_text_deny_rx};

	return $ref;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the configured xpath denied patterns

sub runCrawlByClickXpathDenyPatterns {
	my ( $self ) = @_;

	my $ref = $self->{_run}{click_xpath_deny_rx};

	return $ref;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - whether we want crawl by link

sub runCrawlByLinkEnabled {
	my ( $self ) = @_;

	my $crawl = $self->{_run}{crawl_by_link};

	return $crawl;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - whether all HREFs are allowed

sub runCrawlByLinkHrefAllowedAll {
	my ( $self ) = @_;

	my $bool = $self->{_run}{link_href_allow_all};

	return $bool;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - the running allowed href patterns, as a ref to an array of compiled regex

sub runCrawlByLinkHrefAllowPatterns {
	my ( $self ) = @_;

	my $ref = $self->{_run}{link_href_allow_rx};

	return $ref;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - the running denied href patterns, as a ref to an array of compiled regex

sub runCrawlByLinkHrefDenyPatterns {
	my ( $self ) = @_;

	my $ref = $self->{_run}{link_href_deny_rx};

	return $ref;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the configured text denied patterns

sub runCrawlByLinkTextDenyPatterns {
	my ( $self ) = @_;

	my $ref = $self->{_run}{link_text_deny_rx};

	return $ref;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - whether all URLs are allowed

sub runCrawlByLinkUrlAllowedAll {
	my ( $self ) = @_;

	my $bool = $self->{_run}{link_url_allow_all};

	return $bool;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - the running allowed URL patterns, as a ref to an array of compiled regex

sub runCrawlByLinkUrlAllowPatterns {
	my ( $self ) = @_;

	my $ref = $self->{_run}{link_url_allow_rx};

	return $ref;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - the running denied URL patterns, as a ref to an array of compiled regex

sub runCrawlByLinkUrlDenyPatterns {
	my ( $self ) = @_;

	my $ref = $self->{_run}{link_url_deny_rx};

	return $ref;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - the running max count of visited places

sub runCrawlMaxVisited {
	my ( $self ) = @_;

	my $max = $self->{_run}{max_visited};

	return $max;
}

# -------------------------------------------------------------------------------------------------
# Contrarily to Site or Node or Service, HTTP::Compare::Config is not overridable at all.
# All its configuration must be self-contained.
# (I):
# - either a single string or a reference to an array of keys to be read from (e.g. [ 'moveDir', 'byOS', 'MSWin32' ])
#   each key can be itself an array ref of potential candidates for this level
# (O):
# - the evaluated value of this variable, which may be undef

sub var {
	my ( $self, $keys ) = @_;
	msgDebug( __PACKAGE__."::var() keys=".( ref( $keys ) eq 'ARRAY' ? ( "[ ".join( ', ', @{$keys} )." ]" ) : "'$keys'" ));

	my $value = $self->TTP::IJSONable::var( $keys );

	return $value;
}

### Class methods

# -------------------------------------------------------------------------------------------------
# Constructor
# (I):
# - the TTP::EP entry point
# - the path to the JSON configuration file
# - an optional options hash with following keys:
#   > max_visited: the maximum count of places to visit specified in the command-line, defaulting to the configured one
#   > by_click: whether crawling by click, from the command-line, defaulting to the configured one
#   > by_link: whether crawling by link, from the command-line, defaulting to the configured one
# (O):
# - this object

sub new {
	my ( $class, $ep, $path, $args ) = @_;
	$class = ref( $class ) || $class;
	$args //= {};

	my $self = $class->SUPER::new( $ep, $args );
	bless $self, $class;
	msgDebug( __PACKAGE__."::new() jsonPath='$path'" );

	$self->{_run} = {};

	# the path must be specified
	# IJSONable role takes care of validating the acceptability and the enable-ity
	if( $path ){
		$self->_loadConfig( $path, $args );
		if( $self->jsonLoaded()){
			$self->_compile_regex_patterns();
		}
	} else {
		msgErr( __PACKAGE__."::new() expects a 'path' argument, not found" );
		TTP::stackTrace();
	}

	return $self;
}

# -------------------------------------------------------------------------------------------------
# Constructor
# (I):
# - the TTP::EP entry point
# - a serialized snapshot
# - an optional options hash
# (O):
# - this object

sub new_by_snapshot {
	my ( $class, $ep, $snap, $args ) = @_;
	$class = ref( $class ) || $class;
	$args //= {};

	if( !$ep || !blessed( $ep ) || !$ep->isa( 'TTP::EP' )){
		msgErr( "unexpected ep: ".TTP::chompDumper( $ep ));
		TTP::stackTrace();
	}

	my $self = $class->SUPER::new( $ep, $args );
	bless $self, $class;
	msgDebug( __PACKAGE__."::new_by_snapshot()" );

	my $decoder = Sereal::Decoder->new();
	$decoder->decode( $snap, $self );

	return $self;
}

### Global functions
### Note for the developer: while a global function doesn't take any argument, it can be called both
### as a class method 'TTP::Package->method()' or as a global function 'TTP::Package::method()',
### the former being preferred (hence the writing inside of the 'Class methods' block which brings
### the class as first argument).

1;
