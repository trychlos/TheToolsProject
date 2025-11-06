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
# http.pl compare browser management.

package TTP::HTTP::Compare::Browser;
die __PACKAGE__ . " must be loaded as TTP::HTTP::Compare::Browser\n" unless __PACKAGE__ eq 'TTP::HTTP::Compare::Browser';

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Data::Dumper;
use Digest::MD5 qw( md5_hex );
use Encode qw( encode_utf8 );
use HTTP::Tiny;
use JSON;
use List::Util qw( any );
use MIME::Base64 qw( decode_base64 );
use Mojo::DOM;
use Scalar::Util qw( blessed );
use Selenium::Chrome;
use Selenium::Remote::Driver;
use Time::HiRes qw( time );
use Try::Tiny;
use Unicode::Normalize qw( NFC );
use URI;

use TTP;
use vars::global qw( $ep );

use TTP::Constants qw( :all );
use TTP::HTTP::Compare::Capture;
use TTP::Message qw( :all );

use constant {
	DEFAULT_DEBUG => false
};

my $Const = {
	# browser driver capabilities
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
	# constant prefix used by ChromeDriver for all its paths
	path => '/wd/hub',
};

### Private methods

# -------------------------------------------------------------------------------------------------
# try to see if an alert has been raised by the website
# returns undef or the text of the alert

sub _alert_text_w3c {
    my ( $self ) = @_;

    my $r = $self->_http()->get( $self->_url_ssid().'/alert/text' );
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

sub _alert_accept_w3c {
    my ( $self ) = @_;

    $self->_http()->post( $self->_url_ssid().'/alert/accept', { headers=>{ 'Content-Type' => 'application/json' }, content=>'{}' });
}

# -------------------------------------------------------------------------------------------------

sub _alert_dismiss_w3c {
    my ( $self ) = @_;

    $self->_http()->post( $self->_url_ssid().'/alert/dismiss', { headers=>{ 'Content-Type' => 'application/json' }, content=>'{}' });
}

# -------------------------------------------------------------------------------------------------
# Decode the JSON message safely

sub _decode_msg {
    my ( $self, $e ) = @_;
    my $m = eval { decode_json( $e->{message} || '{}' ) } || return;
    return $m->{message} || {};
}

# -------------------------------------------------------------------------------------------------
# instanciate a browser driver
# because the Perl driver cannot initiate the session, we do that through HTTP::Tiny
# (I):
# - the URL to be addressed
#

sub _driver_start {
	my ( $self ) = @_;

	my $caps = $Const->{caps};
	my $width = $self->conf()->browserWidth();
	my $height = $self->conf()->browserHeight();
	push( @{$caps->{capabilities}{alwaysMatch}{'goog:chromeOptions'}{args}}, "--window-size=$width,$height" );
	#print "caps: ".Dumper( $caps );

    my $url = $self->_url_driver();
	msgVerbose( "creating session with url_driver='$url'" );
	my $res = $self->_http()->post( $url, {
		headers => { 'Content-Type' => 'application/json' },
		content => encode_json( $caps )
	});
	die "session create failed: $res->{status} $res->{reason}\n$res->{content}\n" unless $res->{success};

	my $payload = decode_json( $res->{content} );
	my $session_id = $payload->{sessionId} // $payload->{value}{sessionId} or die "no sessionId in response";
	msgVerbose( "got driver sessionId='$session_id' for ".$self->urlBase());
  
	my $driver = Selenium::Remote::Driver->new(
		session_id => $session_id,
		remote_server_addr => $self->conf()->browserDriverServer(),
		port => $self->conf()->browserDriverPort(),
		path => $Const->{path},
		is_w3c => true,
		debug => $self->isDebug()
	);

	#print STDERR "driver ".Dumper( $driver );
	return $driver;
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

sub _extract_main_doc_from_perf_logs {
    my ( $self, $logs, $final_url ) = @_;
    return unless $logs && @$logs;

    my @docs;
    for my $e ( @$logs ){
        my $msg = $self->_decode_msg( $e ) || next;
        next unless $msg->{method} eq 'Network.responseReceived';
        next unless $msg->{params}{type} eq 'Document';

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

sub _fetch_status {
    my ( $self ) = @_;
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
    return $self->exec_js_w3c_sync( $js, []);
}

# -------------------------------------------------------------------------------------------------

sub _handle_alert_if_present {
    my ( $self, $action ) = @_;          # $action: 'accept' | 'dismiss'
    my $txt = $self->_alert_text_w3c();
	return undef if !$txt;
    msgWarn( "got Alert '$txt'" );
    $action && $action eq 'dismiss' ? $self->_alert_dismiss_w3c() : $self->_alert_accept_w3c();
    return $txt;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - a ref to the configuration hash

sub _hash {
    my ( $self ) = @_;

	return $self->{conf}->var([ 'browser' ]);
}

# -------------------------------------------------------------------------------------------------

sub _http {
    my ( $self ) = @_;

	return HTTP::Tiny->new( timeout => $self->conf()->browserTimeout());
}

# -------------------------------------------------------------------------------------------------
# clear performance logs before a new nav

sub _perf_logs_drain {
    my ( $self ) = @_;
    eval { $self->driver()->get_log( 'performance' ) for 1..2 };  # swallow/ignore
}

# -------------------------------------------------------------------------------------------------
# Sanitizing the rendered html let us compute an idempotent md5 hash for this page
# This md5 hash will be later used to compare the ref and new html pages
# We honor here the configuration for 'compare.htmls.ignore'
# Returns an array ( html, md5 )

sub _sanitize_and_hash_html {
    my ( $self ) = @_;

    # 1) grab rendered markup
    my $html = $self->driver()->get_page_source();
    my $dom = Mojo::DOM->new( $html );
    my $out = $dom->to_string;

    # 2) drop nodes by CSS selector
    for my $sel ( @{ $self->conf()->compareHtmlsIgnoreDOMSelectors() }){
        $dom->find( $sel )->each( sub { $_->remove } );
    }

    #$found = $dom->find( 'div.toggle-left#wrapper' );
    #print STDERR "2: found=$found\n";

    # 3) strip/normalize attributes
    my @attr_rx = map { qr/$_/ } @{ $self->conf()->compareHtmlsIgnoreDOMAttributes() };
    $dom->find( '*' )->each( sub {
        my $el = $_;
        my $attrs = $el->attr // {};

        # 4) remove matching attributes
        for my $name ( keys %{$attrs} ){
            if( List::Util::any { $name =~ $_ } @attr_rx ){
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

    #$found = $dom->find( 'div.toggle-left#wrapper' );
    #print STDERR "3: found=$found\n";

    # 4) text normalization (regexes that cause noise)
    $out = $dom->to_string;
    for my $pat ( @{ $self->conf()->compareHtmlsIgnoreTextPatterns() }){
        $out =~ s/$pat/<var>/g;
    }
    $out =~ s/\s+/ /g;

    #$foundstr = $out =~ /div class="toggled-left" id="wrapper"/;
    #$countdom = $dom->find( 'div.toggle-left#wrapper' )->size;
    #print STDERR "4: found=$foundstr count=$countdom\n";

    return ( $out, md5_hex( encode_utf8( NFC( $out // '' ))));
}

# -------------------------------------------------------------------------------------------------
# Reset the cached page signature, typically after a navigate or a click, to force a recompute
# (I):
# - nothing

sub _signature_clear {
	my ( $self ) = @_;

    $self->{_signature} = undef;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - the base URL of the browser driver

sub _url_driver {
    my ( $self ) = @_;

	return "http://".$self->conf()->browserDriverServer().":".$self->conf()->browserDriverPort()."$Const->{path}/session";
}

# -------------------------------------------------------------------------------------------------
# (I):
# - a parm
# (O):
# - the base URL of the browser driver + the provided parm

sub _url_parm {
	my ( $self ) = @_;
	return $self->_url_driver()."/".$_[1];	# $_[1] = $ssid for example
}

# -------------------------------------------------------------------------------------------------
# (I):
# - a parm
# (O):
# - the base URL of the browser driver + the driver session id.

sub _url_ssid {
	my ( $self ) = @_;
	return $self->_url_driver()."/".$self->driver()->{session_id};
}

### Public methods

=pod
# -------------------------------------------------------------------------------------------------
# go back in the history
# (I):
# - nothing
# (O):
# -nothing
# Returns after having waited for the page

sub back {
    my ( $self ) = @_;

    #eval { $self->exec_js_w3c_sync( 'history.back(); return true;', [] ); };
    $self->driver()->go_back();
    $self->wait_for_page_ready();
}
=cut

=pod
# -------------------------------------------------------------------------------------------------
# Click and wait for the page be ready
# (O):
# - whether the click was successful

sub click_and_wait {
    my ( $self, $xpath ) = @_;

    if( $self->click_by_xpath( $xpath )){
        $self->wait_for_page_ready();
        return true;
    }

    return false;
}
=cut

=pod
# -------------------------------------------------------------------------------------------------
# JS: find element by data-scan-id across top + same-origin iframe docs; click it.

sub click_by_scan_id {
    my ( $self, $scan_id ) = @_;
	msgVerbose( "click_by_scan_id() scan_id='$scan_id'" );
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
    if( $self->exec_js_w3c_sync( $js, [ $scan_id ] )){
        $self->_signature_clear();
        return true;
    }
    return false;
}
=cut

# -------------------------------------------------------------------------------------------------
# JS: find element by xpath across top + same-origin iframe docs; click it.
# (O):
# - returns true if xpath has been found and clicked

sub click_by_xpath {
    my ( $self, $xpath ) = @_;
    TTP::stackTrace() if !$xpath;
	msgVerbose( "click_by_xpath() xpath='$xpath'" );
    my $js = q{
      return (function(xp){
        function allDocs(rootDoc){
          const out = [rootDoc];
          (function walk(doc){
            const frames = doc.querySelectorAll('iframe,frame');
            for (const f of frames){
              try{
                const cd = f.contentDocument;
                if (!cd) continue;
                out.push(cd);
                walk(cd);
              }catch(e){ /* cross-origin -> skip */ }
            }
          })(rootDoc);
          return out;
        }

        function evalFirst(doc, xp){
          try{
            const res = doc.evaluate(xp, doc, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null);
            return res && res.singleNodeValue || null;
          }catch(e){
            return null; // invalid XPath or unsupported axis
          }
        }

        const docs = allDocs(document);
        for (const d of docs){
          const el = evalFirst(d, xp);
          if (el){
            try {
              el.scrollIntoView({block:'center', inline:'center'});
            } catch(e){}
            try {
              el.click();
            } catch(e){
              // fallback via MouseEvent if .click() is blocked
              try {
                const evt = d.createEvent('MouseEvents');
                evt.initEvent('click', true, true);
                el.dispatchEvent(evt);
              } catch(_) {}
            }
            return true;
          }
        }
        return false;
      })(arguments[0]);
    };
	$self->_perf_logs_drain();
    if( $self->exec_js_w3c_sync( $js, [ $xpath ] )){
        $self->_signature_clear();
        return true;
    }
    return false;
}

=pod
# -------------------------------------------------------------------------------------------------
# JS: walk top document + same-origin iframes, tag clickables with data-scan-id,
#     and return metadata: id, text, href (may be javascript:...), kind, docKey, frameSrc

sub clickable_discover_targets_scanid {
    my ( $self ) = @_;
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
    		const out = [];

			// make sure the sane scan-id is not reused by having a global counter
			// because the initial compare is dumped to n°1, start here with 2 so that the 'visited' counter is tried to be kept aligned with the scan id's
			window.__scanCounter = window.__scanCounter || 2;

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
    my $list = $self->exec_js_w3c_sync( $js, [] );
    #print STDERR "clickable_discover_targets_scanid() ".Dumper( $list );
    msgVerbose( "clickable_discover_targets_scanid() found ".scalar( @{$list} )." targets" );
    return $list // [];
}
=cut

# -------------------------------------------------------------------------------------------------
# JS: walk top document + same-origin iframes
# Replace the above scan_id way by a XPATH implementation
# (O):
# - a list of items like
#   {
#     "xpath": "//*[@id=\"menu\"]//a[3]",
#     "text": "Mes rapports et attestations :",
#     "href": "/bo/44375/14450",
#     "kind": "a",
#     "onclick": "",
#     "docKey": "top" | "iframe[1]:/path",
#     "frameSrc": "/path/of/iframe"
#   }

sub clickable_discover_targets_xpath {
    my ( $self ) = @_;

    my $js = q{
      return (function(){
        /* ---------- helpers ---------- */

        function sameOriginFrameDocs(rootDoc){
          const out = [{doc: rootDoc, frameSrc: null, docKey: 'top'}];
          (function walk(doc, prefix){
            const frames = doc.querySelectorAll('iframe,frame');
            let idx = 0;
            for (const f of frames){
              idx++;
              try{
                const cd = f.contentDocument;
                if (!cd) continue; // not loaded or cross-origin
                const src = f.getAttribute('src') || '';
                const key = (prefix ? prefix+'>' : '') + 'iframe['+idx+']:' + src;
                out.push({doc: cd, frameSrc: src, docKey: key});
                walk(cd, key);
              }catch(e){ /* cross-origin -> skip */ }
            }
          })(rootDoc, '');
          return out;
        }

        function visible(el){
          const cs = el.ownerDocument.defaultView.getComputedStyle(el);
          if (!cs) return false;
          if (cs.display === 'none' || cs.visibility === 'hidden' || +cs.opacity === 0) return false;
          const r = el.getBoundingClientRect();
          return (r.width > 0 && r.height > 0);
        }

        // Build a reasonably stable XPath.
        // Strategy:
        //  1) If element has an id that is unique in its document => //*[@id="..."]
        //  2) Else, absolute path with tagName and [index] among same-tag siblings.
        function xpathFor(el){
          if (!el || el.nodeType !== 1) return null;
          const doc = el.ownerDocument;

          // Unique id path if possible
          const id = el.getAttribute('id');
          if (id) {
            // ensure uniqueness within this document
            const hit = doc.querySelectorAll('#'+CSS.escape(id)).length;
            if (hit === 1) {
              // Use id()-style or attribute-style; attr is more portable
              return '//*[@id="'+id.replace(/"/g,'&quot;')+'"]';
            }
          }

          // Otherwise, build absolute with nth-of-type (by tag)
          const steps = [];
          let cur = el;
          while (cur && cur.nodeType === 1 && cur !== doc.documentElement){
            const tag = (cur.tagName || '').toLowerCase();
            // index among same-tag siblings (1-based)
            let i = 1, sib = cur;
            while ((sib = sib.previousElementSibling) != null){
              if (sib.tagName.toLowerCase() === tag) i++;
            }
            steps.push(tag+'['+i+']');
            cur = cur.parentElement;
          }
          // Add the root element
          if (doc.documentElement && doc.documentElement !== el){
            steps.push((doc.documentElement.tagName||'html').toLowerCase()+'[1]');
          }
          steps.reverse();
          return '//' + steps.join('/');
        }

        function canonText(s){
          if (!s) return '';
          return s.replace(/&nbsp;/g,' ')
                  .replace(/\u00A0/g,' ')
                  .replace(/\s+/g,' ')
                  .trim()
                  .slice(0,160);
        }

        function onclickSignature(a){
          let txt = a.getAttribute('onclick') || '';
          if (!txt){
            const h = a.getAttribute('href') || '';
            if (/^\s*javascript:/i.test(h)) txt = h.replace(/^\s*javascript:\s*/i,'');
          }
          if (!txt) return '';
          txt = txt.replace(/\s+/g,' ');
          const m = txt.match(/([A-Za-z_$][\w$\.]*)\s*\(([^)]*)\)/);
          if (!m) return txt;
          const name = m[1].split('.').pop();
          const args = m[2].split(',').map(s=>s.trim()).join(',');
          return name+'('+args+')';
        }

        /* ---------- main ---------- */

        const docs = sameOriginFrameDocs(document);
        const out = [];

        for (const ctx of docs){
          const d = ctx.doc;

          // Build a unique set of candidates per document
          const pool = new Set();
          d.querySelectorAll('a[href], [role="link"], [data-link], [data-router-link], button, [onclick]').forEach(n => pool.add(n));

          for (const el of pool){
            if (!visible(el)) continue;
            if (el.hasAttribute('disabled') || el.getAttribute('aria-disabled') === 'true') continue;

            let href = el.getAttribute('href') || '';
            if (!href && el.closest('a[href]')) href = el.closest('a[href]').getAttribute('href') || '';

            const tag = (el.tagName||'').toLowerCase();
            const kind =
              tag === 'a' ? 'a' :
              tag === 'button' ? 'button' :
              el.hasAttribute('onclick') ? 'onclick' :
              el.getAttribute('role') === 'link' ? 'role-link' :
              'other';

            const text = canonText(el.innerText || el.textContent || '');
            const sig  = onclickSignature(el);

            const xp = xpathFor(el);
            if (!xp) continue;

            out.push({
              xpath   : xp,           // <- canonical locator to reuse later
              text    : text,
              href    : href,
              kind    : kind,
              onclick : sig,
              docKey  : ctx.docKey,
              frameSrc: ctx.frameSrc || ''
            });
          }
        }
        return out;
      })();
    };
    my $list = $self->exec_js_w3c_sync( $js, [] );
    return $list // [];
}

=pod
# -------------------------------------------------------------------------------------------------
# action = { kind, text, href, onclick }  -- all optional except kind
# (I):
# - the current queue item
# (O):
# - the best found match as a scan id available on the page

sub clickable_find_equivalent_scanid {
	my ( $self, $queue_item ) = @_;
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
			for( const el of nodes ){
			    const t = canonText( el.innerText || el.textContent || '' );
			    if( t === wantText ) return ensureScanId(el);
			}

			// Pass 2: case-insensitive text
			for( const el of nodes ){
			    const t = lcCanon( el.innerText || el.textContent || '' );
			    if( t === wantTextLC ) return ensureScanId(el);
			}

			// Pass 3: prefix contains
			if( wantPrefix ){
			    for( const el of nodes ){
				    const t = canonText( el.innerText || el.textContent || '' );
				    if( t.indexOf( wantPrefix ) >= 0 ) return ensureScanId(el);
			    }
			}

			// Pass 4: href path equality
			if( wantHrefPath ){
			    for( const el of nodes ){
				    const h = el.getAttribute && el.getAttribute( 'href' );
				    if( !h ) continue;
				    if( pathOnly( h ) === wantHrefPath ) return ensureScanId(el);
			    }
			}

			// Pass 5: onclick/javascript signature equality
			if( wantSig ){
			    for( const el of nodes ){
				    const sig = parseJsSig( el );
				    if( sig && sig === wantSig ) return ensureScanId(el);
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
	my $res = $self->exec_js_w3c_sync( $js, [ $queue_item->hash() ] );
	#print STDERR "clickable_find_equivalent() res ".Dumper( $res );
    return $res;
}
=cut

# -------------------------------------------------------------------------------------------------
# When replaying on “new”:
#  Try to click directly using the same xpath.
#  If it fails (no element found by XPath), then optionally fall back to a heuristic lookup
#  (this 'find_equivalent_xpath') using the stored metadata.
# (I):
# - the current queue item
# (O):
# - the best found match as a xpath available on the page

sub clickable_find_equivalent_xpath {
    my ( $self, $queue_item ) = @_;
    my $js = q{
      return (function(meta){
        function canon(s){
          if (!s) return '';
          return s.replace(/&nbsp;/g,' ').replace(/\u00A0/g,' ').replace(/\s+/g,' ').trim();
        }
        function lc(s){ return canon(s).toLowerCase(); }
        function pathOnly(u){
          try { const uu = new URL(u, location.href); return uu.pathname + (uu.search||''); }
          catch(e){ return ''; }
        }
        function onclickSig(a){
          let txt = a.getAttribute('onclick') || '';
          if (!txt){
            const h = a.getAttribute('href') || '';
            if (/^\s*javascript:/i.test(h)) txt = h.replace(/^\s*javascript:\s*/i,'');
          }
          if (!txt) return '';
          txt = txt.replace(/\s+/g,' ');
          const m = txt.match(/([A-Za-z_$][\w$\.]*)\s*\(([^)]*)\)/);
          if (!m) return txt;
          const name = m[1].split('.').pop();
          const args = m[2].split(',').map(s=>s.trim()).join(',');
          return name+'('+args+')';
        }
        function jaccard(a,b){
          const A = new Set(lc(a).split(/\s+/).filter(Boolean));
          const B = new Set(lc(b).split(/\s+/).filter(Boolean));
          if (!A.size && !B.size) return 1;
          let inter=0; for (const t of A){ if (B.has(t)) inter++; }
          return inter / (A.size + B.size - inter || 1);
        }
        function xpathFor(el){
          if (!el || el.nodeType !== 1) return null;
          const doc = el.ownerDocument;
          const id = el.getAttribute('id');
          if (id){
            const hit = doc.querySelectorAll('#'+CSS.escape(id)).length;
            if (hit === 1) return '//*[@id="'+id.replace(/"/g,'&quot;')+'"]';
          }
          const steps = [];
          let cur = el;
          while (cur && cur.nodeType === 1 && cur !== doc.documentElement){
            const tag = (cur.tagName||'').toLowerCase();
            let i=1,s=cur;
            while ((s=s.previousElementSibling)!=null){
              if (s.tagName.toLowerCase()===tag) i++;
            }
            steps.push(tag+'['+i+']');
            cur = cur.parentElement;
          }
          if (doc.documentElement && doc.documentElement !== el){
            steps.push((doc.documentElement.tagName||'html').toLowerCase()+'[1]');
          }
          steps.reverse();
          return '//' + steps.join('/');
        }

        const wantKind = (meta.kind || 'a,button,[role="link"]').trim();
        const wantText = canon(meta.text||'');
        const wantHref = pathOnly(meta.href||'');
        const wantSig  = meta.onclick || '';

        const nodes = Array.from(document.querySelectorAll(wantKind));
        // Scoring
        let best = {score:-1, el:null};

        for (const el of nodes){
          const text = el.innerText || el.textContent || '';
          const href = el.getAttribute && el.getAttribute('href') || '';
          const sig  = onclickSig(el);
          let s = 0;

          // exact text match is strong
          if (canon(text) === wantText) s += 3;
          // href path equal helps
          if (wantHref && pathOnly(href) === wantHref) s += 2;
          // onclick sig equal helps
          if (wantSig && sig && sig === wantSig) s += 2;
          // fuzzy text bonus
          s += jaccard(text, wantText);

          if (s > best.score) best = {score:s, el};
        }
        return best.el ? xpathFor(best.el) : null;
      })(arguments[0]);
    };
    return $self->exec_js_w3c_sync( $js, [ $queue_item->hash() ] );
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - a ref to the TTP::HTTP::Compare::Config configuration object as provided by the Role object

sub conf {
    my ( $self ) = @_;

	return $self->role()->conf();
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - the path of the current URL

sub current_path {
    my ( $self ) = @_;

	my $url = $self->driver()->get_current_url();
    my $u = URI->new( $url );

    return $u->path;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - returns the attached chromedriver

sub driver {
	my ( $self, $url ) = @_;

	return $self->{_driver};
}

# -------------------------------------------------------------------------------------------------
# Execute JS (sync) via W3C endpoint (no SRD quirks)

sub exec_js_w3c_sync {
    my ( $self, $script, $args ) = @_;
    my $url = $self->_url_ssid()."/execute/sync";
    my $res;
    try {
        $res = $self->_http()->post( $url, {
            headers => { 'Content-Type' => 'application/json' },
            content => encode_json({ script => $script, args => $args // [] }),
        });
    } catch {
        # at visited=79
        # [http.pl compare] (ERR) do /home/pierre/data/dev/TheToolsProject/tools/http/compare.do.pl: encountered object 'TTP::HTTP::Compare::QueueItem=HASH(0x55876f2d5028)',
        # but neither allow_blessed, convert_blessed nor allow_tags settings are enabled (or TO_JSON/FREEZE method missing)
        # at /home/pierre/data/dev/TheToolsProject/tools/libexec/perl/TTP/HTTP/Compare/Browser.pm line 1085.
        print STDERR "script: ".Dumper( $script );
        print STDERR "args: ".Dumper( $args );
        msgErr( $_ );
        TTP::stackTrace();
    };
    msgErr( "exec_js_w3c_sync() status=$res->{status} reason='$res->{reason}' content='$res->{content}'" ) unless $res->{success};
    return decode_json( $res->{content} )->{value};
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - whether this browser driver must be run in debug mode

sub isDebug {
	my ( $self ) = @_;

	my $args = $self->{_args};
	my $debug = $args->{debug};
	$debug = DEFAULT_DEBUG if !defined $debug;

	return $debug;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - whether this browser driver is correctly defined

sub isDefined {
	my ( $self ) = @_;

	my $ref = $self->_hash();

	return defined $ref;
}

# -------------------------------------------------------------------------------------------------
# Get the page from an url
# (I):
# - the path to navigate to

sub navigate {
	my ( $self, $path ) = @_;

    my $url = $self->urlBase().$path;
    msgVerbose( "navigate() url='$url'" );

    # Drain logs so we only parse events for THIS navigation
    $self->_perf_logs_drain();
    $self->driver()->get( $url );
    $self->_signature_clear();
}

# -------------------------------------------------------------------------------------------------
# Get the page from an url
# (I):
# - the path to navigate to
# (O):
# -the captured document as a TTP::HTTP::Compare::Capture object

sub navigate_and_capture {
	my ( $self, $path ) = @_;

    $self->navigate( $path );
	return $self->wait_and_capture();
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - the role as a TTP::HTTP::Compare::Role object

sub role {
	my ( $self ) = @_;

    return $self->{_role};
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - the screenshot as a png bytes array

sub screenshot {
	my ( $self ) = @_;

    my $b64 = $self->driver()->screenshot();    # base64
    my $png = decode_base64( $b64 );

    return $png;
}

# -------------------------------------------------------------------------------------------------
# Build a page signature which is expected to uniquely identify it.
# Code provided by chatgpt:
# + ignoring dom signature
# + add frame id
# + warns when iframes do not honor same_host configuration
# + doesn't install uuid unless installing in new too
# (O):
# - a signature as 'top:https://tom59.ref.blingua.fr/fo|if:0#content-frame#/bo/27574/8615#/bo/person/home|if:1#details-frame##|if:2#ifDbox##'

sub signature {
    my ( $self ) = @_;

    my $signature = $self->{_signature};
    if( $signature ){
        msgVerbose( "signature() cached='$signature'" );
        return $signature;
    }

    my $js = q{
        return (function(){
            function domSig(doc){
                try{
                    const t = (doc.body?.innerText || '').length;
                    const n = doc.querySelectorAll('*').length;
                    return String( t )+'|'+String(n);
                } catch( e ){
                    return '0|0';
                }
            }
            const topHref = location.href;
            const topSig  = domSig(document);
            const framesInfo = [];

            (function walk( doc ){
                const frames = Array.from( doc.querySelectorAll( 'iframe, frame' ));
                for ( let i=0 ; i<frames.length ; i++ ){
                    const fr = frames[i];
                    let sameOrigin = true, curHref = '', sig = '0|0';
                    try {
                        curHref = fr.contentWindow?.location?.href || '';
                    } catch( e ){
                        sameOrigin=false;
                    }

                    framesInfo.push({
                        index: i,
                        src: fr.getAttribute('src') || '',
                        sameOrigin,
                        href: curHref,
                        id: fr.getAttribute( 'id' )
                    });

                    try {
                        const cd = fr.contentDocument;
                        if( cd ) walk( cd );
                    } catch( e ){
                        /* ignore */
                    }
                }
            })( document, [] );

            return { topHref, topSig, frames: framesInfo };
        })();
    };
    my $st = $self->exec_js_w3c_sync( $js, [] ) || {};

    my $parts = [];
    push( @{$parts}, "top:".( $st->{topHref} // '' ));
    push( @{$parts}, "doc:".( $st->{topSig} // '' ));

    for my $f ( @{ $st->{frames} // [] } ){
        my $path = '';
        if( $f->{href} ne 'about:blank' ){
            $path = URI->new( $f->{href} );
            $path = $path->path;
        }
        push( @{$parts}, "if:$f->{index}#$f->{id}#$f->{src}#$path" );
        if (!$f->{sameOrigin} && $self->conf()->crawlSameHost()){
            msgWarn( "found cross origin $f->{href}" );
        }
    }

    $signature = join( '|', @$parts );
    $self->{_signature} = $signature;
    msgVerbose( "signature() computed='$signature'" );

    return $signature;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - the base URL as defined at instanciation time

sub urlBase {
	my ( $self ) = @_;

    my $which = $self->which();
    my $url = undef;
    if( $which eq 'ref' ){
        $url = $self->role()->conf()->basesRef();
    } elsif( $which eq 'new' ){
        $url = $self->role()->conf()->basesNew();
    } else {
        msgErr( "urlBase() which='$which' is not handled" );
    }
	return $url;
}

# -------------------------------------------------------------------------------------------------
# returns the path extracted from the current URL

sub urlPath {
    my ( $self ) = @_;
    my $u = URI->new( $self->driver()->get_current_url());
    return $u->path || '/';
}

=pod
# -------------------------------------------------------------------------------------------------
# Take a WebDriver screenshot (viewport) through SRD

sub viewport_png_bytes {
    my ( $self ) = @_;
    my $b64 = $self->driver()->screenshot();    # base64
    return decode_base64( $b64 );
}
=cut

# -------------------------------------------------------------------------------------------------
# capture the data extracted from the current page
# returns the captured object, or undef
# (I):
# - args: an optional options hash ref with following keys:
#   > wait: whether we want to wait before capturing, defaulting to true
# 	> logs: an array ref, may be empty
# (O):
# -the captured document as a TTP::HTTP::Compare::Capture object

sub wait_and_capture {
    my ( $self, $args ) = @_;
	$args //= {};

	my $wait = true;
	$wait = $args->{wait} if defined $args->{wait};

	my $driver = $self->driver();
	my $ready;
	my $logs = [];
	my $alerts = [];

	if( $wait ){
		( $ready, $alerts, $logs ) = $self->wait_for_page_ready();
		if( !$ready ){
			msgWarn( "Timeout waiting for page ready for ".$driver->get_current_url());
			return undef;
		}
		msgVerbose( "page ready, got alerts=[".join( '|', @{$alerts} )."]" );
	}

    # Grab performance log entries and find the main Document response
	# If they are not provided, collect logs now (once).
	if( !scalar( @{$logs} )){
		$logs = eval { $driver->get_log('performance') } // [];
	}

	my $doc = $self->_extract_main_doc_from_perf_logs( $logs, $driver->get_current_url());
	#print STDERR "wait_and_capture() $args->{label} doc ".Dumper( $doc );
	my ( $status, $mime, $resp_url, $headers ) = $doc ? @$doc{qw/status ct url headers/} : (undef, undef, undef, {});

	# Fallbacks if DevTools had no Document (rare but possible)
	if( !$status ){
		my $r = $self->_fetch_status();
		if ($r && $r->{status}) {
			( $status, $mime, $resp_url ) = ( $r->{status}, lc($r->{ct} // '' ), $driver->get_current_url );
			$mime =~ s/;.*$//;
		} else {
			# last-resort heuristic: if body exists, treat as 200-ish
			$status = 200;
			$mime ||= $self->exec_js_w3c_sync( 'return (document.contentType||"")', [] );
			$mime = lc( $mime||'' );
			$mime =~ s/;.*$//;
			$resp_url = $driver->get_current_url();
		}
	}

    # Sanitize + hash the rendered DOM
	my ( $html, $dom_hash ) = $self->_sanitize_and_hash_html();

    return TTP::HTTP::Compare::Capture->new( $self->ep(), $self, {
		html         => $html,
        dom_hash     => $dom_hash,
        status       => $status,                                   # e.g., 200
        headers      => $headers,                                  # hashref
        content_type => $mime || (( $headers || {} )->{'content-type'} // '' ),
        final_url    => $driver->get_current_url(),                # landed URL
        response_url => $resp_url,                                 # URL from response event
		alerts       => $alerts || []
    });
}

# -------------------------------------------------------------------------------------------------
# Wait for the body is ready
# returns an array:
# - true|false whether the body is found (the page is ready)
# - alerts array ref, maybe empty

sub wait_for_body {
    my ( $self ) = @_;
    my $t0 = time;
	my @alerts = ();
	my $timeout = $self->conf()->browserTimeout();
    while ( time - $t0 < $timeout ){
        my $el = eval { $self->driver()->find_element_by_css( 'body' ) };
		msgVerbose( "wait_for_body() got el=$el" );
		if( $el ){
	        return ( true, \@alerts );
		} else {
    		my $alert = $self->_handle_alert_if_present( 'accept' );
			push( @alerts, $alert ) if $alert;
		}
        select undef, undef, undef, 0.1;	# wait 0.1 sec before retry
    }
    return ( false, \@alerts );
}

# -------------------------------------------------------------------------------------------------
# DOM becomes "stable" when text length + element count stop changing for quiet_ms

sub wait_for_dom_stable {
    my ( $self ) = @_;
    my $quiet_ms  //= 500;

    my $last_sig;
    my $last_change_t = Time::HiRes::time;
    my $t0 = Time::HiRes::time;
	my $timeout = $self->conf()->browserTimeout();

    while( Time::HiRes::time - $t0 < $timeout ){
        my $sig = $self->exec_js_w3c_sync( q{
            const root = document.body;
            if( !root ) return [0,0,0];
            const textLen = ( root.innerText || '' ).length;
            const elCount = document.querySelectorAll( '*' ).length;
            const hashish = textLen ^ elCount; // cheap fingerprint
            return [textLen, elCount, hashish];
        }, [] );
        if( defined $last_sig && join( ',', @$sig ) ne join( ',', @$last_sig )){
            $last_sig = $sig;
            $last_change_t = Time::HiRes::time;
        } else {
            $last_sig //= $sig;
        }
        if(( Time::HiRes::time - $last_change_t ) * 1000 >= $quiet_ms ){
            return true;
        }
        select undef, undef, undef, 0.1;	# wait 0.1 sec before retry
    }
    return false;
}

# -------------------------------------------------------------------------------------------------
# This waits until the DevTools performance log has been quiet for N ms.
# It’s a good proxy for “page finished loading extra XHRs”.
# Collect performance logs
# Returns [ \@logs, $had_doc_response ]

sub wait_for_network_idle {
    my ( $self ) = @_;
    my $quiet_ms  //= 500;

    my $t0 = Time::HiRes::time;
    my $last_event_t = $t0;
	my $timeout = $self->conf()->browserTimeout();

    my @all;                 # we keep EVERYTHING we read
    my $had_doc_response = 0;

    while( Time::HiRes::time - $t0 < $timeout ){
        my $logs = eval { $self->driver()->get_log('performance') } // ();
        if( scalar( @{$logs} )){
            push @all, @{$logs};
            for my $e ( @{$logs} ){
                my $msg = $self->_decode_msg( $e ) || next;
                my $m = $msg->{method} // next;
                if( $m =~ /^Network\./ ){
                    $last_event_t = Time::HiRes::time;
                    $had_doc_response ||= ( $m eq 'Network.responseReceived' && (( $msg->{params}{type} // '') eq 'Document' ));
                }
            }
        }
        # quiet window?
        if ($had_doc_response && (Time::HiRes::time - $last_event_t) * 1000 >= $quiet_ms) {
            last;
        }
        select undef, undef, undef, 0.1;
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
    my ( $self ) = @_;
    my ( $ok, $alerts ) = $self->wait_for_body();
    return ( false, [], [] ) unless $ok;
    my ( $logs, $had_doc ) = $self->wait_for_network_idle();  # quiet network ~600ms
    $self->wait_for_dom_stable() or msgWarn( "DOM not fully stable after timeout" );
    return ( $ok, $alerts, $logs );
}

# -------------------------------------------------------------------------------------------------
# Wait for URL to change from a known value

sub wait_for_url_change {
    my ( $self, $old_url ) = @_;
    return $self->wait_until(
        interval => 0.1,
        cond     => sub { my $u = $self->driver()->get_current_url; ($u ne $old_url) ? $u : undef }
    );
}

# -------------------------------------------------------------------------------------------------
# Generic waiter: runs $cond->() repeatedly until it returns a truthy value.
# Returns that value, or undef on timeout.

sub wait_until {
    my ( $self, %opt ) = @_;
    my $cond = $opt{cond} or die "wait_until: missing cond";
    my $interval = $opt{interval} // 0.1;   # seconds
    my $start = time;
	my $timeout = $self->conf()->browserTimeout();
    while( time - $start < $timeout ){
        my $val = eval { $cond->() };
        return $val if $val;
        select undef, undef, undef, $interval;   # << precise sleep in (maybe fractional) seconds
    }
    return;
}

# -------------------------------------------------------------------------------------------------
# Returns whether we address the 'ref' or the 'new' site
# This relies on the instanciation args

sub which {
    my ( $self ) = @_;

	return $self->{_which};
}

### Class methods

# -------------------------------------------------------------------------------------------------
# Constructor
# (I):
# - the TTP::EP entry point
# - the TTP::HTTP::Compare::Role object
# - whether we address the new or the reference site ('ref'|'new')
# - an optional options hash with following keys:
#   > debug: whether to run the browser driver in debug mode
# (O):
# - this object

sub new {
	my ( $class, $ep, $role, $which, $args ) = @_;
	$class = ref( $class ) || $class;
	$args //= {};

	if( !$ep || !blessed( $ep ) || !$ep->isa( 'TTP::EP' )){
		msgErr( "unexpected ep: ".TTP::chompDumper( $ep ));
		TTP::stackTrace();
	}
	if( !$role || !blessed( $role ) || !$role->isa( 'TTP::HTTP::Compare::Role' )){
		msgErr( "unexpected role: ".TTP::chompDumper( $role ));
		TTP::stackTrace();
	}
	if( $which ne 'ref' && $which ne 'new' ){
		msgErr( "unexpected which='$which'" );
		TTP::stackTrace();
	}

	my $self = $class->SUPER::new( $ep, $args );
	bless $self, $class;
	msgDebug( __PACKAGE__."::new() role='".$role->name()."' which='$which'" );

	$self->{_role} = $role;
	$self->{_which} = $which;
	$self->{_args} = $args;

	$self->{_driver} = $self->_driver_start();

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

	my $driver = $self->driver();
    if( $driver ){
    	$driver->quit();
        msgVerbose( "driver quitting" );
    } else {
        msgVerbose( "driver is not defined" );
    }

	return;
}

### Global functions
### Note for the developer: while a global function doesn't take any argument, it can be called both
### as a class method 'TTP::Package->method()' or as a global function 'TTP::Package::method()',
### the former being preferred (hence the writing inside of the 'Class methods' block which brings
### the class as first argument).

1;
