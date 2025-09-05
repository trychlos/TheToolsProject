# @(#) deep compare between two HTTP/HTTPS endpoints
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --json=<filename>       the JSON configuration file [${jsonfile}]
# @(-) --[no]debug             whether the Selenium::Remote::Driver must be run in debug mode [${debug}]
# @(-) --maxpages=<count>      maximum count of pages to be visited [${maxpages}]
#
# @(@) Note 1: This verb requires a nginx server which proxyies to a chromedriver server, both running locally.
#
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

use strict;
use utf8;
use warnings;

use Digest::MD5 qw( md5_hex );
use Encode qw( encode_utf8 );
use File::Path qw( make_path );
use File::Temp qw( tempdir );
use HTTP::Tiny;
use Image::Magick;
use JSON;
use List::Util qw( any );
use LWP::UserAgent;
use MIME::Base64 qw( decode_base64 );
use Mojo::DOM;
use Selenium::Chrome;
use Selenium::Remote::Driver;
use Test::More;
use Time::HiRes qw( time usleep );
use Unicode::Normalize qw( NFC );
use URI;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	debug => 'no',
	jsonfile => '',
	maxpages => 10
};

my $opt_debug = false;
my $opt_jsonfile = $defaults->{jsonfile};
my $opt_maxpages = $defaults->{maxpages};

# the JSON compare configuration as a hash ref
my $conf = undef;
# a global hashref which handles the results of the compare
my $hashref = {};
# whether we have set options
my $opt_maxpages_set = false;

# some constants
my $Const = {
	caps => {
		path => '',
		capabilities => {
			firstMatch => [{}],
			alwaysMatch => {
				browserName => 'chrome',
      			platformName => 'linux',
      			acceptInsecureCerts => JSON::true,
				'goog:chromeOptions' => {
					binary => '/usr/lib64/chromium-browser/chromium-browser',
					args => [
						'--headless=new',
						'--no-sandbox',
						'--disable-gpu',
						'--disable-dev-shm-usage'
					]
				},
				'goog:loggingPrefs' => { performance => 'ALL' },
				unhandledPromptBehavior => 'accept and notify'
			}
		}
	},
	# accepted crawl modes
	crawl_modes => {
		'click' => \&doCrawlByClicks,
		'link' => \&doCrawlByLinks
	},
	excluded_cookies => [
		"AspNetCore.Antiforgery"
	],
	# constant prefix used by ChromeDriver for all its paths
	path => '/wd/hub',
	# the timeout (sec) of interactions with internal browser
	timeout_s => 5
};

# -------------------------------------------------------------------------------------------------
# Decode the JSON message safely

sub _cdp_msg {
    my ($e) = @_;
    my $m = eval { decode_json($e->{message}||'{}') } || return;
    return $m->{message} || {};
}

# -------------------------------------------------------------------------------------------------

sub _http {
	return  HTTP::Tiny->new( timeout => $hashref->{run}{timeout_s} );
}

# -------------------------------------------------------------------------------------------------

sub _wd {
	return "http://$hashref->{run}{server}:$conf->{browser}{port}$Const->{path}/session/$_[0]";	# $_[0] = $sid
}

# -------------------------------------------------------------------------------------------------
# try to see if an alert has been raised by the website
# returns undef or the text of the alert

sub alert_text_w3c {
    my ( $sid ) = @_;
    my $r = _http()->get( _wd( $sid ).'/alert/text' );
    return undef unless $r->{success};

    my $v = eval { decode_json( $r->{content} ) } or return undef;

    # handle both success and "unexpected alert open" error format
    if( exists $v->{value}{data}{text} ){
        return $v->{value}{data}{text};
    } elsif( exists $v->{value}{message} ){
        # fallback: try to parse from message
        if( $v->{value}{message} =~ /Alert text : (.+)\}/ ){
            return $1;
        }
    } elsif( exists $v->{value} ){
        return $v->{value};  # older style response
    }

    return undef;
}

# -------------------------------------------------------------------------------------------------

sub alert_accept_w3c {
    my ( $sid ) = @_;
    _http()->post( _wd( $sid ).'/alert/accept', { headers=>{ 'Content-Type' => 'application/json' }, content=>'{}' });
}

# -------------------------------------------------------------------------------------------------

sub alert_dismiss_w3c {
    my ( $sid ) = @_;
    _http()->post( _wd( $sid ).'/alert/dismiss', { headers=>{ 'Content-Type' => 'application/json' }, content=>'{}' });
}

# -------------------------------------------------------------------------------------------------
# instanciate a browser driver
# because the Perl driver cannot initiate the session, we do that through HTTP::Tiny

sub browser_driver {
	my ( $url ) = @_;
	my $res = _http()->post( "http://$hashref->{run}{server}:$conf->{browser}{port}$Const->{path}/session", {
		headers => { 'Content-Type' => 'application/json' },
		content => encode_json( $Const->{caps} ),
	});
	die "session create failed: $res->{status} $res->{reason}\n$res->{content}\n" unless $res->{success};

	my $payload = decode_json( $res->{content} );
	my $session_id = $payload->{sessionId} // $payload->{value}{sessionId} or die "no sessionId in response";
	msgVerbose( "got driver sessionId='$session_id' for $url" );
  
	my $driver = Selenium::Remote::Driver->new(
		session_id => $session_id,
		remote_server_addr => $hashref->{run}{server},
		port => $conf->{browser}{port},
		path => $Const->{path},
		is_w3c => true,
		debug => $opt_debug
	);
	#print STDERR "driver ".Dumper( $driver );
	return $driver;
}

# -------------------------------------------------------------------------------------------------
# Click by scanId, then wait + capture. Returns [ $cap, $alerts, $navigated ]

sub click_and_capture {
    my ($role, $which, $scan_id, $label, $url_base, $basename, $action) = @_;  # $which = 'ref'|'new'
    my $drv = $hashref->{byRole}{$role}{drivers}{$which};
    my $sid = $drv->{session_id};
	msgVerbose( "click_and_capture() $url_base, $scan_id" );

    # before state
    my $before_url = $drv->get_current_url;

	perf_logs_drain( $drv );
	my $ok = click_by_scan_id( $sid, $scan_id );
	#print STDERR "click_and_capture() ok=$ok".EOL;
    return [undef, [], 0] unless $ok;

    # Let SPA settle
    #my ( $ready, $alerts, $logs ) = wait_for_page_ready( $drv, 5 );
    # Even if not fully "ready", try to capture something
    my $cap = wait_and_capture( $role, $which, $basename );
	#print STDERR "click_and_capture() capture ".Dumper( $cap );

    my $after_url = $drv->get_current_url;
	# navigated is true when the URL has changed
    my $navigated = ($after_url||'') ne ($before_url||'') ? 1 : 0;

	#print STDERR "click_and_capture() returns $cap, $alerts, $navigated".EOL;
    return [$cap, [], $navigated];
}

# -------------------------------------------------------------------------------------------------
# JS: find element by data-scan-id across top + same-origin iframe docs; click it.

sub click_by_scan_id {
    my ( $sid, $scan_id ) = @_;
	msgVerbose( "clicking on $scan_id..." );
	my $js = q{
  		return ( function( scanId ){
    		function allDocs( rootDoc ){
      			const out = [ rootDoc ];
      			( function walk( doc ){
        			const frames = doc.querySelectorAll( 'iframe,frame' );
        			for( const f of frames ){
          				try {
            				const cd = f.contentDocument;
            				if( !cd ) continue;
            				out.push( cd );
            				walk( cd );
          				} catch( e ){
							/* cross-origin -> skip */
						}
        			}
      			})( rootDoc );
      			return out;
    		}
    		const docs = allDocs( document );
    		for( const d of docs ){
      			const el = d.querySelector( '[data-scan-id="'+scanId+'"]' );
      			if( el ){
        			el.scrollIntoView({ block:'center', inline:'center' });
        			el.click();
        			return true;
      			}
    		}
    		return false;
  		})( arguments[0] );
	};
    return exec_js_w3c_sync( $sid, $js, [ $scan_id ] );
}

# -------------------------------------------------------------------------------------------------
# Click a tab (by our temporary scan id)

sub click_tab {
    my ($sid, $tab_id) = @_;
    my $js = q{
        (function(id){
          const el = document.querySelector('[data-tab-scan-id="'+id+'"]') ||
                     document.querySelector('[data-tabscan-id="'+id+'"]') ||
                     document.querySelector('[data-tab-scan-id="'+CSS.escape(id)+'"]') ||
                     document.querySelector('[data-tabscan-id="'+CSS.escape(id)+'"]');
          if (!el) return false;
          el.scrollIntoView({block:'center', inline:'center'});
          el.click();
          return true;
        })(arguments[0]);
    };
    return exec_js_w3c_sync( $sid, $js, [$tab_id] );
}

# -------------------------------------------------------------------------------------------------
# JS: walk top document + same-origin iframes, tag clickables with data-scan-id,
#     and return metadata: id, text, href (may be javascript:...), kind, docKey, frameSrc

sub clickable_discover_targets {
    my ( $sid ) = @_;
	my $js = q{
  		return( function(){
    		function sameOriginFrameDocs( rootDoc ){
      			const out = [{doc: rootDoc, frameSrc: null, docKey: 'top'}];
      			function walk( doc, prefix ){
        			const frames = doc.querySelectorAll( 'iframe,frame' );
        			let idx = 0;
        			for( const f of frames ){
          				idx++;
          				try {
            				const cd = f.contentDocument;
            				if( !cd ) continue; // not loaded or cross-origin
            				const src = f.getAttribute('src') || '';
            				const key = (prefix? prefix+'>' : '') + 'iframe['+idx+']:' + src;
            				out.push({ doc: cd, frameSrc: src, docKey: key });
            				walk( cd, key );
          				} catch(e){
							/* cross-origin -> skip */
						}
        			}
      			}
      			walk( rootDoc, '' );
      			return out;
    		}

    		function visible( el ){
      			const cs = el.ownerDocument.defaultView.getComputedStyle( el );
      			if( !cs ) return false;
      			if( cs.display === 'none' || cs.visibility === 'hidden' || +cs.opacity === 0 ) return false;
      			const rect = el.getBoundingClientRect();
      			return ( rect.width > 0 && rect.height > 0 );
    		}

    		const docs = sameOriginFrameDocs( document );
			// make sure the sane scan-id is not reused by having a global counter
			// because the initial compare is dumped to n°1, start here with 2 so that the 'visited' counter is aligned of the scan id's
			window.__scanCounter = window.__scanCounter || 2;
    		const out = [];

    		for( const ctx of docs ){
      			const d = ctx.doc;
      			const list = new Set();
      			d.querySelectorAll( 'a[href], [role="link"], [data-link], [data-router-link], button, [onclick]' ).forEach( n => list.add( n ));

      			for( const el of list ){
        			if( !visible( el )) continue;
        			if( el.hasAttribute( 'disabled' ) || el.getAttribute( 'aria-disabled' ) === 'true' ) continue;

        			let href = el.getAttribute( 'href' ) || '';
        			if( !href && el.closest( 'a[href]' )) href = el.closest( 'a[href]' ).getAttribute( 'href' ) || '';

        			const text = ( el.innerText || el.textContent || '' ).trim().replace( /\s+/g,' ' ).slice( 0,160 );
        			const tag = el.tagName.toLowerCase();
        			const kind =
          				tag === 'a' ? 'a' :
          				tag === 'button' ? 'button' :
          				el.hasAttribute('onclick') ? 'onclick' :
          				el.getAttribute('role') === 'link' ? 'role-link' :
          				'other';
					const onclick = el.getAttribute('onclick') || '';
					const onclickEff = onclick || (/^\s*javascript:/i.test(href) ? href.replace(/^\s*javascript:\s*/i,'') : '');

        			if( !el.dataset.scanId ){
						const frameHint = (ctx.docKey || 'top').slice(0,40).replace( /[^\w\-:]/g, '_' );
						const id = `scan-${frameHint}-${window.__scanCounter++}`;
						el.dataset.scanId = id;
					}

        			out.push({
          				id: el.dataset.scanId,
          				text,
						href,
						kind,
          				docKey: ctx.docKey,
          				frameSrc: ctx.frameSrc || '',
						onclick: onclickEff
        			});
      			}
			}
    		return out;
  		})();
	};
    my $list = exec_js_w3c_sync( $sid, $js, [] );
    return $list // [];
}

# -------------------------------------------------------------------------------------------------
# action = { kind, text, href, onclick }  -- all optional except kind

sub clickable_find_equivalent {
	my ( $driver, $action ) = @_;
	my $diag_js = q{
		return (function(){
			function canon(s){ return (s||'').replace(/\u00A0/g,' ').replace(/\s+/g,' ').trim(); }
			function canReadFrame(f) {
			try { return !!f.contentDocument; } catch(e){ return false; }
			}
			const out = {
			top: {
				href: location.href,
				readyState: document.readyState,
				body: !!document.body,
				aCount: document.querySelectorAll('a').length,
				sample: Array.from(document.querySelectorAll('a')).slice(0,5).map(a=>({
				text: canon(a.innerText||a.textContent||'').slice(0,80),
				href: a.getAttribute('href')||''
				})),
			},
			iframes: []
			};
			const frs = Array.from(document.querySelectorAll('iframe,frame'));
			frs.forEach((f,i)=>{
			const src = f.getAttribute('src')||'';
			const sandbox = f.getAttribute('sandbox')||'';
			const readable = canReadFrame(f);
			const entry = { index:i, src, sandbox, readable, aCount:null, sample:[] };
			if (readable) {
				try{
				const d = f.contentDocument;
				const as = Array.from(d.querySelectorAll('a'));
				entry.aCount = as.length;
				entry.sample = as.slice(0,5).map(a=>({
					text: canon(a.innerText||a.textContent||'').slice(0,80),
					href: a.getAttribute('href')||''
				}));
				} catch(e){ entry.readable = false; }
			}
			out.iframes.push(entry);
			});
			return out;
		})();
	};
	my $js = q{
  		return ( function( meta ){
    		function canonText( s ){
      			if( !s ) return '';
      			return s
        			.replace(/&nbsp;/g, ' ')
        			.replace(/\u00A0/g, ' ')
        			.replace(/\s+/g, ' ')
        			.trim();
    		}

    		function lcCanon( s ){
				return canonText( s ).toLowerCase();
			}

		    function pathOnly( u ){
      			try {
        			const uu = new URL( u, document.location.href );
        			return uu.pathname + ( uu.search || '' );
      			} catch( e ){
					return '';
				}
    		}

    		function parseJsSig( a ){
      			// Try onclick attribute or javascript:href; return "name(arg1,arg2,...)"
      			let txt = a.getAttribute( 'onclick' ) || '';
      			if( !txt ){
        			const h = a.getAttribute( 'href' ) || '';
        			if( /^\s*javascript:/i.test( h )) txt = h.replace( /^\s*javascript:\s*/i, '' );
      			}
      			if( !txt ) return null;
      			// normalize spaces
      			txt = txt.replace( /\s+/g, ' ' );
      			// shrink "parent.ObjectClick(...)" -> "ObjectClick(arg,arg,...)"
      			const m = txt.match( /([A-Za-z_$][\w$\.]*)\s*\(([^)]*)\)/ );
      			if( !m ) return null;
      			const name = m[1].split( '.' ).pop();     // drop parent./window.
      			const args = m[2].split( ',' ).map( s=>s.trim()).join( ',' );
      			return name + '(' + args + ')';
    		}

    		function ensureScanId( el ){
      			if( !el.dataset.scanId ) el.dataset.scanId = 'scan-' + Math.floor( Math.random()*1e9 );
      			return el.dataset.scanId;
    		}

    		function jaccardTokens( a, b ){
      			const A = new Set( lcCanon( a ).split( /\s+/ ).filter( Boolean ));
      			const B = new Set( lcCanon( b ).split( /\s+/ ).filter( Boolean ));
      			if( !A.size && !B.size ) return 1;
      			let inter=0;
				for( const t of A ){
					if( B.has( t )) inter++;
				}
      			return inter / ( A.size + B.size - inter || 1 );
    		}

    		const wantKind = ( meta.kind || 'a,button,[role="link"]' ).trim();
    		const wantText = canonText(meta.text||'');
    		const wantTextLC = lcCanon(wantText);
    		const wantPrefix = wantText.slice(0,40);
    		const wantHrefPath = pathOnly(meta.href||'');
    		const wantSig = (meta.onclick ? meta.onclick : null);

    		const nodes = Array.from( document.querySelectorAll( wantKind ));
			/*
    		const nodes = Array.from( document.querySelectorAll( 'a' ));
			return nodes.map( el => ({
				text: (el.innerText || "").trim().slice(0,80),
				href: el.getAttribute("href") || "",
				hasScanId: !!el.dataset.scanId
			}));
			*/

			// Pass 1: exact text
			for (const el of nodes){
			const t = canonText(el.innerText || el.textContent || '');
			if (t === wantText) return ensureScanId(el);
			}

			// Pass 2: case-insensitive text
			for (const el of nodes){
			const t = lcCanon(el.innerText || el.textContent || '');
			if (t === wantTextLC) return ensureScanId(el);
			}

			// Pass 3: prefix contains
			if (wantPrefix){
			for (const el of nodes){
				const t = canonText(el.innerText || el.textContent || '');
				if (t.indexOf(wantPrefix) >= 0) return ensureScanId(el);
			}
			}

			// Pass 4: href path equality
			if (wantHrefPath){
			for (const el of nodes){
				const h = el.getAttribute && el.getAttribute('href');
				if (!h) continue;
				if (pathOnly(h) === wantHrefPath) return ensureScanId(el);
			}
			}

			// Pass 5: onclick/javascript signature equality
			if (wantSig){
			for (const el of nodes){
				const sig = parseJsSig(el);
				if (sig && sig === wantSig) return ensureScanId(el);
			}
			} else {
			// If ref had no onclick saved, but this candidate does and matches text closely, accept
			for (const el of nodes){
				const sig = parseJsSig(el);
				if (!sig) continue;
				const score = jaccardTokens(el.innerText||el.textContent||'', wantText);
				if (score >= 0.9) return ensureScanId(el);
			}
			}

			// Pass 6: fuzzy text score, pick best over threshold
			let best = {score: 0, el: null};
			for (const el of nodes){
			const t = el.innerText || el.textContent || '';
			const s = jaccardTokens(t, wantText);
			if (s > best.score) best = { score: s, el };
			}
			if (best.el && best.score >= 0.8) return ensureScanId(best.el);

			return null;
		})( arguments[0] );
	};
	my $res = exec_js_w3c_sync( $driver->{session_id}, $js, [ $action ] );
	#print STDERR "clickable_find_equivalent() res ".Dumper( $res );
}

# -------------------------------------------------------------------------------------------------
# Compare the two captured data
# opts:
# - diff: the diff filename 

sub compare_captured {
	my ( $role, $capture_ref, $capture_new, $opts ) = @_;
	msgVerbose( "compare_captured() role'$role' entering" );
	$opts //= {};

	my $path = url_path( $hashref->{byRole}{$role}{drivers}{ref} );
	my @errs = ();
	is( lc( $capture_ref->{content_type} // ''), lc( $capture_new->{content_type} // ''), "[$role ($path)] got same content-type (".lc( $capture_ref->{content_type} // '').")" )
		|| push( @errs, "content-type" );
	is( $capture_ref->{dom_hash}, $capture_new->{dom_hash}, "[$role ($path)] sanitized DOM hashes matches ($capture_ref->{dom_hash})" )
		|| push( @errs, "DOM hashes" );
	ok( !scalar( @{$capture_ref->{alerts}} ), "[$role ($path)] no ref alerts" )
		|| push( @errs, "ref alerts: ".join( ' | ', @{$capture_ref->{alerts}} ));
	ok( !scalar( @{$capture_new->{alerts}} ), "[$role ($path)] no new alerts" )
		|| push( @errs, "new alerts: ".join( ' | ', @{$capture_new->{alerts}} ));

	# optional visual diff
	# Which align should you use?
	# 	crop (default): safest with your stitched full-page shots (they should be same width and very close in height; compares the overlapping area only).
	#	pad: if one page is slightly taller (e.g., a banner present on one env), pad the shorter one with white for a full-height comparison.
	#	resize: if widths differ due to different breakpoints (less common in your setup). It scales both to a common width first, then compares.
	if( $conf->{visual}{enabled} && $conf->{crawl}{write_screenshots} && $opts->{diff} ){
		my $threshold = $conf->{visual}{rmse_fail_threshold} || 0.01;
		my $res = screenshots_compare_rmse(
			a         => $capture_ref->{shotdump},
			b         => $capture_new->{shotdump},
			diff_out  => $opts->{diff},
			align     => 'crop',      # or 'pad' / 'resize'
			fuzz      => '5%',
			threshold => $threshold,
			# resize_width => 1366,   # only if align => 'resize'
		);
		my $rmse = $res->{rmse};
		ok( $rmse <= $threshold, "[$role ($path)] visual RMSE=$rmse" )
			|| push( @errs, "RMSE=$rmse" );
	}

	# record sitemap entry
	record_sitemap_entry( $role, {
		path          => $path,
		capture_ref   => $capture_ref,
		capture_new   => $capture_new,
		errs          => \@errs,
		full          => true
	});
}

# -------------------------------------------------------------------------------------------------
# Call this right after you load YAML/JSON into $cfg

sub config_compile_patterns {
    my ( $cfg ) = @_;
    my $c = $cfg->{crawl} ||= {};

    my $allow_raw = $c->{url_allow_patterns};  # may be undef
    my $deny_raw  = $c->{url_deny_patterns};   # may be undef

    my @allow_rx;
    for my $s (@{ $allow_raw // [] }) {
        next unless defined $s && length $s;
        my $rx = eval { qr/$s/ };
        if ($@) {
            msgWarn( "Invalid allow regex '$s': $@ (skipping)" );
            next;
        }
        push @allow_rx, $rx;
    }

    my @deny_rx;
    for my $s (@{ $deny_raw // [] }) {
        next unless defined $s && length $s;
        my $rx = eval { qr/$s/ };
        if ($@) {
            msgWarn( "Invalid deny regex '$s': $@ (skipping)" );
            next;
        }
        push @deny_rx, $rx;
    }

    # Stash precompiled regexes + a flag so checks are cheap during crawl
    $c->{_allow_rx}   = \@allow_rx;     # empty => allow all (unless denied)
    $c->{_deny_rx}    = \@deny_rx;      # empty => deny none
    $c->{_allow_all}  = (@allow_rx == 0) ? 1 : 0;

    return $cfg;
}

# -------------------------------------------------------------------------------------------------
# load the JSON configuration file
# check main data

sub config_load {
	my ( $fname ) = @_;
	$conf = TTP::jsonRead( $fname );
	my $nberrs = 0;
	#print Dumper( $conf );
	# must have ref and new URLs
	if( $conf && !$conf->{bases}{ref} ){
		msgErr( "$fname: bases.ref URL not specified" );
		$nberrs += 1;
	}
	if( $conf && !$conf->{bases}{new} ){
		msgErr( "$fname: bases.new URL not specified" );
		$nberrs += 1;
	}
	# must have the port number the chromedriver is listening to
	if( !$conf->{browser}{port} ){
		msgErr( "$fname: browser.port not specified" );
		$nberrs += 1;
	}
	# check crawl mode
	my $mode = $conf->{crawl}{mode} || 'link';
	if( !exists( $Const->{crawl_modes}{$mode} )){
		msgErr( "crawl.mode='$mode' is not known" );
		$nberrs += 1;
	} else {
		msgVerbose( "accepting crawl mode='$mode'" );
		$hashref->{run} //= {};
		$hashref->{run}{crawl_mode} = $mode;
	}
	# check brower timeout
	$hashref->{run} //= {};
	$hashref->{run}{timeout_s} = $conf->{browser}{timeout} || $Const->{timeout_s};
	if( $nberrs ){
		# return undef if an error has occured
		$conf = undef;
	} else {
		# update the browser setup
		my $width = $conf->{browser}{width} || 1366;
		my $height = $conf->{browser}{height} || 768;
		push( @{$Const->{caps}{capabilities}{alwaysMatch}{'goog:chromeOptions'}{args}}, "--window-size=$width,$height" );
	}
	return $conf;
}

# -------------------------------------------------------------------------------------------------

sub current_iframe_src {
    my ($sid, $selector) = @_;
    my $js = q{
      (function(sel){
        var f = document.querySelector(sel);
        if (!f) return null;
        return f.getAttribute('src') || null;
      })(arguments[0]);
    };
    return exec_js_w3c_sync( $sid, $js, [ $selector ] );
}

# -------------------------------------------------------------------------------------------------
# Build a lightweight state key for de-duping clicks.
# We prefer response_url or final_url; fall back to a trimmed DOM signature.

sub current_state_key {
    my ($driver) = @_;
    my $top = $driver->get_current_url || '';
    my $sid = $driver->{session_id};
    my $srcs = exec_js_w3c_sync( $sid, js_iframe_srcs(), [] );
    my @s = sort grep { defined $_ } @{ $srcs // [] };
    return join('|', "top:$top", map { "if:$_" } @s);
}

# -------------------------------------------------------------------------------------------------
# Compare two websites

sub doCompare {
	msgOut( "comparing '$conf->{bases}{new}' against ref '$conf->{bases}{ref}' URLs..." );
	$hashref->{byRole} //= {};
	$hashref->{run} //= {};
	$hashref->{run}{rolesroot} = tempdir()."/byRole";
	$hashref->{run}{max_depth} = $conf->{crawl}{max_depth} || 1;
	$hashref->{run}{max_pages} = $conf->{crawl}{max_pages} || 10;
	$hashref->{run}{same_host} = defined( $conf->{crawl}{same_host_only} ) ? $conf->{crawl}{same_host_only} : true;
	$hashref->{run}{server} = $conf->{browser}{remote_server_addr} || '127.0.0.1';
	# the command-line argument (if any) overrides the configured value
	$hashref->{run}{max_pages} = $opt_maxpages if $opt_maxpages_set;
	# iter on roles
	foreach my $role ( sort keys %{$conf->{roles}} ){
		doCompareByRole( $role );
	}
	done_testing();
	print_results_summary();
}

# -------------------------------------------------------------------------------------------------
# Compare two websites for the given role

sub doCompareByRole {
	my ( $role ) = @_;
	my $enabled = defined( $conf->{roles}{$role}{enabled} ) ? $conf->{roles}{$role}{enabled} : true;
	if( !$enabled ){
		msgVerbose( "role '$role' is disabled by configuration, skipping" );
	} else {
		my $user = $conf->{roles}{$role}{creds}{user};
		my $pass = $conf->{roles}{$role}{creds}{pass};
		if( !$user || !$pass ){
			msgErr( "username and/or password credentials are not provided for '$role' role, skipping" );
		} else {
			msgOut( "comparing for role '$role' (login:'$user')..." );
			$hashref->{byRole}{$role} = {
				drivers => {
					ref => browser_driver( $conf->{bases}{ref} ),
					new => browser_driver( $conf->{bases}{new} )
				}
			};
			# if we don't have got both driver, then cancel
			if( !$hashref->{byRole}{$role}{drivers}{ref} || !$hashref->{byRole}{$role}{drivers}{new} ){
				msgWarn( "unable to get both Web drivers, cancelling" );
			} else {
				$hashref->{byRole}{$role}{logins} = {
					ref => login_to( $conf->{bases}{ref}, $hashref->{byRole}{$role}{drivers}{ref}, $role, $user, $pass ),
					new => login_to( $conf->{bases}{new}, $hashref->{byRole}{$role}{drivers}{new}, $role, $user, $pass )
				};
				if( !$hashref->{byRole}{$role}{logins}{ref} || !$hashref->{byRole}{$role}{logins}{new} ){
					msgWarn( "unable to login, cancelling" );
				} else {
					# prepare the result for this role
					$hashref->{byRole}{$role}{routes} = {};
					$hashref->{byRole}{$role}{roledir} = "$hashref->{run}{rolesroot}/$role";
					$hashref->{byRole}{$role}{seen} = {};
					$hashref->{byRole}{$role}{visited} = 0;
					$hashref->{byRole}{$role}{sitemap} = [];
					$hashref->{byRole}{$role}{status} = {};
					$hashref->{byRole}{$role}{errors} = [];
					#make sure the role has its output dirs
					make_path( "$hashref->{byRole}{$role}{roledir}/htmls" );
					make_path( "$hashref->{byRole}{$role}{roledir}/screenshots" );
					make_path( "$hashref->{byRole}{$role}{roledir}/results" );
					# initialize the queue with the configured routes
					$hashref->{byRole}{$role}{queue} = $conf->{roles}{$role}{routes} || [ '/' ];

					# and crawl until the queue is empty
					#print STDERR "queue ".Dumper( $hashref->{byRole}{$role}{queue} );
					while ( @{$hashref->{byRole}{$role}{queue}} ){
						$Const->{crawl_modes}{$hashref->{run}{crawl_mode}}( $role );
						last if $hashref->{byRole}{$role}{visited} >= $hashref->{run}{max_pages};
					}

					# write sitemap JSON (and CSV if asked)
					my $json_path = "$hashref->{byRole}{$role}{roledir}/results/sitemap.json";
					open my $J, '>:utf8', $json_path or die "open $json_path: $!";
					print {$J} encode_json( $hashref->{byRole}{$role}{sitemap} );
					close $J;

					if( $conf->{crawl}{make_sitemap_csv} ){
						my $csv_path = "$hashref->{byRole}{$role}{roledir}/results/sitemap.csv";
						open my $C, '>:utf8', $csv_path or die "open $csv_path: $!";
						print {$C} join(',', qw( path depth status_ref status_new type_ref type_new links_found shot_ref shot_new )), "\n";
						for my $row ( @{$hashref->{byRole}{$role}{sitemap}} ){
							print {$C} join(',', map { make_csv($_) } @{$row}{qw( path depth status_ref status_new type_ref type_new links_found shot_ref shot_new )}), "\n";
						}
						close $C;
					}

					# write status JSON
					$json_path = "$hashref->{byRole}{$role}{roledir}/results/per_status.json";
					open $J, '>:utf8', $json_path or die "open $json_path: $!";
					print {$J} encode_json( $hashref->{byRole}{$role}{status} );
					close $J;

					# write errors JSON
					$json_path = "$hashref->{byRole}{$role}{roledir}/results/errors.json";
					open $J, '>:utf8', $json_path or die "open $json_path: $!";
					print {$J} encode_json( $hashref->{byRole}{$role}{errors} );
					close $J;
				}
			}
		}
	}
}

# -------------------------------------------------------------------------------------------------

sub doCrawlByClicks {
    my ( $role ) = @_;
	msgVerbose( "doCrawlByClicks() role'$role' entering" );

	# Start route (first from queue or '/')
    my $path = shift @{$hashref->{byRole}{$role}{queue}} // '/';
    my $url_ref = $conf->{bases}{ref} . $path;
    my $url_new = $conf->{bases}{new} . $path;

    # Navigate both drivers to start
    my $drv_ref = $hashref->{byRole}{$role}{drivers}{ref};
    my $drv_new = $hashref->{byRole}{$role}{drivers}{new};

    # Initial capture (pairs) so we have a baseline state key
	my $basename = $path;
	$basename =~ s![/\.]!_!g;

	my $capture_ref = navigate_and_capture( $role, 'ref', $basename, url => $url_ref, label => 'initial' );
	my $capture_new = navigate_and_capture( $role, 'new', $basename, url => $url_new, label => 'initial' );

	is( $capture_new->{status}, 200, "[$role ($path)] new website returns '200' status code" );
	is( $capture_new->{status}, $capture_ref->{status}, "[$role ($path)] got same status code ($capture_new->{status})" );

	# if we get the same error both on ref and new, then just cancel this one path, and go to next
	if( $capture_ref->{status} >= 400 && $capture_ref->{status} == $capture_new->{status} ){
		msgVerbose( "same error code, so just cancel this path" );
		record_sitemap_entry( $role, {
			path          => $path,
			capture_ref   => $capture_ref,
			capture_new   => $capture_new
		});
		# increment the visited count (before, maybe, going to next path)
		#  but anyway just after having actually visited the page!
		$hashref->{byRole}{$role}{visited} += 1;
		return;
	}

	my $shot_diff = sprintf "%s/diff_%s_%06d.png", "$hashref->{byRole}{$role}{roledir}/screenshots", $basename, $hashref->{byRole}{$role}{visited}+1;
	compare_captured( $role, $capture_ref, $capture_new, { diff => $shot_diff });

    my $state_key_ref = current_state_key( $drv_ref );
    my $state_key_new = current_state_key( $drv_new );

    # Queue of click actions (scanId + label + origin state key)
    my @todo;

	my $seed = clickable_discover_targets( $drv_ref->{session_id} );
	#print STDERR "seed ".Dumper( $seed );
    for my $a ( @{$seed} ) {
		# each it from clickable_discover_targets() has { href, text, frameSrc, id, docKey, kind }
		$a->{origin} = $state_key_ref;
		push( @todo, $a );
    }
	msgVerbose( "got ".scalar( @todo )." todo items in ref" );

    # De-dup we’ve tried (state_key + scanId)
    my %tried;

    # Crawl loop
    my $depth_guard = 0;  # optional extra guard

    while( @todo && $hashref->{byRole}{$role}{visited} < $hashref->{run}{max_pages} ){
        my $act = shift @todo;
        my $key = join( '|', $act->{origin}||'', $act->{id}||'' );
        next if $tried{$key}++;
		print STDERR "doCrawlByClicks() key='$key' action ".Dumper( $act );

        # Ensure we’re still on the origin state (if not, try to goBack)
		# not sure if this is really relevant
		my $cur_ref = current_state_key( $drv_ref );
		if( $cur_ref ne ( $act->{origin} || '' )){
			if( false ){
				msgVerbose( "got current key='$cur_ref' while origin was $act->{origin}, trying to go back" );
				# Try to restore origin by back()
				eval {
					exec_js_w3c_sync( $drv_ref->{session_id}, 'history.back(); return true;', [] );
				};
				wait_for_page_ready( $drv_ref, 5 );
				$cur_ref = current_state_key( $drv_ref );
				# if still different skip
				if( $cur_ref ne ($act->{origin}||'' )){
					msgVerbose( "giving up with the action as we have quit the original URL (and history.back() cannot restore it)" );
					next;
				} else {
					msgVerbose( "current key has been back'ed to origin" );
				}
			} else {
				msgVerbose( "got current key='$cur_ref' while origin was $act->{origin}, ignoring" );
			}
		} else {
			msgVerbose( "current ref key '$cur_ref' equal origin: fine" );
		}

        # Mirror on NEW: best-effort—just ensure it’s at the analogous start URL
        # (For strict symmetry you could map by text again, but keeping it simple first.)
        my $cur_new = current_state_key( $drv_new );
        if( $cur_new ne $state_key_new ){
			msgVerbose( "current new key has to be re-got" );
            $drv_new->get($url_new);
            wait_for_page_ready( $drv_new, 5 );
        }

        # Click on REF + capture
        my $prefix = $act->{text}; $prefix =~ s/\W+/_/g;
		$prefix = substr($prefix,0,40) || 'click';
        my ($capR,$alertsR,$navR) = @{ click_and_capture( $role, 'ref', $act->{id}, $act->{text}, $url_ref, $prefix, $act ) };
		#print STDERR "capR ".Dumper( $capR );
		#print STDERR "alertsR ".Dumper( $alertsR );
		#print STDERR "navR ".Dumper( $navR );
		if( !defined $capR ){
			msgWarn( "unable to capture the result, skipping" );
			next;
		}

        # Try to replicate on NEW:
        # Re-discover a clickable with same visible text (best effort) and click there too
        my $match_new = clickable_find_equivalent( $drv_new, $act );
		#print STDERR "match_new ".Dumper( $match_new );

        my ($capN,$alertsN,$navN) = (undef, [], 0);
        if ($match_new) {
            ($capN,$alertsN,$navN) = @{ click_and_capture( $role, 'new', $match_new, $act->{text}, $url_new, $prefix, $act) };
			#print STDERR "capN ".Dumper( $capN );
			#print STDERR "alertsN ".Dumper( $alertsN );
			#print STDERR "navN ".Dumper( $navN );
        } else {
            # fallback: just capture current state
		    #perf_logs_drain( $drv_new );
            $capN = navigate_and_capture( $role, 'new', $basename, assume_ready => true );
        }

        # Count page visited now that we performed a pair of actions
        $hashref->{byRole}{$role}{visited} += 1;

		$shot_diff = sprintf "%s/diff_%s_%06d.png", "$hashref->{byRole}{$role}{roledir}/screenshots", $basename, $hashref->{byRole}{$role}{visited}+1;
		compare_captured( $role, $capR, $capN, { diff => $shot_diff });

        # Discover more actions from the new REF state and enqueue
        my $state_key_after = current_state_key( $drv_ref );
		if( $state_key_after ne $cur_ref ){
			msgVerbose( "state_key_after='$state_key_after' discovering new clickables" );
			my $more = clickable_discover_targets( $drv_ref->{session_id} );
			for my $a (@$more) {
				my $k2 = join('|', $state_key_after, $a->{id}||'');
				next if $tried{$k2};
				$a->{origin} = $state_key_after;
				push @todo, $a;
			}
		} else {
			msgVerbose( "state_key_after='$state_key_after' unchanged: fine" );
		}

        last if $hashref->{byRole}{$role}{visited} >= $hashref->{run}{max_pages};
        $depth_guard++;
    }
}

# -------------------------------------------------------------------------------------------------
# Compare two websites for the given role and the given route

sub doCrawlByLinks {
	my ( $role ) = @_;
	msgVerbose( "doCrawlByLinks() role'$role' entering" );

	# get the next item from the queue, either a single string (a configured route) or an array with its depth
	my ( $path, $depth ) = do {
		my $item = shift @{$hashref->{byRole}{$role}{queue}};
		ref( $item ) eq 'ARRAY' ? @$item : ( $item, 0 );
	};
	# return if already seen before
	# Otherwise, if we’ve seen this path only at a deeper depth, we’ll overwrite with the shallower one.
	return if $hashref->{byRole}{$role}{seen}{$path} && $hashref->{byRole}{$role}{seen}{$path} <= $depth;
	# else it is seen
	msgVerbose( "doCrawlByLinks() $path" );
	$hashref->{byRole}{$role}{seen}{$path} = $depth;

	# do not override the configured max depth
	return if $depth > $hashref->{run}{max_depth};

	# get and compare
	my $host_ref = URI->new( $conf->{bases}{ref} )->host;
	my $url_ref = $conf->{bases}{ref}.$path;
	my $url_new = $conf->{bases}{new}.$path;
	my $basename = $path;
	$basename =~ s![/\.]!_!g;

	my $shot_diff = sprintf "%s/diff_%s_%06d.png", "$hashref->{byRole}{$role}{roledir}/screenshots", $basename, $hashref->{byRole}{$role}{visited}+1;
	
	my $capture_ref = navigate_and_capture( $role, 'ref', $basename, url => $url_ref, label => 'initial' );
	my $capture_new = navigate_and_capture( $role, 'new', $basename, url => $url_new, label => 'initial' );

	is( $capture_new->{status}, 200, "[$role ($path)] new website returns '200' status code" );
	is( $capture_new->{status}, $capture_ref->{status}, "[$role ($path)] got same status code ($capture_new->{status})" );

	# increment the visited count (before, maybe, going to next path)
	#  but anyway just after having actually visited the page!
	$hashref->{byRole}{$role}{visited} += 1;

	# if we get the same error both on ref and new, then just cancel this one path, and go to next
	if( $capture_ref->{status} >= 400 && $capture_ref->{status} == $capture_new->{status} ){
		msgVerbose( "same error code, so just cancel this path" );
		record_sitemap_entry( $role, {
			path          => $path,
			depth         => $depth,
			capture_ref   => $capture_ref,
			capture_new   => $capture_new
		});
		return;
	}

	compare_captured( $role, $capture_ref, $capture_new, { diff => $shot_diff });

	# collect links from ref and queue them
	my $links_abs = extract_links( $hashref->{byRole}{$role}{drivers}{ref}->get_page_source, $url_ref, $conf->{crawl} );
	#print STDERR "links ".Dumper( $links_abs );
	my @next_paths;
	my $prefixes = $conf->{crawl}{prefix_path} || [ '' ];
	for my $abs ( @{$links_abs} ){
		next if $hashref->{run}{same_host} && !same_host( $abs, $host_ref );

		my $p = normalize_url_path_query( $abs, $conf->{crawl}{follow_query} );
		next if $p eq '' || $p =~ m{^/logout\b}i; # extra guard
		next unless url_allowed( $p, $conf->{crawl} );
		foreach my $prefix ( @{$prefixes} ){
			if( !exists $hashref->{byRole}{$role}{seen}{$prefix.$p} ){
				push( @next_paths, "$prefix$p" );
				msgVerbose( "adding '$prefix$p' to the queue" );
			}
		}
	}
	#print STDERR "next_paths ".Dumper( @next_paths );

	# queue next layer
	push( @{$hashref->{byRole}{$role}{queue}}, map {[ $_, $depth+1 ]} @next_paths );
	#print STDERR "queue ".Dumper( $hashref->{byRole}{$role}{queue} );
}

# -------------------------------------------------------------------------------------------------
# Execute JS (async) via W3C endpoint.

sub exec_js_w3c_async {
    my ( $sid, $script, $args ) = @_;
    my $url  = _wd( $sid )."/execute/async";
    my $res  = _http()->post( $url, {
        headers => { 'Content-Type' => 'application/json' },
        content => encode_json({ script => $script, args => $args // [] }),
    });
    msgErr( "exec_js_w3c_async() status=$res->{status} reason='$res->{reason}' content='$res->{content}'" ) unless $res->{success};
    return decode_json( $res->{content} )->{value};
}

# -------------------------------------------------------------------------------------------------
# Execute JS (sync) via W3C endpoint (no SRD quirks)

sub exec_js_w3c_sync {
    my ( $sid, $script, $args ) = @_;
    my $url = _wd( $sid )."/execute/sync";
    my $res = _http()->post( $url, {
        headers => { 'Content-Type' => 'application/json' },
        content => encode_json({ script => $script, args => $args // [] }),
    });
    msgErr( "exec_js_w3c_sync() status=$res->{status} reason='$res->{reason}' content='$res->{content}'" ) unless $res->{success};
    return decode_json( $res->{content} )->{value};
}

# -------------------------------------------------------------------------------------------------
# Extract links while excluding regions that match CSS selectors

sub extract_links {
    my ( $html, $base_url, $cfg_crawl ) = @_;
    my $dom = Mojo::DOM->new( $html );

    # remove excluded regions from DOM before link harvest
    for my $sel ( @{ $cfg_crawl->{exclude_selectors} // [] } ){
        $dom->find( $sel )->each( sub { $_->remove });
    }

    my %uniq;
	my $finders = $cfg_crawl->{find_links} || [{ find => 'a[href]', member => 'href' }];
	foreach my $it ( @{$finders} ){
		$dom->find( $it->{find} )->each( sub {
			my $href = $_->attr( $it->{member} ) // return;
			$href =~ s/^\s+|\s+$//g;
			return if $href eq '' || $href =~ m/^javascript:|^mailto:|^tel:/i;

			my $abs = URI->new_abs( $href, $base_url )->as_string;
			$uniq{$abs} = true;
		});
	}

    return [ sort keys %uniq ];
}

# -------------------------------------------------------------------------------------------------
# Try to extract the main Document response (status/ct/url) from perf logs
# Returns something like:
#		{
#          'headers' => {
#                         'Content-Type' => 'text/html; charset=utf-8',
#                         'X-Sent-By' => 'WS22DEV1',
#                         'Server' => 'nginx/1.20.1',
#                         'Transfer-Encoding' => 'chunked',
#                         'Connection' => 'keep-alive',
#                         'Date' => 'Thu, 04 Sep 2025 22:47:14 GMT'
#                       },
#          'url' => 'https://tom59.dev.blingua.fr/',
#          'ts' => '211658.923021',
#          'frameId' => '2A9D0CD1B73A4F8C7B581CA983F19D77',
#          'ct' => 'text/html',
#          'status' => 200
#        };

sub extract_main_doc_from_perf_logs {
    my ( $logs, $final_url ) = @_;
    return unless $logs && @$logs;

    my @docs;
    for my $e ( @$logs ){
        my $msg = _cdp_msg( $e ) || next;
        next unless $msg->{method} eq 'Network.responseReceived';
        next unless $msg->{params}{type} eq 'Document';
		#print STDERR "extract_main_doc_from_perf_logs() msg ".Dumper( $msg );

        my $resp = $msg->{params}{response} || next;
        my $url  = $resp->{url} // '';
        my $ct   = $resp->{mimeType} || ($resp->{headers} || {})->{'content-type'} || '';
        my $st   = $resp->{status} // 0;

        # keep candidates; we’ll pick the “best” below
        push @docs, {
            status  => $st + 0,
            ct      => $ct,
            url     => $url,
            headers => $resp->{headers} || {},
            frameId => $msg->{params}{frameId} || '',
            ts      => $msg->{params}{timestamp} || 0,
        };
    }
    return if !@docs;

    # Prefer the doc whose URL equals final_url (after redirects), else the latest.
    my ($best) = grep { ($_->{url}||'') eq ($final_url||'') } @docs;
    $best ||= (sort { ($a->{ts}//0) <=> ($b->{ts}//0) } @docs)[-1];

    # Normalize content-type (lowercase, first token)
    my $ct = lc($best->{ct} // '');
    $ct =~ s/;.*$//;  # drop charset etc.

    return { %$best, ct => $ct };
}

# -------------------------------------------------------------------------------------------------
# Same-origin fetch of the current page with redirect:'manual' so we see non-200s too.

sub fetch_status_ct_async {
    my ( $sid ) = @_;
	msgVerbose( "fetch_status_ct_async()" );
    my $js = q{
      const done = arguments[arguments.length - 1];
      (async function(){
        try {
          const res = await fetch(location.href, {
            method: 'GET',             // HEAD sometimes blocked; GET is safest
            redirect: 'manual',        // don't auto-follow; we want the real status
            cache: 'no-store',
            credentials: 'same-origin'
          });
          return done({ status: res.status, ct: res.headers.get('content-type') || '' });
        } catch (e) {
          return done({ status: 0, ct: '', err: String(e) });
        }
      })();
    };
    return exec_js_w3c_async( $sid, $js, []);
}

# -------------------------------------------------------------------------------------------------

sub handle_alert_if_present {
    my ( $sid, $action ) = @_;          # $action: 'accept' | 'dismiss'
    my $txt = alert_text_w3c( $sid );
	return undef if !$txt;
    msgWarn( "got Alert '$txt'" );
    $action && $action eq 'dismiss' ? alert_dismiss_w3c( $sid ) : alert_accept_w3c( $sid );
    return $txt;
}

# -------------------------------------------------------------------------------------------------

sub js_iframe_srcs {
	return q{
  		return ( function(){
    		const out = [];
    		document.querySelectorAll( 'iframe,frame' ).forEach( f => {
      			try{
        			if( f.contentDocument ) out.push( f.getAttribute( 'src' ) || '' );
      			}catch( e ){
					/* ignore */
				}
			});
			return out;
		})();
	};
}

# -------------------------------------------------------------------------------------------------
# logs a user to the website
# returns the session cookie

sub login_to {
	my ( $url, $driver, $role, $user, $pass  ) = @_;
	my $session_cookie = undef;
	msgVerbose( "logging-in '$user' user to $url..." );
	$driver->get( $url . $conf->{login}{path} );
	my $element = $driver->find_element_by_css( $conf->{login}{user_selector} );
	if( !$element ){
		msgWarn( "unable to find '$conf->{login}{user_selector}' element, cancelling" );
	} else {
		$element->clear();
		$element->send_keys( $user );
		$element = $driver->find_element_by_css( $conf->{login}{pass_selector} );
		if( !$element ){
			msgWarn( "unable to find '$conf->{login}{pass_selector}' element, cancelling" );
		} else {
			$element->clear();
			$element->send_keys( $pass );
			my $before = $driver->get_current_url();
			$element = $driver->find_element_by_css( $conf->{login}{submit_selector} );
			if( !$element ){
				msgWarn( "unable to find '$conf->{login}{submit_selector}' element, cancelling" );
			} else {
				$element->click();
				wait_for_url_change( $driver, $before, 5 );
				# get the session cookie (if any)
				my $cookies = $driver->get_all_cookies();
				my $re = $conf->{login}{session_cookie_regex};
				if( $re ){
					foreach my $cookie ( @{$cookies} ){
						if( $cookie->{name} =~ m/$re/i ){
							msgVerbose( "got '$cookie->{name}' session cookie by configured regex for $user\@$url" );
							$session_cookie = $cookie;
							last;
						}
					}
				# if no regex is configured, then try to get the first found after exclusion(s)
				} else {
					foreach my $cookie ( @{$cookies} ){
						my $excluded = false;
						foreach my $re ( @{$Const->{excluded_cookies}} ){
							if( $cookie->{name} =~ m/$re/i ){
								$excluded = true;
								last;
							}
						}
						if( $excluded ){
							msgVerbose( "$cookie->{name} cookie is excluded by code" );
						} else {
							msgVerbose( "keeping first found '$cookie->{name}' session cookie for $user\@$url");
							$session_cookie = $cookie;
							last;
						}
					}
				}
			}
		}
	}
	#print STDERR "session_cookie ".Dumper( $session_cookie );
	return $session_cookie;
}

# -------------------------------------------------------------------------------------------------

sub make_csv {
    my ( $v ) = @_;
    $v = '' unless defined $v;
    $v =~ s/"/""/g;
    return qq("$v");
}

# -------------------------------------------------------------------------------------------------
# get the page from url
# keep both the screenshot of the full page, and the HTML code in their respective output dirs
# returns the captured object, or undef
# %opt:
#   url          => 'https://...'   # optional; if omitted, do NOT navigate
#   assume_ready => 0|1             # if true, skip waits (you already waited), defaulting to false
#   label

sub navigate_and_capture {
	my ( $role, $which, $basename, %opt ) = @_;

	my $driver = $hashref->{byRole}{$role}{drivers}{$which};

	if( $opt{url} ){
	    # Drain logs so we only parse events for THIS navigation
	    perf_logs_drain( $driver );
		msgVerbose( "navigate_and_capture() url='$opt{url}'" );
	    $driver->get( $opt{url} );
	} else {
		msgVerbose( "navigate_and_capture() no url, using ".$driver->get_current_url );
	}

	return wait_and_capture( $role, $which, $basename, { wait => !$opt{assume_ready}, label => $opt{label} });
}

# -------------------------------------------------------------------------------------------------

sub normalize_url_path_query {
    my ( $abs_uri, $follow_query ) = @_;
    my $u = URI->new($abs_uri);
    $u->fragment( undef );
    return $follow_query ? $u->path_query : $u->path; # string
}

# -------------------------------------------------------------------------------------------------
# clear old perf logs before a new nav

sub perf_logs_drain {
    my ( $driver ) = @_;
    eval { $driver->get_log('performance') for 1..2 };  # swallow/ignore
}

# -------------------------------------------------------------------------------------------------
# at end, print a results summary

sub print_results_summary {
	msgOut( "results summary by role:" );
	foreach my $role ( sort keys %{$conf->{roles}} ){
		my $enabled = defined( $conf->{roles}{$role}{enabled} ) ? $conf->{roles}{$role}{enabled} : true;
		msgOut( "- $role:" );
		if( $enabled ){
			msgOut( "  output directory: $hashref->{byRole}{$role}{roledir}" );
			msgOut( "  visited pages count: $hashref->{byRole}{$role}{visited}" );
			msgOut( "  count per HTTP status:" );
			foreach my $status ( sort keys %{$hashref->{byRole}{$role}{status}} ){
				msgOut( "  $status: ".( scalar( @{$hashref->{byRole}{$role}{status}{$status}} )));
			}
			msgOut( "  erroneous pages count: ".( scalar( @{$hashref->{byRole}{$role}{errors}} )));
			foreach my $data ( @{$hashref->{byRole}{$role}{errors}} ){
				msgOut( "  - $data->{path}" );
			}
		} else {
			msgOut( "  disabled by configuration" );
		}
	}
	msgOut( "done" );
}

# -------------------------------------------------------------------------------------------------
# record a sitemap entry two ways:
# - as a simple array
# - as an array per http status
# (I):
# - the role
# - a hash which contains data, with at least path, depth and capture's

sub record_sitemap_entry {
    my ( $role, $data ) = @_;
	# build the parms
	my $parms = {
		path          => $data->{path} // '/',
		depth         => $data->{depth} // -1,
		status_ref    => $data->{capture_ref}{status},
		status_new    => $data->{capture_new}{status},
		final_url_ref => $data->{capture_ref}{final_url},
		final_url_new => $data->{capture_new}{final_url},
	};
	if( $data->{full} ){
		$parms->{type_ref} = $data->{capture_ref}{content_type};
		$parms->{type_new} = $data->{capture_new}{content_type},
		$parms->{dom_hash_ref} = $data->{capture_ref}{dom_hash};
		$parms->{dom_hash_new} = $data->{capture_new}{dom_hash};
		$parms->{shot_ref} = $data->{capture_ref}{shotdump} // '';
		$parms->{shot_new} = $data->{capture_new}{shotdump} // '';
		$parms->{html_ref} = $data->{capture_ref}{htmldump} // '';
		$parms->{html_new} = $data->{capture_new}{htmldump} // '';
		$parms->{errs} = $data->{errs} // [];
		$parms->{alerts_ref} = $data->{capture_ref}{alerts} // [];
		$parms->{alerts_new} = $data->{capture_new}{alerts} // [];
	}
	if( $data->{next_paths} ){
		$parms->{links_found} = scalar( @{$data->{next_paths}} );
		$parms->{next_paths} = $data->{next_paths};
	}
	# record all pages in a single array
	push( @{$hashref->{byRole}{$role}{sitemap}}, $parms );
	# have an array per status ref
	$hashref->{byRole}{$role}{status}{$parms->{status_ref}} //= [];
	push( @{$hashref->{byRole}{$role}{status}{$parms->{status_ref}}}, $parms );
	# record pages with a full entry and at least an error
	push( @{$hashref->{byRole}{$role}{errors}}, $parms ) if $data->{full} && scalar( @{$data->{errs}} );
}

# -------------------------------------------------------------------------------------------------

sub same_host {
    my ( $abs, $host ) = @_;
    my $u = URI->new( $abs );
    return ( $u->scheme =~ /^https?$/ ) && ( lc( $u->host // '' ) eq lc( $host ));
}

# -------------------------------------------------------------------------------------------------
# SRD is calling the legacy /execute endpoint even in W3C mode. ChromeDriver expects /execute/sync
# (or /execute/async), so it rejects the call.
# You’ve got two clean fixes. The simplest is: stop using JS for sanitizing and do it in Perl off
# the rendered HTML. That also avoids the “ARRAY(0x…)" you saw (that came from interpolating a
# Perl array into your JS).
# returns an array ( html, md5 )

sub sanitize_and_hash_perl {
    my ( $driver, $cfg ) = @_;

    # 1) grab rendered markup
    my $html = $driver->get_page_source;   # SRD: alias is sometimes page_source()

    # 2) drop nodes by CSS selector
    my $dom = Mojo::DOM->new( $html );
    for my $sel ( @{ $cfg->{ignore}{dom_selectors} // [] } ){
        $dom->find($sel)->each( sub { $_->remove } );
    }

    # 3) strip/normalize attributes
    my @attr_rx = map { qr/$_/ } @{ $cfg->{ignore}{dom_attributes} // [] };
    $dom->find('*')->each(sub {
    my $el = $_;
    my $attrs = $el->attr // {};

    # 4) remove matching attributes
    for my $name (keys %$attrs) {
        if (List::Util::any { $name =~ $_ } @attr_rx) {
            delete $attrs->{$name};            # hard delete
            next;
        }
        # 3b) normalize values
        my $v = $attrs->{$name};
        next unless defined $v;

        # timestamps
        $v =~ s/\b\d{10}\b/<TS>/g;

        # drop only v=… param, preserve other query params
        #  - remove "v=..." as a standalone param
        $v =~ s/(?:^|[?&])v=[^&]*(?=&|$)//gi;
        #  - clean up any trailing ? or & left behind
        $v =~ s/\?(?=&|$)//;		# tidy dangling ?
        $v =~ s/&(?=&|$)//;			# tidy dangling &

        $attrs->{$name} = $v;
    }

    # 5) write back in case Mojo clones internally (usually not needed)
    $el->attr($attrs);
});


    # 4) text normalization (regexes that cause noise)
    my $out = $dom->to_string;
    for my $pat (@{ $cfg->{ignore}{text_patterns} // [] }) {
        $out =~ s/$pat/<var>/g;
    }
    $out =~ s/\s+/ /g;
	#print STDERR "html ".Dumper( $out );

    return ( $out, md5_hex( encode_utf8( NFC( $out // '' ))));
}

# -------------------------------------------------------------------------------------------------

sub screenshot_file {
	my ( $drv, $file ) = @_;
	$drv->screenshot( $file ); # saves PNG directly
	return -s $file;
}

# -------------------------------------------------------------------------------------------------
# make a full page (not viewport) screenshot whatever be the running browser type

sub screenshot_fullpage_scroll_stitch {
    my ( %o ) = @_;
    my ( $sid, $driver, $outfile ) = @o{qw/ session_id driver outfile /};
	msgVerbose( "dumping screenshot to $outfile" );
    my $overlap  = $o{overlap_px} // 80;
    my $pause_ms = $o{pause_ms} // 150;
    my $max_seg  = $o{max_segments} // 200;

    # 1) Measure
    my $vh = exec_js_w3c_sync( $sid, 'return window.innerHeight;', [] );
    my $vw = exec_js_w3c_sync( $sid, 'return window.innerWidth;',  [] );
    my $doc_h = exec_js_w3c_sync( $sid, q{
        return Math.max(
          document.documentElement.scrollHeight,
          document.body ? document.body.scrollHeight : 0,
          document.documentElement.offsetHeight,
          document.documentElement.clientHeight
        );
    }, []);
    $vh ||= 800; $vw ||= 1366; $doc_h ||= $vh;

    # 2) Positions
    my @ys = (0);
    my $step = $vh - $overlap; $step = 1 if $step < 1;
    while ($ys[-1] + $vh < $doc_h && @ys < $max_seg) {
        my $next = $ys[-1] + $step;
        my $last_start = $doc_h - $vh;
        $next = $last_start if $next > $last_start;
        last if $next == $ys[-1];
        push @ys, $next;
    }

    # 3) Scroll + capture
    my @tiles;
    my $first_cols;
    for my $i ( 0..$#ys ){
        my $y = $ys[$i];
        exec_js_w3c_sync( $sid, 'window.scrollTo(0, arguments[0]); return true;', [$y] );
        usleep( $pause_ms*1000 );
        my $png = wd_viewport_png_bytes( $driver );
		my $img = Image::Magick->new;
		$img->BlobToImage( $png );
        my $cols = $img->Get( 'columns' );
		my $rows = $img->Get( 'rows' );
        $first_cols ||= $cols;
        if( $i > 0 ){
            my $crop_top = $overlap < $rows ? $overlap : $rows-1;
            my $keep_h = $rows - $crop_top;
            $img->Crop( geometry => "${cols}x${keep_h}+0+$crop_top" );
			$img->Set( page => '0x0' );
            $rows = $keep_h;
        }
        push( @tiles, { img => $img, h => $rows });
    }

    # 4) Stitch
    my $total_h = 0; $total_h += $_->{h} for @tiles;
    my $out = Image::Magick->new;
    $out->Set(size => $first_cols . 'x' . $total_h);
    $out->ReadImage('xc:white');
    my $yoff = 0;
    for my $t ( @tiles ){
        $out->Composite(image=>$t->{img}, compose=>'Over', x=>0, y=>$yoff);
        $yoff += $t->{h};
    }
    $out->Write($outfile);
    return $outfile;
}

# -------------------------------------------------------------------------------------------------
# Compare two screenshots visually using RMSE.
# Options:
#   diff_out     => '/path/to/diff.png'   # optional: write a heatmap-ish diff
#   fuzz         => '5%'                  # optional: color tolerance (default 5%)
#   align        => 'crop'|'pad'|'resize' # default 'crop'
#       crop   -> compare overlapping area only (no distortion)
#       pad    -> pad smaller image with white to match the bigger (no crop)
#       resize -> scale both to the same width (keeps aspect ratio; may blur)
#   resize_width => 1366                  # only used when align => 'resize'
#   threshold
#
# Returns a hashref:
#  { rmse => <number>, compared_w => <int>, compared_h => <int>, wrote_diff => 0|1 }

sub screenshots_compare_rmse {
    my (%o) = @_;
    my ($file_a, $file_b) = @o{qw/a b/};
    my $align   = $o{align} // 'crop';
    my $fuzz    = $o{fuzz}  // '5%';
    my $diffout = $o{diff_out};

    die "screenshots_compare_rmse: need a and b" unless $file_a && $file_b;

    my $A = Image::Magick->new; my $x = $A->Read($file_a); die $x if $x;
    my $B = Image::Magick->new; my $y = $B->Read($file_b); die $y if $y;

    my $aw = $A->Get('columns'); my $ah = $A->Get('rows');
    my $bw = $B->Get('columns'); my $bh = $B->Get('rows');

    my ($cw, $ch);

    if( $align eq 'resize' ){
        my $target_w = $o{resize_width} // ($aw < $bw ? $aw : $bw);
        my $r1 = $A->Resize(width => $target_w); die $r1 if $r1;
        my $r2 = $B->Resize(width => $target_w); die $r2 if $r2;
        $aw = $bw = $target_w;
        $ah = $A->Get('rows'); $bh = $B->Get('rows');
        # Compare only overlapping height to avoid tiny rounding diffs
        $ch = $ah < $bh ? $ah : $bh;
        $cw = $target_w;
        $A->Crop(geometry => "${cw}x${ch}+0+0"); $A->Set(page => '0x0');
        $B->Crop(geometry => "${cw}x${ch}+0+0"); $B->Set(page => '0x0');
    }
    elsif( $align eq 'pad' ){
        # Pad smaller image with white to match the larger dimensions
        $cw = ($aw > $bw) ? $aw : $bw;
        $ch = ($ah > $bh) ? $ah : $bh;

        for my $img ([$A,$aw,$ah], [$B,$bw,$bh]) {
            my ($I,$w,$h) = @$img;
            if ($w != $cw || $h != $ch) {
                my $bg = Image::Magick->new;
                my $r  = $bg->Set(size => $cw . 'x' . $ch); die $r if $r;
                $r = $bg->ReadImage('xc:white'); die $r if $r;
                # top-left align; switch to center by adjusting x/y
                $r = $bg->Composite(image => $I, compose => 'Over', x => 0, y => 0); die $r if $r;
                $I->ReadImage('null:');  # clear
                @$I = @$bg;              # replace content
            }
        }
    }
    else { # 'crop' (default): compare overlapping rectangle only
        $cw = $aw < $bw ? $aw : $bw;
        $ch = $ah < $bh ? $ah : $bh;
        $A->Crop(geometry => "${cw}x${ch}+0+0"); $A->Set(page => '0x0');
        $B->Crop(geometry => "${cw}x${ch}+0+0"); $B->Set(page => '0x0');
    }

    # Compute RMSE; optionally write a diff image if rmse > threshold (and threshold is set)
    my ($diff, $metric) = $A->Compare(image => $B, metric => 'RMSE', fuzz => $fuzz);
	$metric //= 0;
    my $wrote = 0;
    if( $diffout && $o{threshold} && $metric > $o{threshold} ){
        my $z = $diff->Write($diffout); die $z if $z;
        $wrote = 1;
    }

    return {
        rmse        => $metric,
        compared_w  => $cw,
        compared_h  => $ch,
        wrote_diff  => $wrote,
    };
}

# -------------------------------------------------------------------------------------------------

sub url_allowed {
	my ($url, $crawl_cfg) = @_;

    # Deny first
    if( @{ $crawl_cfg->{_deny_rx} // [] } ){
        return false if any { $url =~ $_ } @{ $crawl_cfg->{_deny_rx} };
    }

    # If no allow patterns provided/compiled -> allow everything (default)
    return true if $crawl_cfg->{_allow_all};

    # Else require at least one allow match
    return any { $url =~ $_ } @{ $crawl_cfg->{_allow_rx} };
}

# -------------------------------------------------------------------------------------------------
# returns the path extracted from an URL

sub url_path {
    my ( $driver ) = @_;
    my $u = URI->new( $driver->get_current_url );
    return $u->path || '/';
}

# -------------------------------------------------------------------------------------------------
# capture the data extracted from the current page
# keep both the screenshot of the full page, and the HTML code in their respective output dirs
# returns the captured object, or undef
# (I):
# - role
# - which = ref|new
# - basename
# - opts: an optional options hash ref with following keys:
#   > wait: true|false, defaulting to true
# 	> logs: an array ref, may be empty
#   > label: if truethy, then dump the doc

sub wait_and_capture {
    my ( $role, $which, $basename, $opts ) = @_;
	$opts //= {};

	my $driver = $hashref->{byRole}{$role}{drivers}{$which};
	my $wait = true;
	$wait = $opts->{wait} if defined $opts->{wait};

	my $ready;
	my $logs = [];
	my $alerts = [];

	if( $wait ){
		( $ready, $alerts, $logs ) = wait_for_page_ready( $driver, 5 );
		if( !$ready ){
			msgWarn( "Timeout waiting for page ready for ".$driver->get_current_url );
			return undef;
		}
		msgVerbose( "page ready, got alerts=[".join( '|', @{$alerts} )."]" );
	}

    # Grab performance log entries and find the main Document response
	# If they are not provided, collect logs now (once).
	if( !scalar( @{$logs} )){
		$logs = eval { $driver->get_log('performance') } // [];
	}

	my $doc = extract_main_doc_from_perf_logs( $logs, $driver->get_current_url );
	print STDERR "capture() $opts->{label} doc ".Dumper( $doc ) if $opts->{label};
	my ( $status, $mime, $resp_url, $headers ) = $doc ? @$doc{qw/status ct url headers/} : (undef, undef, undef, {});

	# Fallbacks if DevTools had no Document (rare but possible)
	if (!defined $status || !$status) {
		my $r = fetch_status_ct_async( $driver->{session_id} );
		if ($r && $r->{status}) {
			( $status, $mime, $resp_url ) = ( $r->{status}, lc($r->{ct} // '' ), $driver->get_current_url );
			$mime =~ s/;.*$//;
		} else {
			# last-resort heuristic: if body exists, treat as 200-ish
			$status = 200;
			$mime ||= exec_js_w3c_sync( $driver->{session_id}, 'return (document.contentType||"")', [] );
			$mime = lc($mime||''); $mime =~ s/;.*$//;
			$resp_url = $driver->get_current_url;
		}
	}

	my $html_fname = undef;
	my $shot_fname = undef;

	# Optionally take a screenshot (viewport or full-page)
	# our current Selenium::Remote::Driver+ChromeDriver v139 doesn't let us inject JS into the execution path
	if( $conf->{crawl}{write_screenshots} ){
		$shot_fname = sprintf "%s/%s_%s_%06d.png", "$hashref->{byRole}{$role}{roledir}/screenshots", $which, $basename, $hashref->{byRole}{$role}{visited}+1;
		screenshot_fullpage_scroll_stitch(
			session_id => $driver->{session_id},
			driver     => $driver,
			outfile    => $shot_fname,
			overlap_px => 80,
			pause_ms   => 200,
		);
    }

    # Sanitize + hash the rendered DOM
    #my $html = $driver->execute_script( $sanitize_js );
    #my $dom_hash = md5_hex( $html // '' );
	my ( $html, $dom_hash ) = sanitize_and_hash_perl( $driver, $conf );

	# optionally serialize the html
	if( $conf->{crawl}{write_htmls} ){
		$html_fname = sprintf "%s/%s_%s_%06d.html", "$hashref->{byRole}{$role}{roledir}/htmls", $which, $basename, $hashref->{byRole}{$role}{visited}+1;
		msgVerbose( "dumping html to $html_fname" );
		open my $fh, '>:utf8', $html_fname or die "open $html_fname: $!";
		print {$fh} $html;
		close $fh;
    }

    return {
		html         => $html,
        dom_hash     => $dom_hash,
        status       => $status,                                   # e.g., 200
        headers      => $headers,                                  # hashref
        content_type => $mime || (( $headers||{} )->{'content-type'} // '' ),
        final_url    => $driver->get_current_url,                  # landed URL
        response_url => $resp_url,                                 # URL from response event
		alerts       => $alerts || [],
		shotdump     => $shot_fname || '',
		htmldump     => $html_fname || ''
    };
}

# -------------------------------------------------------------------------------------------------
# Wait for the body is ready
# returns an array:
# - true|false whether the body is found (the page is ready)
# - alerts array ref, maybe empty

sub wait_for_body {
    my ( $driver ) = @_;
    my $t0 = time;
	my @alerts = ();
    while ( time - $t0 < $hashref->{run}{timeout_s} ){
        my $el = eval { $driver->find_element_by_css( 'body' ) };
		msgVerbose( "wait_for_body() got el=$el" );
		if( $el ){
	        return ( true, \@alerts );
		} else {
    		my $alert = handle_alert_if_present( $driver->{session_id}, 'accept' );
			push( @alerts, $alert ) if $alert;
		}
        select undef, undef, undef, 0.2;	# small wait before retry
    }
    return ( false, \@alerts );
}

# -------------------------------------------------------------------------------------------------
# DOM becomes "stable" when text length + element count stop changing for quiet_ms

sub wait_for_dom_stable {
    my ( $sid, $quiet_ms ) = @_;
    $quiet_ms  //= 500;

    my $last_sig;
    my $last_change_t = Time::HiRes::time;
    my $t0 = Time::HiRes::time;

    while (Time::HiRes::time - $t0 < $hashref->{run}{timeout_s} ){
        my $sig = exec_js_w3c_sync( $sid, q{
            const root = document.body;
            if (!root) return [0,0,0];
            const textLen = (root.innerText||'').length;
            const elCount = document.querySelectorAll('*').length;
            const hashish = textLen ^ elCount; // cheap fingerprint
            return [textLen, elCount, hashish];
        }, []);
        if (defined $last_sig && join(',',@$sig) ne join(',',@$last_sig)) {
            $last_sig = $sig;
            $last_change_t = Time::HiRes::time;
        } else {
            $last_sig //= $sig;
        }
        if ((Time::HiRes::time - $last_change_t)*1000 >= $quiet_ms) {
            return 1;
        }
        select undef, undef, undef, 0.12;
    }
    return 0;
}

# -------------------------------------------------------------------------------------------------
# This waits until the DevTools performance log has been quiet for N ms.
# It’s a good proxy for “page finished loading extra XHRs”.
# Collect performance logs
# Returns [ \@logs, $had_doc_response ]

sub wait_for_network_idle {
    my ( $driver, $quiet_ms ) = @_;
    $quiet_ms  //= 600;

    my $t0 = Time::HiRes::time;
    my $last_event_t = $t0;

    my @all;                 # we keep EVERYTHING we read
    my $had_doc_response = 0;

    while( Time::HiRes::time - $t0 < $hashref->{run}{timeout_s} ){
        my $logs = eval { $driver->get_log('performance') } // ();
        if( scalar( @{$logs} )){
            push @all, @{$logs};
            for my $e ( @{$logs} ){
                my $msg = _cdp_msg( $e ) || next;
                my $m = $msg->{method} // next;
                if( $m =~ /^Network\./ ){
                    $last_event_t = Time::HiRes::time;
                    $had_doc_response ||= ($m eq 'Network.responseReceived'
                        && (($msg->{params}{type} // '') eq 'Document'));
                }
            }
        }
        # quiet window?
        if ($had_doc_response && (Time::HiRes::time - $last_event_t) * 1000 >= $quiet_ms) {
            last;
        }
        select undef, undef, undef, 0.10;
    }
    return (\@all, $had_doc_response);
}

# -------------------------------------------------------------------------------------------------
# Combined SPA-ready: body present → network idle → DOM stable
# returns an array:
# - true|false whether the body is found (the page is ready)
# - alerts array ref, maybe empty
# - performance logs array ref, maybe empty

sub wait_for_page_ready {
    my ( $driver ) = @_;
    my ( $ok, $alerts ) = wait_for_body( $driver );
    return ( false, [], [] ) unless $ok;
    my ( $logs, $had_doc ) = wait_for_network_idle( $driver, 600 );  # quiet network ~600ms
    wait_for_dom_stable( $driver->{session_id}, 500 ) or msgWarn( "DOM not fully stable after timeout" );
    return ( $ok, $alerts, $logs );
}

# -------------------------------------------------------------------------------------------------
# Wait for URL to change from a known value

sub wait_for_url_change {
    my ( $driver, $old_url ) = @_;
    return wait_until(
        interval => 0.2,
        cond     => sub { my $u = $driver->get_current_url; ($u ne $old_url) ? $u : undef }
    );
}

# -------------------------------------------------------------------------------------------------
# Generic waiter: runs $cond->() repeatedly until it returns a truthy value.
# Returns that value, or undef on timeout.

sub wait_until {
    my ( %opt ) = @_;
    my $cond = $opt{cond} or die "wait_until: missing cond";
    my $interval = $opt{interval} // 0.2;   # seconds
    my $start = time;
    while( time - $start < $hashref->{run}{timeout_s} ){
        my $val = eval { $cond->() };
        return $val if $val;
        select undef, undef, undef, $interval;   # << precise sleep
    }
    return;
}

# -------------------------------------------------------------------------------------------------
# Take a WebDriver screenshot (viewport) through SRD

sub wd_viewport_png_bytes {
    my ( $driver ) = @_;
    my $b64 = $driver->screenshot();                    # base64
    return decode_base64( $b64 );
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> sub { $ep->runner()->help( @_ ); },
	"colored!"			=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"			=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"			=> sub { $ep->runner()->verbose( @_ ); },
	"debug!"			=> \$opt_debug,
	"jsonfile=s"		=> \$opt_jsonfile,
	"maxpages=i"		=> sub {
		my ( $name, $value ) = @_;
		$opt_maxpages = $value;
		$opt_maxpages_set = true;
	})){

		msgOut( "try '".$ep->runner()->command()." ".$ep->runner()->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $ep->runner()->help()){
	$ep->runner()->displayHelp( $defaults );
	TTP::exit();
}

msgVerbose( "got colored='".( $ep->runner()->colored() ? 'true':'false' )."'" );
msgVerbose( "got dummy='".( $ep->runner()->dummy() ? 'true':'false' )."'" );
msgVerbose( "got verbose='".( $ep->runner()->verbose() ? 'true':'false' )."'" );
msgVerbose( "got debug='".( $opt_debug ? 'true':'false' )."'" );
msgVerbose( "got jsonfile='$opt_jsonfile'" );
msgVerbose( "got maxpages='$opt_maxpages'" );

# JSON configuration file is mandatory
if( $opt_jsonfile ){
	config_load( $opt_jsonfile );
	$conf = config_compile_patterns( $conf );
} else {
	msgErr( "'--jsonfile' is required, but is not specified" );
}

# if a maxpages is provided, must be greater or equal to zero
if( $opt_maxpages_set ){
	msgErr( "'--maxpages' must be greater or equal to zero, got $opt_maxpages" ) if $opt_maxpages < 0;
}

if( !TTP::errs()){
	doCompare();
}

TTP::exit();
