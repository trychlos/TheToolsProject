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
use File::Copy qw( move );
use File::Path qw( make_path );
use File::Spec;
use File::Temp;
use Image::Compare;
use Mojo::DOM;
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
# - the current queue item
# (O):
# - returns the basename to be considered when writing a file
#   the final basename is built like '000006_new__fo_if_0#content-frame#_bo_fo#_bo_person_home_if_1#details-frame##_if_2#ifDbox##___html[1]_body[1]_div[1]_div[1]_div[1]_div[1]_div[1]_ul[1]_li[2]_a[1].png'
#                                     counter|which|path|                    state_key                                         | xpath
#   counter and which are added by the caller
#   we provide here the 'path|state_key|xpath' part

sub _bname {
	my ( $self, $queue_item ) = @_;

	my $path = $self->browser()->current_path();
	my $state = $self->browser()->state_get_key();
	# remove the topHref part
	my @w = split( /\|/, $state );
	shift( @w );
	my $xpath = $queue_item->isClick() ? $queue_item->xpath() : '';

	my $bname = join( "|", $path, @w, $xpath );
	$bname =~ s![/\.\|:]!_!g;

	return $bname;
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
#   > counter: a counter
#   > item: the current queue item
#   > add: a suffix to be added, defaulting to ''
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

	# must have same content-type
	is( lc( $self->content_type() // ''), lc( $other->content_type() // ''), "[$role ($path)] got same content-type (".lc( $self->content_type() // '').")" )
		|| push( @errs, "content-type" );
	# must have same DOM hash
	is( $self->dom_hash(), $other->dom_hash(), "[$role ($path)] sanitized DOM hashes matches (".$self->dom_hash().")" )
		|| push( @errs, "DOM hash" );
	# must not have any alert from reference site
	ok( !scalar( @{ $self->alerts() }), "[$role ($path)] no alert from ref site" )
		|| push( @errs, "ref alerts: ".join( ' | ', @{ $self->alerts() }));
	# must not have any alert from new site
	ok( !scalar( @{$other->alerts() }), "[$role ($path)] no alert from new site" )
		|| push( @errs, "new alerts: ".join( ' | ', @{$other->alerts() }));

	# optional visual diff
	if( $self->browser()->conf()->compareScreenshotsEnabled()){

		# Which align should you use?
		# 	crop (default): safest with your stitched full-page shots (they should be same width and very close in height; compares the overlapping area only).
		#	pad: if one page is slightly taller (e.g., a banner present on one env), pad the shorter one with white for a full-height comparison.
		#	resize: if widths differ due to different breakpoints (less common in your setup). It scales both to a common width first, then compares.
		#my $ref = 
		#my $new = $new->browser()->screenshot();
		#my $threshold = $self->browser()->conf()->compareScreenshotsRmse();
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
		my $threshold = $self->browser()->conf()->compareScreenshotsRmse() * 441.67;
		my $maxcount = $self->browser()->conf()->compareThresholdCount();

		# try some methods
		# threshold seems to be a bit too exact - even 5% detect non-visible differences
		#$cmp->set_method( method => &Image::Compare::THRESHOLD, args => $threshold );
		#my $res = $cmp->compare();
		#print STDERR "threshold: ".Dumper( $res );
		#ok( $res, "[$role ($path)] screenshots threshold comparison is OK" )
		#	|| push( @errs, "screenshot_threshold" );

		$cmp->set_method( method => &Image::Compare::THRESHOLD_COUNT, args => $threshold );
		my $res = $cmp->compare();
		#print STDERR "threshold_count: ".Dumper( $res );
		ok( $res <= $maxcount, "[$role ($path)] screenshots threshold_count '$res <= $maxcount' is OK" )
			|| push( @errs, "screenshot_threshold_count" );

		# avg_threshold is a boolean - useless here
		#$cmp->set_method( method => &Image::Compare::AVG_THRESHOLD, args => { type  => &Image::Compare::AVG_THRESHOLD::MEAN, value => 35 });
		#$res = $cmp->compare();
		#print STDERR "avg_threshold: ".Dumper( $res );
		#ok( $res, "[$role ($path)] screenshots avg_threshold comparison is OK" )
		#	|| push( @errs, "screenshot_avg_threshold" );

		# if we detect a difference, and have a 'diff' directory, then keep the screenshots
		if( !$res && $args->{diff} ){
			#my $fref = File::Spec->catfile( $args->{diff}, sprintf( "%06d_ref_%s.png", $args->{counter}, $self->_bname( $args->{item} )));
			#move( $tmpref, $fref );
			#my $fnew = File::Spec->catfile( $args->{diff}, sprintf( "%06d_new_%s.png", $args->{counter}, $self->_bname( $args->{item} )));
			#move( $tmpnew, $fnew );
			#msgVerbose( "keeping diff screenshots in '$fref' and '$fnew'" );

		# unlink temporary files
		} else {
			if( $isreftmp ){
				unlink( $dumpref );
				msgVerbose( "unlinking '$dumpref'" );
			}
			if( $isnewtmp ){
				unlink( $dumpnew );
				msgVerbose( "unlinking '$dumpnew'" );
			}
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

    # remove excluded regions from DOM before link harvest
	my $excluded = $self->browser()->conf()->crawlExcludeSelectors();
    for my $sel ( @{ $excluded // [] } ){
        $dom->find( $sel )->each( sub { $_->remove });
    }

    my %uniq;
	my $finders = $self->browser()->conf()->crawlFindLinks() || [{ find => 'a[href]', member => 'href' }];

	my $wants_same_host = $self->browser()->conf()->crawlSameHost();
	my $host_ref = URI->new( $self->browser()->urlBase())->host;

	foreach my $it ( @{$finders} ){
		$dom->find( $it->{find} )->each( sub {
			my $href = $_->attr( $it->{member} ) // return;
			$href =~ s/^\s+|\s+$//g;
			return if $href eq '' || $href =~ m/^javascript:|^mailto:|^tel:|\.xls$/i;

			my $abs = URI->new_abs( $href, $self->browser()->urlBase())->as_string;
			# honor same host
			return if $wants_same_host && !TTP::HTTP::Compare::Utils::same_host( $abs, $host_ref );

			$uniq{$abs} = true;
		});
	}

    return [ sort keys %uniq ];
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
# (I):
# - an arguments hash with following keys:
#   > dir: the root output directory for the role, defaulting to standard temp dir
#   > counter: a counter, defaulting to the queue_item->visited() one
#   > item: the current queue item
#   > add: a suffix to be added, defaulting to ''

sub writeHtml {
    my ( $self, $args ) = @_;

	my $which = $self->browser()->which();
	my $subdirs = $self->browser()->conf()->var([ 'dirs', $which, 'htmls' ]) // "$which/htmls";
	if( $subdirs ){
		my @dirs = File::Spec->splitdir( $subdirs );
		my $fdir = File::Spec->catdir( $args->{dir} || File::Temp->tempdir(), @dirs );
		make_path( $fdir );
		my $suffix = $args->{add} || '';
		$suffix = "_$suffix" if $suffix;
		my $counter = $args->{counter} // $args->{item}->visited() // 0;
		my $fname = File::Spec->catfile( $fdir, sprintf( "%06d_%s_%s%s.html", $counter, $which, $self->_bname( $args->{item} ), $suffix ));
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
# - an arguments hash with following keys:
#   > dir: the root output directory for the role, defaulting to standard temp dir
#   > counter: a counter
#   > item: the current queue item
#   > add: a suffix to be added, defaulting to ''

sub writeScreenshot {
    my ( $self, $args ) = @_;

	my $which = $self->browser()->which();
	my $subdirs = $self->browser()->conf()->var([ 'dirs', $which, 'screenshots' ]) // "$which/screenshots";
	if( $subdirs ){
		my @dirs = File::Spec->splitdir( $subdirs );
		my $fdir = File::Spec->catdir( $args->{dir} || File::Temp->tempdir(), @dirs );
		make_path( $fdir );
		my $suffix = $args->{add} || '';
		$suffix = "_$suffix" if $suffix;
		my $counter = $args->{counter} // $args->{item}->visited() // 0;
		my $fname = File::Spec->catfile( $fdir, sprintf( "%06d_%s_%s%s.png", $counter, $which, $self->_bname( $args->{item} ), $suffix ));
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
