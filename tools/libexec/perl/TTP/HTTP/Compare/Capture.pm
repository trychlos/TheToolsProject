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

package TTP::HTTP::Compare::Capture;
die __PACKAGE__ . " must be loaded as TTP::HTTP::Compare::Capture\n" unless __PACKAGE__ eq 'TTP::HTTP::Compare::Capture';

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Data::Dumper;
use File::Copy qw( copy move );
use File::Path qw( make_path );
use File::Spec;
use File::Temp;
use Image::Compare;
use List::Util qw( any );
use Mojo::DOM;
use Scalar::Util qw( blessed );
use Test::More;
use URI;

use TTP;
use vars::global qw( $ep );

use TTP::Constants qw( :all );
use TTP::HTTP::Compare::Utils;
use TTP::Message qw( :all );

use constant {
};

my $Const = {
};

### Private methods

# -------------------------------------------------------------------------------------------------
# (I):
# - whether we work for 'ref' or 'new' site
# - the current queue item
# - the desired extension
# - an arguments hash with following keys:
#   > counter: a counter, defaulting to the queue_item->visited() one
#   > suffix: a suffix to be added, defaulting to ''
# (O):
# - returns the filename

sub _fname {
	my ( $self, $which, $queue_item, $extension, $args ) = @_;
	$args //= {};

	# 1. a counter
	my $counter = $args->{counter} // $queue_item->visited() // 0;
	# 2. the which part, as-is
	# 3. a path part
	my $path = $self->browser()->current_path();
	# 4. the page signature without the URL
	my $signature = $self->browser()->signature();
	my @w = split( /\|/, $signature );
	shift( @w );	# remove the topHref part
	# 5. the current xpath
	my $xpath = $queue_item->isClick() ? $queue_item->xpath() : '';
	# maybe a suffix
	my $suffix = $args->{suffix} || '';
	$suffix = "_$suffix" if $suffix;
	# last build the filename
	my $fname = sprintf( "%06d_%s_%s%s%s", $counter, $which, join( "|", $path, @w, $xpath ), $suffix, $extension );
	$fname =~ s![/\|:"\*]!_!g;

	return $fname;
}

=pod
# -------------------------------------------------------------------------------------------------
# Compare two screenshots visually using RMSE.
# (I):
# - the other TTP::HTTP::Compare::Capture object
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

sub _screenshots_compare_rmse {
    my ( $self, $other, $args ) = @_;

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
# make a full page (not viewport) screenshot whatever be the running browser type

sub _screenshot_fullpage_scroll_stitch {
    my ( $self, $outfile ) = @_;
    my $overlap  = 80;
    my $pause_ms = 150;
    my $max_seg  = 200;

	my $browser = $self->browser();

    # 1) Measure
    my $vh = $browser->exec_js_w3c_sync( 'return window.innerHeight;', [] );
    my $vw = $browser->exec_js_w3c_sync( 'return window.innerWidth;',  [] );
    my $doc_h = $browser->exec_js_w3c_sync( q{
        return Math.max(
          document.documentElement.scrollHeight,
          document.body ? document.body.scrollHeight : 0,
          document.documentElement.offsetHeight,
          document.documentElement.clientHeight
        );
    }, []);
    $vh ||= 800;
	$vw ||= 1366;
	$doc_h ||= $vh;

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
        $browser->exec_js_w3c_sync( 'window.scrollTo(0, arguments[0]); return true;', [$y] );
        usleep( $pause_ms*1000 );
        my $png = $browser->viewport_png_bytes();
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
    $out->Write( $outfile );
}
=cut

# -------------------------------------------------------------------------------------------------
# Screenshot in a temporary file
# Re-use the already saved screenshots if ant
# (O):
# - the screenshot filename
# - whether this is a temp file

sub _temp_screenshot {
    my ( $self ) = @_;

	my $fname = undef;
	my $tmp = true;
	
	if( $self->{_hash}{screendump} ){
		$fname = $self->{_hash}{screendump};
		$tmp = false;
		msgVerbose( "reusing existing screeshot $fname" );

	} else {
		my $png = $self->browser()->screenshot();
		my $fh = File::Temp->new( UNLINK => false, SUFFIX => '.png' );
		binmode( $fh, ':raw' );
		print {$fh} $png;
		close $fh;
		$fname = $fh->filename();
		my $exists = ( -r $fname );
		msgVerbose( "creating temp screenshot '$fname' (exists=$exists)" );
	}

	return [ $fname, $tmp ];
}

# -------------------------------------------------------------------------------------------------
# Copy the different screenshots to the 'diff' dir
# This is a copy because:
# - we want keep original screenshots in their respective directories
# - eventual temmp files will be deleted later
# (I):
# - the ref screenshot
# - the new screenshot
# - an optional options hash with following keys:
#   > dir: the root output directory for the role, defaulting to standard temp dir
#   > item: the current queue item

sub _write_diffs {
    my ( $self, $ref, $new, $args ) = @_;
	$args //= {};

	my $subdirs = $self->browser()->conf()->dirsScreenshots( 'diffs' );
	if( $subdirs ){
		my @dirs = File::Spec->splitdir( $subdirs );
		my $fdir = File::Spec->catdir( $args->{dir} || File::Temp->tempdir(), @dirs );
		make_path( $fdir );
		$self->_write_diffs_which( $ref, $fdir, $args->{item}, 'ref' );
		$self->_write_diffs_which( $new, $fdir, $args->{item}, 'new' );
	}
}

# -------------------------------------------------------------------------------------------------
# Copy the provided file to the specified directory
# (I):
# - the filename to be copied
# - the output (existing) directory
# - the current queue item
# - whether we work for 'ref' or 'new' site

sub _write_diffs_which {
    my ( $self, $fref, $dir, $queue_item, $which ) = @_;

	my $fname = File::Spec->catfile( $dir, $self->_fname( $which, $queue_item, '.png' ));
	if( $fref eq $fname ){
		msgWarn( "cannot save '$fref' to same '$fname': you should review 'dirs.diffs' configuration" );
	} else {
		msgVerbose( "write_diffs() saving '$fref' to '$fname'" );
		copy( $fref, $fname );
	}
}

### Public methods

# -------------------------------------------------------------------------------------------------
# Returns the list of alerts

sub alerts {
    my ( $self ) = @_;

	return $self->{_hash}{alerts} || [];
}

# -------------------------------------------------------------------------------------------------
# Returns the initiating browser

sub browser {
    my ( $self ) = @_;

	return $self->{_browser};
}

# -------------------------------------------------------------------------------------------------
# Returns the content-type

sub content_type {
    my ( $self ) = @_;

	return $self->{_hash}{content_type};
}

# -------------------------------------------------------------------------------------------------
# Compare two captured documents.
# (I):
# - the capture from the new site (self being the reference one)
# - an optional options hash with following keys:
#   > dir: the root output directory for the role, defaulting to standard temp dir
#   > item: the current queue item
# (O):
# - the result as a ref to an array of error messages

sub compare {
    my ( $self, $other, $args ) = @_;
	$args //= {};
	msgVerbose( "compare() entering" );

	my $result = {};

	my $path = $self->browser()->urlPath();
	my $role = $self->browser()->role()->name();
	my @errs = ();

	# compare rendered HTMLs if configured
	if( $self->browser()->conf()->confCompareHtmlsEnabled()){
		# must have same content-type
		is( lc( $self->content_type() // ''), lc( $other->content_type() // ''), "[$role ($path)] got same content-type (".lc( $self->content_type() // '').")" )
			|| push( @errs, "content-type" );
		# must have same DOM hash
		is( $self->dom_hash(), $other->dom_hash(), "[$role ($path)] sanitized DOM hashes matches (".$self->dom_hash().")" )
			|| push( @errs, "DOM hash" );
	}

	# must not have any alert from reference site
	ok( !scalar( @{ $self->alerts() }), "[$role ($path)] no alert from ref site" )
		|| push( @errs, "ref alerts: ".join( ' | ', @{ $self->alerts() }));
	# must not have any alert from new site
	ok( !scalar( @{$other->alerts() }), "[$role ($path)] no alert from new site" )
		|| push( @errs, "new alerts: ".join( ' | ', @{$other->alerts() }));

	# optional visual diff
	if( $self->browser()->conf()->confCompareScreenshotsEnabled()){

		# Which align should you use?
		# 	crop (default): safest with your stitched full-page shots (they should be same width and very close in height; compares the overlapping area only).
		#	pad: if one page is slightly taller (e.g., a banner present on one env), pad the shorter one with white for a full-height comparison.
		#	resize: if widths differ due to different breakpoints (less common in your setup). It scales both to a common width first, then compares.
		#my $ref = 
		#my $new = $new->browser()->screenshot();
		#my $threshold = $self->browser()->conf()->confCompareScreenshotsRmse();
		#my $res = $self->_compare_screenshots( $other, 
		#	a         => $capture_ref->{shotdump},
		#	b         => $capture_new->{shotdump},
		#	diff_out  => $opts->{diff},
		#	align     => 'crop',      # or 'pad' / 'resize'
		#	fuzz      => '5%',
		#	threshold => $threshold,
		#	# resize_width => 1366,   # only if align => 'resize'
		#);
		#my $rmse = $res->{rmse};
		#ok( $rmse <= $threshold, "[$role ($path)] visual RMSE=$rmse" )
		#	|| push( @errs, "RMSE=$rmse" );

		# Image::Compare wants image files, so have to temporarily dump screenshots somewhere if we do not already have recorded a dump
		# rmse threshold can be configured as a percent, to be closed of Image::Compare which uses 255*sqrt( 3 ) ~ 441.67
		#  we also can define an accepted diffs count
		my ( $dumpref, $isreftmp ) = @{ $self->_temp_screenshot() };
		my ( $dumpnew, $isnewtmp ) = @{ $other->_temp_screenshot() };
		my $cmp = Image::Compare->new();
		$cmp->set_image1( img => $dumpref, type => 'png' );
		$cmp->set_image2( img => $dumpnew, type => 'png' );
		my $threshold = $self->browser()->conf()->confCompareScreenshotsRmse() * 441.67;
		my $maxcount = $self->browser()->conf()->confCompareScreenshotsThresholdCount();

		# try some methods
		# threshold seems to be a bit too exact - even 5% reports non-visible differences
		# avg_threshold is a boolean - useless here

		# counting the differences seems usable:
		# non visible differences may count until 75 or less
		# one line diff counts for more than 10000
		$cmp->set_method( method => &Image::Compare::THRESHOLD_COUNT, args => $threshold );
		my $res = $cmp->compare();
		#print STDERR "threshold_count: ".Dumper( $res );
		if( !ok( $res <= $maxcount, "[$role ($path)] screenshots threshold_count '$res <= $maxcount' is OK" )){
			push( @errs, "screenshot_threshold_count" );
			$self->_write_diffs( $dumpref, $dumpnew, $args );
		}	

		# unlink temporary files
		if( $isreftmp ){
			unlink( $dumpref );
			msgVerbose( "unlinking '$dumpref'" );
		}
		if( $isnewtmp ){
			unlink( $dumpnew );
			msgVerbose( "unlinking '$dumpnew'" );
		}
	}

	return \@errs;
}

# -------------------------------------------------------------------------------------------------
# Returns the DOM hash

sub dom_hash {
    my ( $self ) = @_;

	return $self->{_hash}{dom_hash};
}

# -------------------------------------------------------------------------------------------------
# Extract links while excluding regions that match CSS selectors
# Honors the same_host configuration
# (O):
# - returns the list of uniq links as a ref to a sorted array

sub extract_links {
    my ( $self ) = @_;

    my $dom = Mojo::DOM->new( $self->html());
	my $conf = $self->browser()->conf();

    my %uniq;
	my $finders = $conf->confCrawlByLinkFinders();
	my $wants_same_host = $conf->confCrawlSameHost();
	my $url_base = $self->browser()->urlBase();
	my $host_ref = URI->new( $url_base )->host;
	my $honor_query = $conf->confCrawlByLinkHonorQuery();

	# '$finders' is configured to address all the links of the page (mostly when there is some 'href' inside)
	foreach my $it ( @{$finders} ){
		$dom->find( $it->{find} )->each( sub {
			my $href = $_->attr( $it->{member} ) // return;
			$href =~ s/^\s+|\s+$//g;
			#return if $href eq '' || $href =~ m/^javascript:|^mailto:|^tel:|\.xls$/i;
			return if !$href;
			# apply href inclusions/exclusions
			return unless $self->_extract_links_href_allowed( $it, $href );
			# whether to follow only the path or also the query fragment
			my $u = URI->new( $href );
			$u->fragment( undef );
			my $p = $u->can( 'path_query' ) ? ( $honor_query ? $u->path_query : $u->path ) : $u->path;
			# compute an absolute url
			my $abs = URI->new_abs( $p, $url_base )->as_string;
			# apply url inclusions/exclusions
			return unless $self->_extract_links_url_allowed( $it, $abs );
			# honor same host
			return if $wants_same_host && !TTP::HTTP::Compare::Utils::same_host( $abs, $host_ref );

			$uniq{$abs} = true;
		});
	}

    return [ sort keys %uniq ];
}

# -------------------------------------------------------------------------------------------------
# (I):
# - the finder item
# - the candidate url
# (O):
# - whether the href is allowed to be crawled

sub _extract_links_href_allowed {
	my ( $self, $finder, $href ) = @_;

	my $conf = $self->browser()->conf();

    # Deny first
	my $denied = $conf->runCrawlByLinkHrefDenyPatterns() || [];
    if( scalar( @{$denied} )){
        if( any { $href =~ $_ } @{ $denied } ){
			#msgVerbose( "extract_links_allowed() '$href' denied by regex" );
			return false;
		}
    }

    # If no allow patterns provided/compiled -> allow everything (default)
    return true if $conf->runCrawlByLinkHrefAllowedAll();

    # Else require at least one allow match
    return any { $href =~ $_ } @{ $conf->runCrawlByLinkHrefAllowPatterns() };
}

# -------------------------------------------------------------------------------------------------
# (I):
# - the finder item
# - the candidate url
# (O):
# - whether the url is allowed to be crawled

sub _extract_links_url_allowed {
	my ( $self, $finder, $url ) = @_;

	my $conf = $self->browser()->conf();

    # Deny first
	my $denied = $conf->runCrawlByLinkUrlDenyPatterns() || [];
    if( scalar( @{$denied} )){
        if( any { $url =~ $_ } @{ $denied } ){
			#msgVerbose( "extract_links_allowed() '$url' denied by regex" );
			return false;
		}
    }

    # If no allow patterns provided/compiled -> allow everything (default)
    return true if $conf->runCrawlByLinkUrlAllowedAll();

    # Else require at least one allow match
    return any { $url =~ $_ } @{ $conf->runCrawlByLinkUrlAllowPatterns() };
}

# -------------------------------------------------------------------------------------------------
# Returns the HTTP status

sub status {
    my ( $self ) = @_;

	return $self->{_hash}{status};
}

# -------------------------------------------------------------------------------------------------
# Returns the (sanitized) HTML document

sub html {
    my ( $self ) = @_;

	return $self->{_hash}{html};
}

# -------------------------------------------------------------------------------------------------
# Write the HTML file
# (I)
# - the current queue item
# - an arguments hash with following keys:
#   > dir: the root output directory for the role, defaulting to standard temp dir
#   > counter: a counter, defaulting to the queue_item->visited() one
#   > suffix: a suffix to be added, defaulting to ''

sub writeHtml {
    my ( $self, $queue_item, $args ) = @_;

	if( !$queue_item || !blessed( $queue_item ) || !$queue_item->isa( 'TTP::HTTP::Compare::QueueItem' )){
		msgErr( "unexpected queue item: ".TTP::chompDumper( $queue_item ));
		TTP::stackTrace();
	}

	my $which = $self->browser()->which();
	my $subdirs = $self->browser()->conf()->dirsHtmls( $which );
	if( $subdirs ){
		my @dirs = File::Spec->splitdir( $subdirs );
		my $fdir = File::Spec->catdir( $args->{dir} || File::Temp->tempdir(), @dirs );
		make_path( $fdir );
		my $fname = File::Spec->catfile( $fdir, $self->_fname( $which, $queue_item, '.html', $args ));
		msgVerbose( "dumping '$which' HTML to $fname" );
		open my $fh, '>:utf8', $fname or die "open $fname: $!";
		print {$fh} $self->{_hash}{html};
		close $fh;
		$self->{_hash}{htmldump} = $fname;
	} else {
		msgVerbose( "not writing HTML file as disabled by configuration" )
	}
}

# -------------------------------------------------------------------------------------------------
# Write the page screenshot
# (I):
# - the current queue item
# - an arguments hash with following keys:
#   > dir: the root output directory for the role, defaulting to standard temp dir
#   > counter: a counter
#   > suffix: a suffix to be added, defaulting to ''

sub writeScreenshot {
    my ( $self, $queue_item, $args ) = @_;

	if( !$queue_item || !blessed( $queue_item ) || !$queue_item->isa( 'TTP::HTTP::Compare::QueueItem' )){
		msgErr( "unexpected queue item: ".TTP::chompDumper( $queue_item ));
		TTP::stackTrace();
	}

	my $which = $self->browser()->which();
	my $subdirs = $self->browser()->conf()->var([ 'dirs', $which, 'screenshots' ]) // "$which/screenshots";
	if( $subdirs ){
		my @dirs = File::Spec->splitdir( $subdirs );
		my $fdir = File::Spec->catdir( $args->{dir} || File::Temp->tempdir(), @dirs );
		make_path( $fdir );
		my $fname = File::Spec->catfile( $fdir, $self->_fname( $which, $queue_item, '.png', $args ));
		msgVerbose( "writing '$which' page screenshot to $fname" );
		my $png = $self->browser()->screenshot();
		open my $fh, '>:raw', $fname or die "open $fname: $!";
		print {$fh} $png;
		close $fh;
		$self->{_hash}{screendump} = $fname;
	} else {
		msgVerbose( "not writing screenshot file as disabled by configuration" )
	}
}

### Class methods

# -------------------------------------------------------------------------------------------------
# Constructor
# (I):
# - the TTP::EP entry point
# - the initiating browser as a TTP::HTTP::Compare::Browser object
# - the data hash ref, with following keys:
#   > html: the captured (sanitized) HTML document
#   > dom_hash: the corresponding MD5 hash
#   > status: the HTTP status
#   > headers: the received headers as a hash ref
#   > content_type: the mime type, may be empty
#   > final_url: the page URL
#   > response_url: the URL from response event
#   > alerts: an array ref of triggered alerts, may be empty
# (O):
# - this object

sub new {
	my ( $class, $ep, $browser, $hash ) = @_;
	$class = ref( $class ) || $class;

	if( !$ep || !blessed( $ep ) || !$ep->isa( 'TTP::EP' )){
		msgErr( "unexpected ep: ".TTP::chompDumper( $ep ));
		TTP::stackTrace();
	}
	if( !$browser || !blessed( $browser ) || !$browser->isa( 'TTP::HTTP::Compare::Browser' )){
		msgErr( "unexpected browser: ".TTP::chompDumper( $browser ));
		TTP::stackTrace();
	}
	if( !$hash || ref( $hash ) ne 'HASH' ){
		msgErr( "unexpected hash: ".TTP::chompDumper( $hash ));
		TTP::stackTrace();
	}

	my $self = $class->SUPER::new( $ep );
	bless $self, $class;
	msgDebug( __PACKAGE__."::new()" );

	$self->{_browser} = $browser;
	$self->{_hash} = $hash;

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
