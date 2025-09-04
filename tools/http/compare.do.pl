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
	excluded_cookies => [
		"AspNetCore.Antiforgery"
	],
	path => '/wd/hub'
};

# -------------------------------------------------------------------------------------------------
# ahead definition
# note that executing a JS inside of a got page is currently available as current version of the
# Selenium::Remote::Driver still calls (obsolete) /execute ChromeDriver endpoint instead of
# /execute/sync or /execute/async.. So this is disabled and replaced with a sanitizing Perl version

my $sanitize_js = sprintf q{
	( function(){
		const dropTags   = new Set(%s);
		const dropAttrRx = [%s].map(s=>new RegExp(s));
		const textRx     = [%s].map(s=>new RegExp(s,'g'));

		function cleanse(node){
			if (node.nodeType === 1){
				if (dropTags.has(node.tagName.toLowerCase())) { node.remove(); return; }
				for (const a of [...node.attributes]) {
				if (dropAttrRx.some(rx => rx.test(a.name))) node.removeAttribute(a.name);
				// normalize cache-buster-ish values
				if (a.value) node.setAttribute(a.name, a.value.replace(/\b\d{10}\b/g, '<TS>').replace(/v=\w{6,}/g,'v=<hash>'));
				}
				for (const c of [...node.childNodes]) cleanse(c);
			} else if (node.nodeType === 3){
				let t = node.nodeValue;
				for (const rx of textRx) t = t.replace(rx, '<var>');
				node.nodeValue = t.replace(/\s+/g,' ');
			}
		}
		cleanse(document.documentElement);
		document.documentElement.normalize();
		return document.documentElement.outerHTML;
	})();
},
	# arrays rendered into JS
	json_array([ map lc($_), @{$conf->{ignore}{dom_selectors} // []} ]),
	join(',', map { "'$_'" } @{$conf->{ignore}{dom_attributes} // []}),
	join(',', map { "'$_'" } @{$conf->{ignore}{text_patterns} // []});

# -------------------------------------------------------------------------------------------------

sub _wd {
	return "http://$hashref->{run}{server}:$conf->{browser}{port}$Const->{path}/session/$_[0]";	# $_[0] = $sid
}

# -------------------------------------------------------------------------------------------------
# try to see if an alert has been raised by the website
# returns undef or the text of the alert

sub alert_text_w3c {
    my ( $sid ) = @_;
    my $r = HTTP::Tiny->new( timeout => 5 )->get( _wd( $sid ).'/alert/text' );
    return undef unless $r->{success};
	#print STDERR "r ".Dumper( $r );
    return eval { decode_json( $r->{content} )->{value} };
}

# -------------------------------------------------------------------------------------------------

sub alert_accept_w3c {
    my ( $sid ) = @_;
    HTTP::Tiny->new( timeout => 5 )->post( _wd( $sid ).'/alert/accept', { headers=>{ 'Content-Type' => 'application/json' }, content=>'{}' });
}

# -------------------------------------------------------------------------------------------------

sub alert_dismiss_w3c {
    my ( $sid ) = @_;
    HTTP::Tiny->new( timeout => 5 )->post( _wd( $sid ).'/alert/dismiss', { headers=>{ 'Content-Type' => 'application/json' }, content=>'{}' });
}

# -------------------------------------------------------------------------------------------------
# instanciate a browser driver
# because the Perl driver cannot initiate the session, we do that through HTTP::Tiny

sub browser_driver {
	my ( $url ) = @_;
	my $http = HTTP::Tiny->new( timeout => 30 );
	my $res = $http->post( "http://$hashref->{run}{server}:$conf->{browser}{port}$Const->{path}/session", {
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
# Compare two screenshots visually using RMSE.
# Options:
#   diff_out     => '/path/to/diff.png'   # optional: write a heatmap-ish diff
#   fuzz         => '5%'                  # optional: color tolerance (default 5%)
#   align        => 'crop'|'pad'|'resize' # default 'crop'
#       crop   -> compare overlapping area only (no distortion)
#       pad    -> pad smaller image with white to match the bigger (no crop)
#       resize -> scale both to the same width (keeps aspect ratio; may blur)
#   resize_width => 1366                  # only used when align => 'resize'
#
# Returns a hashref:
#  { rmse => <number>, compared_w => <int>, compared_h => <int>, wrote_diff => 0|1 }

sub compare_screenshots_rmse {
    my (%o) = @_;
    my ($file_a, $file_b) = @o{qw/a b/};
    my $align   = $o{align} // 'crop';
    my $fuzz    = $o{fuzz}  // '5%';
    my $diffout = $o{diff_out};

    die "compare_screenshots_rmse: need a and b" unless $file_a && $file_b;

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

    # Compute RMSE; optionally write a diff image
    my ($diff, $metric) = $A->Compare(image => $B, metric => 'RMSE', fuzz => $fuzz);
    my $wrote = 0;
    if ($diffout) {
        my $z = $diff->Write($diffout); die $z if $z;
        $wrote = 1;
    }

    return {
        rmse        => $metric // 0,
        compared_w  => $cw,
        compared_h  => $ch,
        wrote_diff  => $wrote,
    };
}

# -------------------------------------------------------------------------------------------------
# Call this right after you load YAML/JSON into $cfg

sub compile_url_patterns {
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
# Compare two websites

sub doCompare {
	msgOut( "comparing ref '$conf->{bases}{ref}' against '$conf->{bases}{new}' URLs..." );
	$hashref->{byRole} = {};
	$hashref->{run} = {
		rolesroot => tempdir()."/byRole",
		max_depth => $conf->{crawl}{max_depth} || 1,
		same_host => defined( $conf->{crawl}{same_host_only} ) ? $conf->{crawl}{same_host_only} : true,
		server => $conf->{browser}{remote_server_addr} || '127.0.0.1'
	};
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
					# limit by count of pages, the command-line argument overriding the configured value
					my $max_pages = $conf->{crawl}{max_pages} || 10;
					$max_pages = $opt_maxpages if $opt_maxpages_set;
					# initialize the queue with the configured routes
					$hashref->{byRole}{$role}{queue} = $conf->{roles}{$role}{routes} || [ '/' ];

					# and crawl until the queue is empty
					#print STDERR "queue ".Dumper( $hashref->{byRole}{$role}{queue} );
					while ( @{$hashref->{byRole}{$role}{queue}} ){
						doCompareQueuedItem( $role );
						last if $hashref->{byRole}{$role}{visited} >= $max_pages;
					}

					# write sitemap JSON (and CSV if asked)
					my $json_path = "$hashref->{byRole}{$role}{roledir}/results/sitemap.json";
					open my $J, '>:utf8', $json_path or die "open $json_path: $!";
					print {$J} encode_json( $hashref->{byRole}{$role}{sitemap} );
					close $J;

					if( $conf->{crawl}{make_sitemap_csv} ){
						my $csv_path = "$hashref->{byRole}{$role}{roledir}/results/sitemap.csv";
						open my $C, '>:utf8', $csv_path or die "open $csv_path: $!";
						print {$C} join(',', qw( path depth status_ref status_new type_ref type_new links_found shot_ref shot_new)), "\n";
						for my $row ( @{$hashref->{byRole}{$role}{sitemap}} ){
							print {$C} join(',', map { make_csv($_) } @{$row}{qw(path depth status_ref status_new type_ref type_new links_found shot_ref shot_new)}), "\n";
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
# Compare two websites for the given role and the given route

sub doCompareQueuedItem {
	my ( $role ) = @_;

	# get the next item from the queue, either a single string (a configured route) or an array with its depth
	my ( $path, $depth ) = do {
		my $item = shift @{$hashref->{byRole}{$role}{queue}};
		ref( $item ) eq 'ARRAY' ? @$item : ( $item, 0 );
	};
	# return if already seen before
	# Otherwise, if we’ve seen this path only at a deeper depth, we’ll overwrite with the shallower one.
	return if $hashref->{byRole}{$role}{seen}{$path} && $hashref->{byRole}{$role}{seen}{$path} <= $depth;
	# else it is seen
	msgVerbose( "doCompareQueuedItem() $path" );
	$hashref->{byRole}{$role}{seen}{$path} = $depth;

	# do not override the configured max depth
	last if $depth > $hashref->{run}{max_depth};

	# get and compare
	my $host_ref = URI->new( $conf->{bases}{ref} )->host;
	my $url_ref = $conf->{bases}{ref}.$path;
	my $url_new = $conf->{bases}{new}.$path;
	my $basename = $path;
	$basename =~ s![/\.]!_!g;

	my $html_ref = sprintf "%s/ref_%s_%06d.html", "$hashref->{byRole}{$role}{roledir}/htmls", $basename, $hashref->{byRole}{$role}{visited}+1;
	my $html_new = sprintf "%s/new_%s_%06d.html", "$hashref->{byRole}{$role}{roledir}/htmls", $basename, $hashref->{byRole}{$role}{visited}+1;
	my $shot_ref = sprintf "%s/ref_%s_%06d.png", "$hashref->{byRole}{$role}{roledir}/screenshots", $basename, $hashref->{byRole}{$role}{visited}+1;
	my $shot_new = sprintf "%s/new_%s_%06d.png", "$hashref->{byRole}{$role}{roledir}/screenshots", $basename, $hashref->{byRole}{$role}{visited}+1;
	my $shot_diff = sprintf "%s/diff_%s_%06d.png", "$hashref->{byRole}{$role}{roledir}/screenshots", $basename, $hashref->{byRole}{$role}{visited}+1;
	my $capture_ref = navigate_and_capture( $hashref->{byRole}{$role}{drivers}{ref}, $url_ref, screenshot => $shot_ref, fullpage => true, html => $html_ref );
	my $capture_new = navigate_and_capture( $hashref->{byRole}{$role}{drivers}{new}, $url_new, screenshot => $shot_new, fullpage => true, html => $html_new );

	is( $capture_new->{status}, 200, "[$role ($path)] new website returns '200' status code" );
	is( $capture_new->{status}, $capture_ref->{status}, "[$role ($path)] got same status code ($capture_new->{status})" );

	# increment the visited count (before, maybe, going to next path)
	#  but anyway just after havoing actually visited the page!
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

	my @errs = ();
	is( lc( $capture_ref->{content_type} // ''), lc( $capture_new->{content_type} // ''), "[$role ($path)] got same content-type (".lc( $capture_ref->{content_type} // '').")" )
		|| push( @errs, "content-type" );
	is( $capture_ref->{dom_hash}, $capture_new->{dom_hash}, "[$role ($path)] sanitized DOM hashes matches ($capture_ref->{dom_hash})" )
		|| push( @errs, "DOM hashes" );
	is( $capture_ref->{alert}, '', "[$role ($path)] no ref alert" )
		|| push( @errs, "ref alert: $capture_ref->{alert}" );
	is( $capture_new->{alert}, '', "[$role ($path)] no new alert" )
		|| push( @errs, "new alert: $capture_new->{alert}" );

	# optional visual diff
	# Which align should you use?
	# 	crop (default): safest with your stitched full-page shots (they should be same width and very close in height; compares the overlapping area only).
	#	pad: if one page is slightly taller (e.g., a banner present on one env), pad the shorter one with white for a full-height comparison.
	#	resize: if widths differ due to different breakpoints (less common in your setup). It scales both to a common width first, then compares.
	if( $conf->{visual}{enabled} ){
		my $threshold = $conf->{visual}{rmse_fail_threshold} || 0.01;
		if( false ){
			my $rmse = screenshot_rmse( $shot_ref, $shot_new );
			ok( $rmse <= $threshold, "[$role ($path)] visual RMSE=$rmse" );
		}
		my $res = compare_screenshots_rmse(
			a         => $shot_ref,
			b         => $shot_new,
			diff_out  => $shot_diff,
			align     => 'crop',      # or 'pad' / 'resize'
			fuzz      => '5%',
			# resize_width => 1366,   # only if align => 'resize'
		);
		my $rmse = $res->{rmse};
		ok( $rmse <= $threshold, "[$role ($path)] visual RMSE=$rmse" )
			|| push( @errs, "RMSE=$rmse" );
	}

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

	# record sitemap entry
	record_sitemap_entry( $role, {
		path          => $path,
		depth         => $depth,
		capture_ref   => $capture_ref,
		html_ref      => $html_ref,
		shot_ref      => $shot_ref,
		capture_new   => $capture_new,
		html_new      => $html_new,
		shot_new      => $shot_new,
		next_paths    => \@next_paths,
		errs          => \@errs,
		full          => true
	});
}

# -------------------------------------------------------------------------------------------------
# Compare two websites for the given role and the given route

sub doCompareRoute {
	my ( $role, $route ) = @_;
	msgOut( "    role='$role': working on '$route', route..." );
	$hashref->{byRole}{$role}{routes}{$route} = {};
	# compute url for this route
	my $url_ref = $conf->{bases}{ref} . $route;
    my $url_new = $conf->{bases}{new} . $route;
	# get the page and validate the status code and the content type
	# first version: doesn't work
	if( false ){
	    my ( $code_ref, $ct_ref ) = http_meta( $url_ref );
    	my ( $code_new, $ct_new ) = http_meta( $url_new );
	}
	# second version: ok for a single page
	if( false ){
		my $capture_ref = navigate_and_capture( $hashref->{byRole}{$role}{drivers}{ref}, $url_ref );
		my $capture_new = navigate_and_capture( $hashref->{byRole}{$role}{drivers}{new}, $url_new );
		is( $capture_new->{status}, 200, "[$role ($route)] new website returns '200' status code" );
    	is( $capture_new->{status}, $capture_ref->{status}, "[$role ($route)] 'got same status code ($capture_new->{status})" );
    	is( lc( $capture_ref->{content_type} // ''), lc( $capture_new->{content_type} // ''), "[$role ($route)] got same content-type (".lc( $capture_ref->{content_type} // '').")" );
    	is( $capture_ref->{dom_hash}, $capture_new->{dom_hash}, "[$role ($route)] sanitized DOM hashes matches ($capture_ref->{dom_hash})" );
	}
}

# -------------------------------------------------------------------------------------------------
# clear old perf logs before a new nav

sub drain_perf_logs {
    my ( $driver ) = @_;
    eval { $driver->get_log('performance') for 1..2 };  # swallow/ignore
}

# -------------------------------------------------------------------------------------------------
# Execute JS (sync) via W3C endpoint (no SRD quirks)

sub exec_js_w3c_sync {
    my ( $host,$port,$base,$sid,$script,$args ) = @_;
    my $http = HTTP::Tiny->new(timeout => 20);
    my $url = "http://$host:$port$base/session/$sid/execute/sync";
    my $res = $http->post($url, {
        headers => { 'Content-Type' => 'application/json' },
        content => encode_json({ script => $script, args => $args // [] }),
    });
    die "exec_js_w3c_sync failed: $res->{status} $res->{reason}\n$res->{content}\n"
        unless $res->{success};
    return decode_json( $res->{content} )->{value};
}

# -------------------------------------------------------------------------------------------------
# Extract links while excluding regions that match CSS selectors

sub extract_links {
    my ( $html, $base_url, $cfg_crawl ) = @_;
    my $dom = Mojo::DOM->new($html);

    # remove excluded regions from DOM before link harvest
    for my $sel ( @{ $cfg_crawl->{exclude_selectors} // [] } ){
        $dom->find($sel)->each(sub { $_->remove });
    }

    my %uniq;
	my $finders = $cfg_crawl->{find_links} || [{ find => 'a[href]', member => 'href' }];
	foreach my $it ( @{$finders} ){
		$dom->find( $it->{find} )->each( sub {
			my $href = $_->{$it->{member}} // return;
			$href =~ s/^\s+|\s+$//g;
			return if $href eq '' || $href =~ m/^javascript:|^mailto:|^tel:/i;

			my $abs = URI->new_abs( $href, $base_url )->as_string;
			$uniq{$abs} = true;
		});
	}

    return [ sort keys %uniq ];
}

# -------------------------------------------------------------------------------------------------
# make a full page (not viewport) screenshot whatever be the running browser type

sub fullpage_screenshot_scroll_stitch {
    my ( %o ) = @_;
    my ( $host, $port, $base, $sid, $driver, $outfile ) = @o{qw/host port base session_id driver outfile/};
	msgVerbose( "screenshoting to $outfile" );
    my $overlap  = $o{overlap_px} // 80;
    my $pause_ms = $o{pause_ms} // 150;
    my $max_seg  = $o{max_segments} // 200;

    # 1) Measure
    my $vh = exec_js_w3c_sync( $host,$port,$base,$sid, 'return window.innerHeight;', [] );
    my $vw = exec_js_w3c_sync( $host,$port,$base,$sid, 'return window.innerWidth;',  [] );
    my $doc_h = exec_js_w3c_sync( $host,$port,$base,$sid, q{
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
        exec_js_w3c_sync( $host,$port,$base,$sid, 'window.scrollTo(0, arguments[0]); return true;', [$y] );
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

sub handle_alert_if_present {
    my ( $sid, $action ) = @_;          # $action: 'accept' | 'dismiss'
    my $txt = alert_text_w3c( $sid );
	return undef if !$txt;
    msgWarn( "got Alert '$txt'" );
    $action && $action eq 'dismiss' ? alert_dismiss_w3c( $sid ) : alert_accept_w3c( $sid );
    return $txt;
}

# -------------------------------------------------------------------------------------------------
# load a page
# returns the status and the content type
# NO MORE USED - but kept as an example (see navigate_and_capture()).

sub http_meta {
	my ( $url ) = @_;
	my $http = HTTP::Tiny->new( timeout => 20 );
	my $res = $http->get( $url );
	return ( $res->{status}, lc( $res->{headers}{'content-type'} // '' ));
}

# -------------------------------------------------------------------------------------------------

sub json_array {
	'[' . join(',', map { "'$_'" } @_) . ']';
}

# -------------------------------------------------------------------------------------------------
# load the JSON configuration file
# check main data

sub load_config {
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
						foreach my $re ( @{$Const->excluded_cookies} ){
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

sub navigate_and_capture {
    my ( $driver, $url, %opt ) = @_;
    # %opt:
    #   screenshot => '/path/to/file.png'   (optional)
    #   fullpage   => 0|1                   (optional, default 0)
    #   html       => '/path/to/page.html'  (optional)

    # Drain logs so we only parse events for THIS navigation
    drain_perf_logs( $driver );

	msgVerbose( "navigate_and_compare() url='$url'" );
    $driver->get( $url );
	my ( $ready, $alert ) = wait_for_body( $driver, 5 );
	if( !$ready ){
		msgWarn "Timeout waiting for document.body for $url";
		return undef;
	}
	msgVerbose( "page ready" );

    # Grab performance log entries and find the main Document response
    my $logs = eval { $driver->get_log( 'performance' ) } // ();
    my ( $status, $headers, $mime, $resp_url );
    for my $e ( @{$logs} ){
		#print STDERR "log ".Dumper( $e );
        my $msg = eval { decode_json( $e->{message} ) } || next;
        my $method = $msg->{message}{method} // next;
        next unless $method eq 'Network.responseReceived';
        my $p = $msg->{message}{params} || next;

        # We only care about the main document (not images/XHR)
        next unless ($p->{type} // '') eq 'Document';
        my $r = $p->{response} || next;

        # Keep the LAST Document response (after redirects)
        ( $status, $headers, $mime, $resp_url ) = (
            $r->{status},
            $r->{headers} || {},
            $r->{mimeType},
            $r->{url},
        );
    }

	# Optionally take a screenshot (viewport or full-page)
	# our current Selenium::Remote::Driver+ChromeDriver v139 doesn't let us inject JS into the execution path
	if( my $outfile = $opt{screenshot} ){
		if( $opt{fullpage} ){
			fullpage_screenshot_scroll_stitch(
				host       => $hashref->{run}{server},
				port       => $conf->{browser}{port},
				base       => $Const->{path},
				session_id => $driver->{session_id},
				driver     => $driver,
				outfile    => $outfile,
				overlap_px => 80,
				pause_ms   => 200,
			);
		} else {
			my $png_b64 = $driver->screenshot;
			open my $fh, '>:raw', $outfile or die "open $outfile: $!";
			print {$fh} decode_base64( $png_b64 );
			close $fh;
		}
    }

    # Sanitize + hash the rendered DOM
    #my $html = $driver->execute_script( $sanitize_js );
    #my $dom_hash = md5_hex( $html // '' );
	my ( $html, $dom_hash ) = sanitize_and_hash_perl( $driver, $conf );

	# optionally serialize the html
	if( my $outfile = $opt{html} ){
		open my $fh, '>:utf8', $outfile or die "open $outfile: $!";
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
		alert        => $alert || ''
    };
}

# -------------------------------------------------------------------------------------------------

sub normalize_url_path_query {
    my ( $abs_uri, $follow_query ) = @_;
    my $u = URI->new($abs_uri);
    $u->fragment( undef );
    return $follow_query ? $u->path_query : $u->path; # string
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
# test in a page is loaded
# BUT: You’re hitting a known SRD quirk: in W3C mode it’s still calling the legacy endpoints
# (/execute_async instead of /execute/async), so ChromeDriver rejects it. Rather than fighting that,
# just avoid JS execution entirely for your “page is ready” check.
# NO MORE USED

sub ready_state_complete {
    my ( $driver ) = @_;
    my $state = eval {
        $driver->execute_async_script(
            'arguments[arguments.length - 1](document.readyState);'
        );
    };
    return ($@) ? undef : ( $state && $state eq 'complete' );
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
		path          => $data->{path},
		depth         => $data->{depth},
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
		$parms->{links_found} = scalar( @{$data->{next_paths}} );
		$parms->{next_paths} = $data->{next_paths};
		$parms->{shot_ref} = $data->{shot_ref};
		$parms->{shot_new} = $data->{shot_new};
		$parms->{html_ref} = $data->{html_ref};
		$parms->{html_new} = $data->{html_new};
		$parms->{errs} = $data->{errs};
		$parms->{alert} = $data->{alert};
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
    $dom->find('*')->each( sub {
        my $el = $_;
        my %attrs = %{ $el->attr // {} };
        for my $name ( keys %attrs ){
            if( grep { $name =~ $_ } @attr_rx ){
                $el->attr( $name => undef );           # remove attr
                next;
            }
            my $v = $attrs{$name};
            next unless defined $v;
            $v =~ s/\b\d{10}\b/<TS>/g;                 # unix timestamps
            $v =~ s/\bv=\w{6,}\b/v=<hash>/g;           # cache-busters
            $el->attr( $name => $v );
        }
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

sub screenshot_rmse {
	my ( $a, $b ) = @_;
	my $img1 = Image::Magick->new; $img1->Read( $a );
	my $img2 = Image::Magick->new; $img2->Read( $b );
	my ( $diff, $metric ) = $img1->Compare( image => $img2, metric => 'RMSE', fuzz => '5%%' );
	return $metric // 0;
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
# Wait for the body is ready
# returns an array:
# - true|false whether the body is found (the page is ready)
# - alert text or empty

sub wait_for_body {
    my ( $driver, $timeout ) = @_;
    my $t0 = time;
	$timeout //= 10;
	my $alert = '';
    while ( time - $t0 < $timeout ){
        my $el = eval { $driver->find_element_by_css( 'body' ) };
		msgVerbose( "wait_for_body() got el=$el" );
		if( !$el ){
    		$alert = handle_alert_if_present( $driver->{session_id}, 'accept' );
		}
        return ( true, $alert ) if $el;
        select undef, undef, undef, 0.2;	# small wait before retry
    }
    return ( false, $alert );
}

# -------------------------------------------------------------------------------------------------
# Wait for a specific cookie to exist; returns the cookie hashref

sub wait_for_cookie {
    my ( $driver, $cookie_name, $timeout ) = @_;
    return wait_until(
        timeout  => $timeout // 10,
        interval => 0.2,
        cond     => sub { $driver->get_cookie_named($cookie_name) }
    );
}

# -------------------------------------------------------------------------------------------------
# Wait for a DOM element (CSS selector); returns the element

sub wait_for_element {
    my ( $driver, $css, $timeout ) = @_;
    return wait_until(
        timeout  => $timeout // 10,
        interval => 0.2,
        cond     => sub {
            my $el = eval { $driver->find_element($css, 'css') };
            $@ ? undef : $el;
        },
    );
}

# -------------------------------------------------------------------------------------------------
# Wait for an in-page JS condition to be true; returns JS value

sub wait_for_js_true {
    my ( $driver, $js_expr, $timeout ) = @_;
    return wait_until(
        timeout  => $timeout // 10,
        interval => 0.2,
        cond     => sub {
            # execute_script returns the JS value; truthy means we're done
            my $v = eval { $driver->execute_script("return ($js_expr);") };
            $@ ? undef : ($v ? $v : undef);
        },
    );
}

# -------------------------------------------------------------------------------------------------
# Wait for URL to change from a known value

sub wait_for_url_change {
    my ( $driver, $old_url, $timeout ) = @_;
    return wait_until(
        timeout  => $timeout // 10,
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
    my $timeout = $opt{timeout} // 10;    # seconds
    my $interval = $opt{interval} // 0.2;   # seconds
    my $start = time;
    while( time - $start < $timeout ){
        my $val = eval { $cond->() };
        return $val if $val;
        sleep $interval;
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
	load_config( $opt_jsonfile );
	$conf = compile_url_patterns( $conf );
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
