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

package TTP::Media;
die __PACKAGE__ . " must be loaded as TTP::Media\n" unless __PACKAGE__ eq 'TTP::Media';

use strict;
use utf8;
use warnings;

use Audio::Scan;
use Capture::Tiny qw( capture );
use Data::Dumper;
use Encode qw( decode );
use File::Basename;
use File::Find;
use File::Spec;
use JSON::PP;
use Scalar::Util qw( looks_like_number );

use TTP;
use vars::global qw( $ep );

use TTP::Constants qw( :all );
use TTP::Finder;
use TTP::Message qw( :all );
use TTP::Path;

my $Const = {
	# the threshold when checking count of packets
	durationThreshold => {
		minDuration => 600,
		minPackets => 1000
	},
	# the duration tolerance when checking video consistency
	durationTolerance => {
		video => 0.1,
		gstreamer => 0.1
	},
	# KDE Connect / Android /FAT32 filesystems do not like these characters
	forbiddenChars => {
		'\s*\?' => '',
		'\s*:' => ' -',
		'[<>\/\\\|]' => '',
		'"' => '\'',
		'\*' => '_'
	},
	# when sampling a video, the length of each try
	sampling => {
		count => 10,
		length => 60
	},
	# a list of known video extensions
	videoExtensions => [
		'.avi',
		'.m4v',
		'.mkv',
		'.mov',
		'.mp4',
		'.mpeg',
		'.mpg',
		'.ts',
		'.webm'
	],
	videoReasons => [
		{
			id => 'CONTAINER_UNSUPPORTED_FOR_REPAIR',
			format => "container format '%s' is not supported by timeline repair"
		},
		{
			id => 'FFMPEG_ERROR',
			format => '%s'
		},
		{
			id => 'FFPROBE_ERROR',
			format => '%s'
		},
		{
			id => 'GST_DURATION_DELTA',
			format => 'GStreamer duration=%ss confirms repairability'
		},
		{
			id => 'GST_ERROR',
			format => '%s'
		},
		{
			id => 'GST_REPAIR_ERROR',
			format => '%s'
		},
		{
			id => 'MEDIA_MIN_DURATION',
			format => 'video duration=\'%ss\' less than minimal requested=\'%ss\''
		},
		{
			id => 'STREAM_DIVX_PACKED',
			format => 'video stream #%s: divx_packed=\'true\' detected'
		},
		{
			id => 'STREAM_DIVX_SAMPLE',
			format => 'excessive bitstream confirmed at start=%ss'
		},
		{
			id => 'STREAM_DURATION_DELTA',
			format => 'video stream #%s: duration=%ss vs container=%ss'
		},
		{
			id => 'STREAM_DURATION_INVALID',
			format => 'video stream #%s: duration=\'%s\' is not valid'
		},
		{
			id => 'STREAM_PACKETS_INVALID',
			format => 'video stream #%s: count of packets is not valid: \'%s\''
		},
		{
			id => 'STREAM_PACKETS_THRESHOLD',
			format => 'video stream #%s: only %s packets for %ss container'
		},
		{
			id => 'STREAM_PACKETS_UNDEFINED',
			format => 'video stream #%s: count of packets is not defined'
		},
		{
			id => 'STREAM_UNSUPPORTED_FOR_REPAIR',
			format => "stream #%d: %s codec '%s' is not supported by timeline repair"
		}
	],
	# a list of regexps to be ignored when walking a tree
	walkingIgnore => {
		dirs => [
			'^\.Trash'
		]
	}
};

# have some constant short names
use constant {
	# check qualifiers
	BITSTREAM => 'BITSTREAM',
	DURATION => 'DURATION',
	TIMELINE => 'TIMELINE',
	# check statuses
	OK => 'OK',
	ERROR => 'ERROR',
	FINDINGS => 'FINDINGS',
	SUSPICIOUS => 'SUSPICIOUS',
	REPAIRABLE => 'REPAIRABLE',
	FAILED => 'FAILED'
};

# ------------------------------------------------------------------------------------------------
# Extracts from the path the album level
# our standard audio trees are set as ROOT/type/letter/artist/albums[/disc]/file
# (I):
# - the full file pathname
# - an optional options hash with following keys:
#   > level: the directory level where to find the album, defaulting to 6
# (O):
# - the album directory, which may be undef

sub albumFromPath {
	my ( $path, $opts ) = @_;
	$opts //= {};
	my $album = undef;

	my $level = 6;
	$level = $opts->{level} if defined $opts->{level};

	if( -d $path ){
		my @dirs = File::Spec->splitdir( $path );
		$album = $dirs[$level];
	} else {
		my ( $volume,$directories,$file ) = File::Spec->splitpath( $path );
		my @dirs = File::Spec->splitdir( $directories );
		$album = $dirs[$level];
	}

	return $album;
}

# ------------------------------------------------------------------------------------------------
# Extracts the album from a full scan
# (I):
# - the scan result
# (O):
# - the album, or undef

sub albumFromScan {
	my ( $scan ) = @_;

	my $value = undef;
	$value = $value || $scan->{tags}{TALB};		# MP3
	$value = $value || $scan->{tags}{ALB};		# MP4
	$value = $value || $scan->{tags}{ALBUM};	# FLAC
	print "albumFromScan() $scan->{path} ".Dumper( $scan->{tags} ) if !$value;
	#msgVerbose( "$scan->{path} album $value" ) if $value;

	return $value;
}

# ------------------------------------------------------------------------------------------------
# Extracts from the path the artist level
# our standard audio trees are set as ROOT/type/letter/artist/albums[/disc]/file
# (I):
# - the full file pathname
# - an optional options hash with following keys:
#   > level: the directory level where to find the artist, defaulting to 5
# (O):
# - the artist directory

sub artistFromPath {
	my ( $path, $opts ) = @_;
	$opts //= {};
	my $artist = undef;

	my $level = 5;
	$level = $opts->{level} if defined $opts->{level};

	if( -d $path ){
		my @dirs = File::Spec->splitdir( $path );
		$artist = $dirs[$level];
	} else {
		my ( $volume,$directories,$file ) = File::Spec->splitpath( $path );
		my @dirs = File::Spec->splitdir( $directories );
		$artist = $dirs[$level];
	}

	return $artist;
}

# ------------------------------------------------------------------------------------------------
# Extracts the artist from a full scan
# (I):
# - the scan result
# (O):
# - the artist, or undef

sub artistFromScan {
	my ( $scan ) = @_;

	my $value = undef;
	$value = $value || $scan->{tags}{TPE1};		# MP3
	$value = $value || $scan->{tags}{TPE2};
	$value = $value || $scan->{tags}{AART};		# MP4
	$value = $value || $scan->{tags}{ARTIST};	# FLAC
	print "artistFromScan() $scan->{path} ".Dumper( $scan->{tags} ) if !$value;
	#msgVerbose( "$scan->{path} artist $value" ) if $value;

	return $value;
}

# ------------------------------------------------------------------------------------------------
# Check that we have a working ffmpeg installation, and that ffmpeg knows about the provided fomats
# (I):
# - a ref to an array of file formats (which may be empty)
#   formats specifies the accepted formats
#   the first one is the preferred output, and must be available both as Decoder and Encoder, while others only need to be Decodable
# (O):
# - true if all provided formats are ok
# - may have incremented the global count of errors

sub checkFormats {
	my ( $formats ) = @_;
	my $ok = true;

	my $res = TTP::commandExec( "ffmpeg -formats" );

	if( !$res->{success} ){
		msgErr( $res->{results}[0]{stderr} );
		$ok = false;

	} elsif( !$formats || ref( $formats ) ne 'ARRAY' ){
		msgErr( __PACKAGE__."::checkformats() expects formats as an array ref, got ".( $formats ? ref( $formats ) : '(undef)' ));
		$ok = false;

	} else {
		my $stdout = $res->{results}[0]{stdout};
		my $first = true;
		foreach my $fmt ( @{$formats} ){
			my $found = checkFFmpegFormat( $fmt, $stdout );
			if( $found ){
				if( $first ){
					if( !$found->{encode} || !$found->{decode} ){
						my $str = "the first provided format '$fmt', must be both 'Decodable' and 'Encodable', but ffmpeg cannot ";
						$str .= "encode" if $found->{decode};
						$str .= "decode" if $found->{encode};
						$str .= "decode nor encode" if !$found->{encode} && !$found->{decode};
						$str .= " this one";
						msgErr( $str );
						$ok = false;
					}
				} elsif( !$found->{decode} ){
					msgErr( "ffmpeg cannot decode the '$fmt' format" );
					$ok = false;
				}
			} else {
				msgErr( "ffmpeg doesn't know about '$fmt' format" );
				$ok = false;
			}
			$first = false;
		}
	}

	return $ok;
}

# ------------------------------------------------------------------------------------------------
# Check that we have a working ffmpeg installation
# (I):
# - none
# (O):
# - true if ok
# - may have incremented the global count of errors

sub checkFFmpeg {
	my $ok = true;

	my $res = TTP::commandExec( "ffmpeg -h" );

	if( !$res->{success} ){
		if( $ep->runner()->dummy()){
			msgWarn( $res->{results}[0]{stderr} );
		} else {
			msgErr( $res->{results}[0]{stderr} );
		}
		$ok = false;
	}

	return $ok;
}

# ------------------------------------------------------------------------------------------------
# Get among the available ffmpeg formats the line which correspond to the given format
# (I):
# - the searched for format
# - a ref to the array of ffmpeg available formats
# (O):
# - the found line as a ref to a hash with following keys, or undef:
#   > decode: true of false
#   > encode: true of false
#   > suffix: the file suffix
#   > label: the file format label

sub checkFFmpegFormat {
	my ( $fmt, $formats ) = @_;
	my $found = undef;

	#  D.. = Demuxing supported
	#  .E. = Muxing supported
	#  ..d = Is a device
	#  ---
	# 012345
	# 0: space
	# 1: D.. = Demuxing supported
	# 2: .E. = Muxing supported
	# 3: ..d = Is a device
	# 4: space
	# 5- comma-separated list of formats
	# ?: space
	#    label
	# may have ' D   mov,mp4,m4a,3gp,3g2,mj2 QuickTime / MOV'
	my @res = grep( /[ ,]$fmt[ ,]/, @{$formats} );
	if( @res && scalar( @res )){
		if( scalar( @res ) > 1 ){
			msgWarn( "format '$fmt' provides several possibilities, considering only the first one" );
		}
		my $line = $res[0];
		$found = {};
		$found->{decode} = ( substr( $line, 1,1 ) eq "D" );
		$found->{encode} = ( substr( $line, 2,1 ) eq "E" );
		my $rest = substr( $line, 5 );
		my @words = split( /\s+/, $rest, 2 );
		my @sfxes = split( /,/, $words[0] );
		if( !grep( /$fmt/, @sfxes )){
			msgWarn( "unable to find back our desired '$fmt' format in ffmpeg output [ ".join( ', ', @sfxes )." ]" );
		}
		$found->{suffix} = $fmt;
		$found->{label} = $words[1];
	}

	return $found;
}

# ------------------------------------------------------------------------------------------------
# Check that we have a working ffprobe binary
# (I):
# - none
# (O):
# - true if ok
# - may have incremented the global count of errors

sub checkFFprobe {
	my $ok = true;

	my $res = TTP::commandExec( "ffprobe -version" );

	if( !$res->{success} ){
		if( $ep->runner()->dummy()){
			msgWarn( $res->{results}[0]{stderr} );
		} else {
			msgErr( $res->{results}[0]{stderr} );
		}
		$ok = false;
	}

	return $ok;
}

# ------------------------------------------------------------------------------------------------
# Check that we have a working gst-discoverer binary
# (I):
# - none
# (O):
# - true if ok
# - may have incremented the global count of errors

sub checkGstDiscoverer {
	my $ok = true;

	my $res = TTP::commandExec( "gst-discoverer-1.0 --help" );

	if( !$res->{success} ){
		if( $ep->runner()->dummy()){
			msgWarn( $res->{results}[0]{stderr} );
		} else {
			msgErr( $res->{results}[0]{stderr} );
		}
		$ok = false;
	}

	return $ok;
}

# ------------------------------------------------------------------------------------------------
# Check that we have a working gst-launch binary
# (I):
# - none
# (O):
# - true if ok
# - may have incremented the global count of errors

sub checkGstLaunch {
	my $ok = true;

	my $res = TTP::commandExec( "gst-launch-1.0 --version" );

	if( !$res->{success} ){
		if( $ep->runner()->dummy()){
			msgWarn( $res->{results}[0]{stderr} );
		} else {
			msgErr( $res->{results}[0]{stderr} );
		}
		$ok = false;
	}

	return $ok;
}

# ------------------------------------------------------------------------------------------------
# Check that a video is consistent (i.e. that all streams are consistently declared and identified)
# (I):
# - the video filename
# - an optional options hash with following keys:
#   > bitstream: whether to test for bitstream pathology, defaulting to true
#   > duration: whether to test for minimal duration, defaulting to -1 (disabled)
#   > timeline: whether to test for timeline pathology, defaulting to true
#   > displaySummary: whether to display a check summary per check type, defaulting to false
# (O):
# - a hash with following keys:
#   > status: OK, ERROR or FINDINGS
#   > reasons: an array ref of error reasons
#   > findings: a hash ref per done check:
#     - BITSTREAM: a hash with following keys:
#       > status: OK, SUSPICIOUS or REPAIRABLE
#       > reasons: an array ref of reasons
#     - DURATION: a hash with following keys:
#       > status: OK or FAILED
#       > reasons: an array ref of failed reasons
#     - TIMELINE: a hash with following keys:
#       > status: OK, SUSPICIOUS or REPAIRABLE
#       > reasons: an array ref of reasons
#   > info: the ffprobe informations

sub checkVideo {
	my ( $fname, $opts ) = @_;

	# set default values
	$opts //= {};
	$opts->{bitstream} //= true;
	$opts->{duration} //= -1;
	$opts->{timeline} //= true;
	$opts->{displaySummary} //= false;

	# prepare the returned result
	my $result = {
		status => OK,
		reasons => [],
		info => undef
	};
	if( $opts->{bitstream} ){
		$result->{findings}{BITSTREAM} = {
			status => OK,
			reasons => []
		};
	}
	if( $opts->{duration} > 0 ){
		$result->{findings}{DURATION} = {
			status => OK,
			reasons => []
		};
	}
	if( $opts->{timeline} ){
		$result->{findings}{TIMELINE} = {
			status => OK,
			reasons => []
		};
	}

	# if nothing to do, just return
	if( !$opts->{timeline} && !$opts->{bitstream} && $opts->{duration} < 0 ){
		msgWarn( "checkVideo() nothing to do for '$fname'" );
		return $result;
	}

	# first stage: cheap metadata check
	# if nothing suspicious is found: then cheap path ends here
	# status is OK or ERROR
	ffprobeInfo( $fname, $result );
	if( $result->{status} ne OK ){
		return $result;
	}

	my $qualifiers = checkVideoStage1( $result, $opts );
	return $result if $result->{status} ne FINDINGS;

	# any SUSPICIOUS media should have set a qualifier which determine
	# some more expensive tests to be done to confirm or infirm the suspicion
	# the status begins its life with 'OK'

	if( scalar( grep( /BITSTREAM/, @{$qualifiers} ))){
		checkVideoForBitstream( $result );
		checkVideoSummary( $result, BITSTREAM ) if $opts->{displaySummary};
	}

	# if minimal duration has been requested and is not satisfied, there is nothing we can do here to repair
	# just keep the media suspicious
	if( scalar( grep( /DURATION/, @{$qualifiers} ))){
		# nothing to do to confirm a failed duration
	}

	if( scalar( grep( /TIMELINE/, @{$qualifiers} ))){
		checkVideoForTimeline( $result );
		checkVideoSummary( $result, TIMELINE ) if $opts->{displaySummary};
	}

	videoFinalizeStatus( $result );
	return $result;
}

# ------------------------------------------------------------------------------------------------
# The stage 1 has given the media a SUSPICIOUS status due to usage of 'divx_packed' flag
# Sample the file to try to find the 'Discarding excessive bitstream in packed xvid' which would
# confirm the SUSPICIOUS status - else just return to OK
# (I):
# - tresult hash
#   > status is 'FINDINGS'
#   > info contains the first-stage ffprobe JSON informations on the current media
# (O):
# - nothing

sub checkVideoForBitstream {
	my ( $result ) = @_;

	checkVideoForBitstreamSample( $result );

	# no return value
}

# ------------------------------------------------------------------------------------------------
# Sample the media to detect the "Discarding excessive bitstream in packed xvid" error
# we try to sample say 10 parts, until having found our error - or not
# (I):
# - result hash
#   > status is 'FINDINGS'
#   > info contains the first-stage ffprobe JSON informations on the current media
# (O):
# - nothing

sub checkVideoForBitstreamSample {
	my ( $result ) = @_;

	my $formatDuration = $result->{info}{format}{duration};
	my $spread = 0;
	if( $formatDuration > $Const->{sampling}{length} ){
		$spread = ( $formatDuration - $Const->{sampling}{length} ) / $Const->{sampling}{count};
	}
	my $start = 0;
	my $found = false;
	for( my $i=0 ; $i<$Const->{sampling}{count} ; ++$i ){
		$start = $i * $spread;
		$found = checkVideoForBitstreamSingleSample( $result, $start );
		return if $result->{status} eq ERROR;
		last if $found;
		last if !$spread;
	}
	if( $found ){
		videoCheckSet( $result, BITSTREAM, REPAIRABLE, videoReason( 'STREAM_DIVX_SAMPLE', [ $start ]));

	} else {
		videoCheckSet( $result, BITSTREAM, OK);
	}
}

# ------------------------------------------------------------------------------------------------
# Try a single sample
# (I):
# - result hash
#   > file-status is 'FINDINGS'
#   > check-level is SUSPICIOUS
#   > info contains the first-stage ffprobe JSON informations on the current media
# - the start offset
# (O):
# - true if the searched error has been found (and we can stop the sampling), false else

sub checkVideoForBitstreamSingleSample {
	my ( $result, $start ) = @_;

	# ffmpeg warns when asked to stream from start=0
	$start = 1 if !$start;

	my $args = [
		'-v', 'warning',
		'-ss', $start,
		'-t', $Const->{sampling}{length},
		'-i', $result->{info}{format}{filename},
		'-map', '0:v:0',
		'-f', 'null',
		'-'
	];

	my $res = TTP::commandExec({ command => 'ffmpeg', args => $args });
	my $errorFound = false;
	if( $res->{success} ){
		foreach my $line ( @{$res->{stderrs}} ){
			if( $line =~ m/Discarding excessive bitstream in packed/ ){
				$errorFound = true;
				last;
			}
		}
	} else {
		videoError( $result, videoReason( 'FFMPEG_ERROR', [ "ffmpeg failed at start='$start'" ]));
	}
	return $errorFound;
}

# ------------------------------------------------------------------------------------------------
# The stage 1 has given the media a SUSPICIOUS status due to a difference between a video stream
# duration and the container duration which happens to be greater than the accepted tolerance
# Handle complementary checks for a possible - and maybe repairable - anomaly
# (I):
# - the result hash
#   > status is 'FINDINGS'
#   > info contains the first-stage ffprobe JSON informations on the current media
# (O):
# - <nothing>
# - the result hash may have been updated

sub checkVideoForTimeline {
	my ( $result ) = @_;

	msgLog( "checkVideoForTimeline() $result->{info}{format}{filename}" );

	# count packets
	# if we find something suspicious, we will ask a confirmation to GStreamer
	ffprobeInfo( $result->{info}{format}{filename}, $result, { countPackets => true });
	if( $result->{status} eq ERROR ){
		return;
	}

	# check in each video stream that the count of packets is compatible with the stream duration
	# return unless still SUSPICIOUS
	checkVideoForTimelineStage2( $result );
	return if $result->{status} eq ERROR;
	return if $result->{findings}{TIMELINE}{status} ne SUSPICIOUS;

	# ask a confirmation to GStreamer
	my $gstDuration = gstDuration( $result );
	return if $result->{status} eq ERROR;

	checkVideoForTimelineStage3( $result, $gstDuration );
	return if $result->{status} eq ERROR;

	# if said REPAIRABLE, make sure all streams can be handled
	if( $result->{findings}{TIMELINE}{status} eq REPAIRABLE ){
		checkVideoForTimelineHandledStreams( $result );
	}

	# no return value
}

# ------------------------------------------------------------------------------------------------
# If the movie is said REPAIRABLE for TIMELINE pathology, we still have to check that we will be
#  able to handle each stream
# (I):
# - the result hash
#   > status is 'OK'
#   > info contains the second-stage ffprobe JSON informations on the current media
# (O):
# - <nothing>
# - the global $result hash may have been updated

sub checkVideoForTimelineHandledStreams {
	my ( $result ) = @_;

    my $format = $result->{info}{format} // {};
    my $formatName = $format->{format_name} // 'unknown';
	my $formatDuration = $result->{info}{format}{duration};

	msgLog( "checkVideoForTimelineHandledStreams() ".
		"result->{info}{format}{filename} format='$formatName'" );

    if( !timelineContainerSupported( $format )){
        videoCheckSet( $result, TIMELINE, SUSPICIOUS,
            videoReason( 'CONTAINER_UNSUPPORTED_FOR_REPAIR', [ $formatName ])
        );
        return;
    }

	foreach my $stream ( @{$result->{info}{streams} || []} ){
		msgLog( "checkVideoForTimelineHandledStreams() ".
			"stream #$stream->{index} codec_type='$stream->{codec_type}' codec_name='$stream->{codec_name}'" );

		if( !timelineStreamSupported( $stream )){
			my $index = $stream->{index} // '?';
			my $type = $stream->{codec_type} // 'unknown';
			my $codec = $stream->{codec_name} // 'unknown';

			videoCheckSet( $result, TIMELINE, SUSPICIOUS,
				videoReason( 'STREAM_UNSUPPORTED_FOR_REPAIR', [
					$index, $type, $codec
				]));

			return;
		}
	}

	msgLog( "checkVideoForTimelineHandledStreams() all streams validated for repair" );
	# no return value
}

# ------------------------------------------------------------------------------------------------
# Stage 2 is a bit less cheap as we count packets in stream
# The media is SUSPICIOUS because a video stream displays a duration very lower than the container
# We check the packets count (more expensive) to confirm or inform the anomaly
# (I):
# - the result hash
#   > status is 'OK'
#   > info contains the second-stage ffprobe JSON informations on the current media
# (O):
# - <nothing>
# - the global $result hash has been updated

sub checkVideoForTimelineStage2 {
	my ( $result ) = @_;

	my $formatDuration = $result->{info}{format}{duration};
	msgLog( "checkVideoForTimelineStage2() $result->{info}{format}{filename}" );

	foreach my $stream ( @{$result->{info}{streams} || []} ){
		msgLog( "checkVideoForTimelineStage2() stream #$stream->{index} codec_type='$stream->{codec_type}'" );
		next if $stream->{codec_type} ne 'video';

		my $packets = $stream->{nb_read_packets};
		msgLog( "checkVideoForTimelineStage2() stream #$stream->{index} packets=".( $packets // '(undefined)' ));

		if( defined( $packets )){
			if( $packets !~ /^\d+(?:\.\d+)?$/ || $packets <= 0 ){
				videoError( $result, videoReason( 'STREAM_PACKETS_INVALID', [ $stream->{index}, $packets ]));

			} elsif( $formatDuration > $Const->{durationThreshold}{minDuration} && 
						$packets < $Const->{durationThreshold}{minPackets} ){
				videoCheckSet( $result, TIMELINE, SUSPICIOUS,
					videoReason( 'STREAM_PACKETS_THRESHOLD',
						[ $stream->{index}, $packets, sprintf( "%.1f", $formatDuration )]));

			} else {
				msgLog( "checkVideoForTimelineStage2() ".
					"stream #$stream->{index} formatDuration is compatible with packets count" );
			}
		} else {
			videoCheckSet( $result, TIMELINE, SUSPICIOUS,
				videoReason( 'STREAM_PACKETS_UNDEFINED', [ $stream->{index} ]));
		}
	}

	# no return value
}

# ------------------------------------------------------------------------------------------------
# Stage 3 is called when stage 2 has detected some inconsistency in packets count
# We ask a confirmation to GStreamer, and compare the two durations which must be close enough
# (I):
# - the result hash
#   > status is 'OK'
#   > info contains the second-stage ffprobe JSON informations on the current media
# - the (valid) GStreamer duration
# (O):
# - <nothing>
# - the global $result hash has been updated

sub checkVideoForTimelineStage3 {
	my ( $result, $gstDuration ) = @_;

	my $formatDuration = $result->{info}{format}{duration};
	msgLog( "checkVideoForTimelineStage3() $result->{info}{format}{filename} gstDuration='$gstDuration'" );

	my $delta = durationDelta( $gstDuration, $formatDuration );
	msgLog( "checkVideoForTimelineStage3() ".
		"formatDuration=".sprintf( "%.3f", $formatDuration )." ".
		"delta=".sprintf( "%.3f", $delta )." ".
		"durationTolerance=".sprintf( "%.3f", $Const->{durationTolerance}{gstreamer} ));

	# a normal container duration (say 2500s),
	#   associatied with a very low video stream duration (often zero),
	#   associated with a very low count of packets reported by ffmpeg
	#   while gstreamer confirms the duration of the whole video
	#   -> is a known and repairable issue
	if( $delta < $Const->{durationTolerance}{gstreamer} ){
		videoCheckSet( $result, TIMELINE, REPAIRABLE, videoReason( 'GST_DURATION_DELTA',
			[ sprintf( "%.3f", $gstDuration )]));
		return;
	}

	# but:
	# a normal container duration (say 2500s),
	#   associatied with a very low video stream duration (often zero),
	#   associated with a very low count of packets reported by ffmpeg
	#   but gstreamer DOES NOT confirms the duration of the whole video
	# the issue has not been yet found
	videoCheckSet( $result, TIMELINE, OK );

	# no return value
}

# ------------------------------------------------------------------------------------------------
# Stage 1 is designed to be as cheap as possible:
# - checks that each video stream duration is not too low regarding the global duration written in metadata
# - search for 'divx_packed' which has proven to be subject to excessive bitstream in packed xvid
# (I):
# - the result hash
#   > status is 'OK'
#   > info contains a first-stage ffprobe JSON informations on the current media
# - an options hash with following keys:
#   > timeline: whether to test for timeline pathology, defaulting to true
#   > bitstream: whether to test for bitstream pathology, defaulting to true
#   > duration: whether to test for minimal duration, defaulting to -1 (disabled)
# (O):
# - an array ref of the found qualifiers
#   > ERRORS are set to result->{reasons}
#   > findings are set to the relevant object
# Note: A supported-extension file containing only audio can be classified as a valid video and
# ultimately return OK.

sub checkVideoStage1 {
	my ( $result, $opts ) = @_;

	my $qualifiers = [];
	msgLog( "checkVideoStage1() $result->{info}{format}{filename}" );

	my $formatDuration = $result->{info}{format}{duration};

	foreach my $stream ( @{$result->{info}{streams} || []} ){
		msgLog( "checkVideoStage1() stream #$stream->{index} codec_type='$stream->{codec_type}'" );
		next if $stream->{codec_type} ne 'video';

		if( $opts->{bitstream} ){
			if( $opts->{displaySummary} ){
				msgOut( sprintf( "%-8s %s", " ", "verifying bitstream..."));
			} else {
				msgLog( "checkVideoStage1() checking for bitstream pathology" );
			}
			if( defined( $stream->{divx_packed}) && $stream->{divx_packed} eq 'true' ){
				my $qualifier = BITSTREAM;
				videoCheckSet( $result,
					$qualifier, SUSPICIOUS,
					videoReason( 'STREAM_DIVX_PACKED', [ $stream->{index} ]));
				push( @{$qualifiers}, $qualifier );
			}
		}

		if( $opts->{timeline} ){
			if( $opts->{displaySummary} ){
				msgOut( sprintf( "%-8s %s", " ", "verifying timeline..."));
			} else {
				msgLog( "checkVideoStage1() checking for timeline pathology" );
			}
			my $duration = $stream->{duration};
			msgLog( "checkVideoStage1() stream #$stream->{index} duration=".( $duration // '(undefined)' ));
			if( defined( $duration ) && $duration ne 'N/A' ){
				if( $duration !~ /^\d+(?:\.\d+)?$/ || $duration < 0 ){
					videoError( $result, videoReason( 'STREAM_DURATION_INVALID', [ $stream->{index}, $duration ]));

				} else {
					my $delta = durationDelta( $duration, $formatDuration );
					msgLog( "checkVideoStage1() ".
						"formatDuration=".sprintf( "%.3f", $formatDuration )." ".
						"delta=".sprintf( "%.3f", $delta )." ".
						"durationTolerance=".sprintf( "%.3f", $Const->{durationTolerance}{video} ));

					# video stream duration should be close or equal to the known container duration
					# we accept a 10% tolerance, but a greater delta makes the media suspicious
					if( $delta > $Const->{durationTolerance}{video} ){
						my $qualifier = TIMELINE;
						videoCheckSet( $result,
							$qualifier, SUSPICIOUS,
							videoReason( 'STREAM_DURATION_DELTA', 
								[ $stream->{index}, sprintf( "%.3f", $duration ), sprintf( "%.3f", $formatDuration ) ]));
						push( @{$qualifiers}, $qualifier );
		
					} else {
						msgLog( "checkVideoStage1() delta is inside the accepted tolerance" );
					}
				}
			} else {
				# video stream with undefined duration
				#  -> no video-duration check applicable for that stream
				# this can be normal in particular for Matroska containers
				msgLog( "checkVideoStage1() stream #$stream->{index} duration not considered" );
			}
		}
	}

	if( $opts->{duration} > 0 ){
		msgLog( "checkVideoStage1() checking for minimal duration" );
		if( $opts->{duration} > $formatDuration ){
			my $qualifier = DURATION;
			videoCheckSet( $result,
				$qualifier, FAILED,
				videoReason( 'MEDIA_MIN_DURATION',
					[ sprintf( "%.3f", $formatDuration ), sprintf( "%.3f", $opts->{duration} ) ]));
			push( @{$qualifiers}, $qualifier );
		}
	}

	# doesn't override a potential file-level ERROR
	return [] if $result->{status} eq ERROR;

	# all what we may say here is whether we have found something, but 
	$result->{status} = FINDINGS if scalar( @{$qualifiers} );
	return $qualifiers;
}

# ------------------------------------------------------------------------------------------------
# A summary for each repair operation
# (I):
# - the checkVideo() result hash
# - the check qualifier
# (O):
# - <nothing>

sub checkVideoSummary {
    my ( $result, $check ) = @_;
	msgLog( "checkVideoSummary() check'$check'" );

    my $status = $result->{findings}{$check}{status};
    return if !$status;

    msgOut( sprintf( "%-10s %s", '', "$check verification: $status" ));

    if( scalar( @{$result->{findings}{$check}{reasons} // []} )){
        foreach my $reason ( @{$result->{findings}{$check}{reasons}} ){
            msgOut( sprintf(
                "%-10s %s",
                '',
                sprintf( $reason->{format}, @{$reason->{args} // [] })
            ));
        }
    }
}

# ------------------------------------------------------------------------------------------------
# Convert the given string to replace forbidden chars
# (I):
# - the string to be converted
# (O):
# - the converted string

sub convertStr {
	my ( $str ) = @_;

	foreach my $ch ( keys %{$Const->{forbiddenChars}} ){
		my $rep = $Const->{forbiddenChars}{$ch};
		$str =~ s/$ch/$rep/g;
	}

	return $str;
}

# ------------------------------------------------------------------------------------------------
# Extracts the cover from a full scan
# https://metacpan.org/release/AGRUNDMA/Audio-Scan-0.93/view/lib/Audio/Scan.pm#SKIPPING-ARTWORK
# we return here the length of the image rather than the image itself
# (I):
# - the scan result
# (O):
# - the length of the image, or undef

sub coverFromScan {
	my ( $scan ) = @_;

	my $value = undef;
	$value = $value || $scan->{tags}{APIC}->[3];						# MP3
	$value = $value || $scan->{tags}{APIC}->[0][3];						# MP3 when there are several images
	$value = $value || $scan->{tags}{COVR};								# MP4
	$value = $value || $scan->{tags}{ALLPICTURES}->[0]->{image_data};	# Ogg Vorbis / FLAC
	$value = $value || $scan->{tags}{'WM/Picture'}->{image};			# ASF
	$value = $value || $scan->{tags}{'COVER ART (FRONT)'};				# APE, Musepack, WavPack, MP3 with APEv2
	print "coverFromScan() $scan->{path} ".Dumper( $scan->{tags} ) if !$value;
	#msgVerbose( "$scan->{path} cover $value" ) if $value;

	return $value;
}

# ------------------------------------------------------------------------------------------------
# compute the difference between two durations
# (I):
# - duration
# - reference
# (O):
# - the delta as a number <= 1, to be compared with the corresponding 'durationTolerance' named constant

sub durationDelta {
	my ( $duration, $reference ) = @_;

	return abs( $duration - $reference ) / $reference;
}

# ------------------------------------------------------------------------------------------------
# Get informations from ffprobe about the provided video, and check they are valid
# When no error is detected, we can safely use filename and container duration.
# (I):
# - the video filename
# - the result hash
#   > status is 'OK'
#   > reasons
# - an optional options hash with following keys:
#   > countPackets: whether packets are to be counted, defaulting to false
# (O):
# - the result hash has been updated:
#   > info: the decoded ffprobe JSON structure, or undef on error
#   > reasons: if error, an array ref of error reason(s)
#   > status: 'OK' or 'ERROR'

sub ffprobeInfo {
	my ( $fname, $result, $opts ) = @_;

	ffprobeInfoGet( $fname, $result, $opts );

	if( $result->{status} ne ERROR ){
		ffprobeInfoCheck( $result );
	}
}

# ------------------------------------------------------------------------------------------------
# Check the got ffprobe informations:
#  Must have at least a format, a filename, a duration
# (I):
# - the result hash
#   > status is 'OK'
#   > info contains a first-stage ffprobe JSON informations on the current media
# (O):
# - <nothing>
# - the result hash has been updated:
#   > reasons: if error, an array ref of error reason(s)
#   > status: 'OK' or 'ERROR'

sub ffprobeInfoCheck {
	my ( $result ) = @_;

	if( !$result->{info} ){
		videoError( $result, videoReason( 'FFPROBE_ERROR',
			[ "ffprobeInfoCheck() called while 'info' is not defined" ]));
	} elsif( !$result->{info}{format} ){
		videoError( $result, videoReason( 'FFPROBE_ERROR',
			[ "ffprobeInfoCheck() info->{format} is not defined" ]));
	} else {
		# check filename
		if( !$result->{info}{format}{filename} ){
			videoError( $result, videoReason( 'FFPROBE_ERROR',
				[ 'ffprobeInfoCheck() info->{format}{filename} is not defined' ]));
		} else {
			msgLog( "ffprobeInfoCheck() info->{format}{filename}='$result->{info}{format}{filename}'" );
		}
		# check container duration
		if( defined( $result->{info}{format}{duration} )){
			my $duration = $result->{info}{format}{duration};
			if( $duration !~ /^\d+(?:\.\d+)?$/  || $duration <= 0 ){
				videoError( $result, videoReason( 'FFPROBE_ERROR',
					[ "ffprobeInfoCheck() info->{format}{duration}='$duration' is not valid" ]));
			} else {
				msgLog( "ffprobeInfoCheck() info->{format}{duration}='$duration'" );
			}
		} else {
			videoError( $result, videoReason( 'FFPROBE_ERROR',
				[ "ffprobeInfoCheck() info->{format}{duration} is not defined" ]));
		}
	}

	msgLog( "ffprobeInfoCheck() status='$result->{status}'" );
	# not return value
}

# ------------------------------------------------------------------------------------------------
# Get informations from ffprobe about the provided video
# (I):
# - the video filename
# - the result hash
#   > status is 'OK'
#   > reasons
# - an optional options hash with following keys:
#   > countPackets: whether packets are to be counted, defaulting to false
# (O):
# - the result hash has been updated:
#   > info: the decoded ffprobe JSON structure, or undef on error
#   > reasons: if error, an array ref of error reason(s)
#   > status: 'OK' or 'ERROR'

sub ffprobeInfoGet {
	my ( $fname, $result, $opts ) = @_;
	$opts //= {};

	my $args = [
		'-v', 'error'
	];

	push( @{$args}, '-count_packets' ) if $opts->{countPackets};

	push( @{$args},
		'-show_format',
		'-show_streams',
		'-of', 'json',
		$fname
	);

	my $res = TTP::commandExec({ command => 'ffprobe', args => $args });
	#print Dumper( $result );
	my $reason = undef;
	my $decoded = undef;

	if( $res->{success} ){
		my $json = join( "\n", @{$res->{stdouts}} );
		eval {
			$decoded = JSON::PP->new->decode( $json );
		};
		if( $@ ){
			$reason = videoReason( 'FFPROBE_ERROR', [ "ffprobeInfoGet() unable to decode ffprobe output for '$fname': $@" ] );
			$decoded = undef;
		}
	} else {
		$reason = videoReason( 'FFPROBE_ERROR', [ "ffprobeInfoGet() failed for '$fname'" ] );
	}

	# summary and sanity checks
	if( $reason ){
		videoError( $result, $reason );
		if( $decoded ){
			msgErr( __PACKAGE__."ffprobeInfoget() have both reason and decoded" );
		}
	} else {
		if( !$decoded ){
			$result->{status} = ERROR;
			msgErr( __PACKAGE__."ffprobeInfoget() have neither reason nor decoded" );
		}
	}

	if( $decoded ){
		$result->{info} = $decoded;
		msgLog( "ffprobeInfoGet() status='$result->{status}' fname='$fname'" );
	}

	# no return value
}

# ------------------------------------------------------------------------------------------------
# Extracts the genre from a full scan
# (I):
# - the scan result
# - an optional options hash with following keys:
#   > dumpIfEmpty: whether to dump the tags if the searched value is not found, defaulting to true
# (O):
# - the genre, or undef

sub genreFromScan {
	my ( $scan, $opts ) = @_;
	$opts //= {};

	my $dumpIfEmpty = true;
	$dumpIfEmpty = $opts->{dumpIfEmpty} if defined $opts->{dumpIfEmpty};

	my $value = undef;
	$value = $value || $scan->{tags}{TCON};		# MP3
	$value = $value || $scan->{tags}{GEN};		# MP4
	$value = $value || $scan->{tags}{GENRE};	# FLAC

	print "genreFromScan() $scan->{path} ".Dumper( $scan->{tags} ) if !$value && $dumpIfEmpty;

	return $value;
}

# ------------------------------------------------------------------------------------------------
# get the duration as reported by gst-discoverer-1.0
# (I):
# - the result hash
#   > status is 'SUSPICIOUS'
#   > info contains the second-stage ffprobe JSON informations on the current media
# (O):
# - the GStreamer duration, or undef
# - the result hash has been updated:
#   > reasons: if error, an array ref of error reason(s)
#   > status: unchanged or 'ERROR'

sub gstDuration {
	my ( $result ) = @_;

	my $args = [
		$result->{info}{format}{filename}
	];
	my $res = TTP::commandExec({ command => 'gst-discoverer-1.0', args => $args });

	if( !$res->{success} ){
		msgErr( __PACKAGE__."::gstDuration() gst-discoverer-1.0 failed for '$result->{info}{format}{filename}'" );
		videoError( $result, videoReason( 'GST_ERROR',
			[ "gstDuration() gst-discoverer-1.0 failed for '$result->{info}{format}{filename}'" ]));
		return undef;
	}

	my $duration;

	foreach my $line ( @{$res->{stdouts}} ){
		if( $line =~ /^\s*Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)\s*$/ ){
			my ( $hours, $minutes, $seconds ) = ( $1, $2, $3 );
			$duration = $hours * 3600 + $minutes * 60 + $seconds;
			last;
		}
	}

	if( !defined( $duration )){
		videoError( $result, videoReason( 'GST_ERROR',
			[ "gstDuration() unable to find the duration reported by GStreamer" ]));
		return undef;
	}

	if( $duration !~ /^\d+(?:\.\d+)?$/ ){
		videoError( $result, videoReason( 'GST_ERROR',
			[ "gstDuration() duration='$duration' is not valid" ]));
		return undef;
	}

	if( $duration < 0 ){
		videoError( $result, videoReason( 'GST_ERROR',
			[ "gstDuration() duration='$duration' is not valid" ]));
		return undef;
	}

	return $duration;
}

# ------------------------------------------------------------------------------------------------
# given our standard audio trees are set as ROOT/type/letter/artist/albums[/disc]/file
# (I):
# - the full file pathname
# (O):
# - whether the path includes a disc level

sub hasDiscLevel {
	my ( $path ) = @_;

	my ( $volume,$directories,$file ) = File::Spec->splitpath( $path );
	my @dirs = File::Spec->splitdir( $directories );
	my $disc = ( scalar( @dirs ) > 8 );

	return $disc;
}

# ------------------------------------------------------------------------------------------------
# whether the string embeds some forbidden chars
# (I):
# - a string
# (O):
# - true if the string has any forbidden char

sub hasForbiddenChars {
	my ( $str ) = @_;

	my $new = convertStr( $str );
	my $hasForbidden = ( $new ne $str );

	return $hasForbidden;
}

# ------------------------------------------------------------------------------------------------
# Whether the filename exhibits a path which may let us think this is an audio file
# (I):
# - the full file pathname
# (O):
# - true if this may be an audio file, false else

sub isAudioCapable {
	my ( $path ) = @_;

	my $audio = Audio::Scan->is_supported( $path );

	return $audio;
}

# ------------------------------------------------------------------------------------------------
# Whether the filename exhibits a path which may let us think this is a video file
# (I):
# - the full file pathname
# (O):
# - true if this may be a video file, false else

sub isVideoCapable {
	my ( $path ) = @_;

	my ( undef, undef, $suffix ) = File::Basename::fileparse( $path, qr/\.[^.]*/ );

	my $video = grep( { lc( $suffix ) eq $_ } @{$Const->{videoExtensions}} ) ? true : false;

	return $video;
}

# ------------------------------------------------------------------------------------------------
# Repair a video where checkVideo() has identified a repairable pathology
# (I):
# - the video filename
# - the checkVideo() result hash
# - an optional options hash with following keys:
#   > bitstream: whether to test for bitstream pathology, defaulting to true
#   > timeline: whether to test for timeline pathology, defaulting to true
#   > verify: whether the repair will later be verified, defaulting to false
# (O):
# - a hash with following keys:
#   > status: 'OK' or 'ERROR'
#   > reasons: an array ref of error reasons
#   > findings: a hash ref per done repair:
#     - BITSTREAM: a hash with following keys:
#       > status: OK or ERROR
#       > reasons: an array ref of reasons
#     - TIMELINE: a hash with following keys:
#       > status: OK or ERROR
#       > reasons: an array ref of reasons
#   > info: the ffprobe informations
#
# nb: 'findings' is the same name than in checkVideo() to be able to reuse '$result'-oriented functions

sub repairVideo {
	my ( $fname, $checkResult, $opts ) = @_;
	$opts //= {};
	my $new_fname = $fname;

	# prepare the returned result
	my $result = {
		status => OK,
		reasons => [],
		info => undef,
		fname => $new_fname,
		findings => {}
	};

	if( $opts->{bitstream} && $checkResult->{findings}{BITSTREAM}{status} eq REPAIRABLE ){
		$result->{findings}{BITSTREAM} = {
			status => OK,
			reasons => []
		};
		msgOut( sprintf( "%-8s %s", " ", "repairing bitstream..."));
		repairVideoBitstream( $result, $fname, $checkResult );
		$fname = $result->{fname};
		repairVideoSummary( $result, BITSTREAM );
	}

	if( $opts->{timeline} && $checkResult->{findings}{TIMELINE}{status} eq REPAIRABLE ){
		$result->{findings}{TIMELINE} = {
			status => OK,
			reasons => []
		};
		msgOut( sprintf( "%-8s %s", " ", "repairing timeline..."));
		repairVideoTimeline( $result, $fname, $checkResult );
		$fname = $result->{fname};
		repairVideoSummary( $result, TIMELINE );
	}

	videoFinalizeStatus( $result );

	return $result;
}

# ------------------------------------------------------------------------------------------------
# Repair an 'excessive bitstream' divx video
# (I):
# - the global result hash
# - the video filename
# - the checkVideo() result hash
# (O):
# - the new filename (should be unchanged)
# + the global result->{findings}{BITSTREAM}{status} has been updated

sub repairVideoBitstream {
	my ( $repairResult, $fname, $checkResult ) = @_;

	my $new_fname = $fname;

	my ( undef, undef, $suffix ) = File::Basename::fileparse( $fname, qr/\.[^.]*/ );
	my $tmp_fname = "$fname.tmp$suffix";

	my $args = [
		'-i', $fname,
		'-map', '0',
		'-c', 'copy',
		'-bsf:v',
		'mpeg4_unpack_bframes',
		$tmp_fname
	];

	my $res = TTP::commandExec({ command => 'ffmpeg', args => $args });
	my $success = false;

	if( $res->{success} ){
		$args = [
			'-v',
			$tmp_fname,
			$fname
		];
		$res = TTP::commandExec({ command => 'mv', args => $args });
		if( $res->{success} ){
			# filename is left unchanged by that repair
			videoCheckSet( $repairResult, BITSTREAM, OK );
			$repairResult->{fname} = $fname;
			$success = true;
		}

	}
	if( !$success ){
		unlink( $tmp_fname );
		videoCheckSet( $repairResult, BITSTREAM, ERROR, videoReason( 'FFMPEG_ERROR', [
			"unable to successfully execute ffmpeg to repair \'$fname\'"
		]));
	}

	return $new_fname;
}

# ------------------------------------------------------------------------------------------------
# A summary for each repair operation
# (I):
# - the repairVideo() result hash
# - the check qualifier
# (O):
# - <nothing>

sub repairVideoSummary {
    my ( $result, $check ) = @_;
	msgLog( "repairVideoSummary() check'$check'" );

    my $status = $result->{findings}{$check}{status};
    return if !$status;

    my $suffix = '';
    if( $status eq OK && $result->{fname} ){
        $suffix = " -> $result->{fname}";
    }

    msgOut( sprintf(
        "%-10s %s%s",
        '',
        "$check repair: $status",
        $suffix
    ));

    if( scalar( @{$result->{findings}{$check}{reasons} // []} )){
        foreach my $reason ( @{$result->{findings}{$check}{reasons}} ){
            msgOut( sprintf(
                "%-10s %s",
                '',
                sprintf( $reason->{format}, @{$reason->{args} // [] })
            ));
        }
    }
}

# ------------------------------------------------------------------------------------------------
# Repair a broken MP4 timeline by remuxing supported streams into Matroska
# without transcoding.
# (I):
# - the global repair result hash
# - the video filename
# - the checkVideo() result hash
# (O):
# - the new filename
# + the global result->{findings}{TIMELINE}{status} has been updated

sub repairVideoTimeline {
    my ( $repairResult, $fname, $checkResult ) = @_;

    my ( $base, $dir, $suffix ) = File::Basename::fileparse( $fname, qr/\.[^.]*/ );

    my $new_fname = File::Spec->catfile( $dir, "$base.mkv" );
    my $tmp_fname = "$new_fname.part";
    my $orig_fname = "$fname.orig";

    # Do not overwrite anything.
    if( -e $new_fname ){
        videoCheckSet( $repairResult, TIMELINE, ERROR,
            videoReason( 'GST_REPAIR_ERROR',
                [ "destination already exists: '$new_fname'" ]));
        return $fname;
    }

    if( -e $orig_fname ){
        videoCheckSet( $repairResult, TIMELINE, ERROR,
            videoReason( 'GST_REPAIR_ERROR',
                [ "backup already exists: '$orig_fname'" ]));
        return $fname;
    }

    unlink( $tmp_fname ) if -e $tmp_fname;

	my @branches = ();

	my $video_idx = 0;
	my $audio_idx = 0;
	my $subtitle_idx = 0;

	foreach my $stream ( @{$checkResult->{info}{streams} || []} ){

		my $type = $stream->{codec_type} // '';
		my $codec = $stream->{codec_name} // '';

		if( $type eq 'video' ){

			my $parser;

			if( $codec eq 'h264' ){
				$parser = 'h264parse';

			} elsif( $codec eq 'hevc' ){
				$parser = 'h265parse';

			} else {
				videoCheckSet( $repairResult, TIMELINE, ERROR,
					videoReason( 'GST_REPAIR_ERROR', [
						"unsupported video codec '$codec' in '$fname'"
					]));
				return $fname;
			}

			push( @branches, (
				"d.video_$video_idx",
				'!',
				'queue',
				'max-size-time=10000000000',
				'!',
				$parser,
				'!',
				'mux'
			));

			$video_idx += 1;

		} elsif( $type eq 'audio' ){

			if( $codec ne 'aac' ){
				videoCheckSet( $repairResult, TIMELINE, ERROR,
					videoReason( 'GST_REPAIR_ERROR', [
						"unsupported audio codec '$codec' in '$fname'"
					]));
				return $fname;
			}

			push( @branches, (
				"d.audio_$audio_idx",
				'!',
				'queue',
				'!',
				'aacparse',
				'!',
				'mux'
			));

			$audio_idx += 1;

		} elsif( $type eq 'subtitle' ){

			if( $codec ne 'mov_text' ){
				videoCheckSet( $repairResult, TIMELINE, ERROR,
					videoReason( 'GST_REPAIR_ERROR', [
						"unsupported subtitle codec '$codec' in '$fname'"
					]));
				return $fname;
			}

			push( @branches,
				"d.subtitle_$subtitle_idx",
				'!',
				'queue',
				'!',
				'mux'
			);

			$subtitle_idx += 1;

		} else {
			videoCheckSet( $repairResult, TIMELINE, ERROR,
				videoReason( 'GST_REPAIR_ERROR', [
					"unsupported stream type '$type' codec '$codec' in '$fname'"
				]));
			return $fname;
		}
	}

	# theorically impossible guards

	if( !$video_idx ){
		videoCheckSet( $repairResult, TIMELINE, ERROR,
			videoReason( 'GST_REPAIR_ERROR',
				[ "no video stream found in '$fname'" ]));
		return $fname;
	}

    my $args = [
        '-e',
        'filesrc',
        "location=\"$fname\"",
        '!',
        'qtdemux',
        'name=d',
        'matroskamux',
        'name=mux',
        '!',
        'filesink',
        "location=\"$tmp_fname\""
	];
	push( @{$args}, @branches );

    my $res = TTP::commandExec({ command => 'gst-launch-1.0', args => $args });

    if( !$res->{success} ){
        unlink( $tmp_fname );
        videoCheckSet( $repairResult, TIMELINE, ERROR,
            videoReason( 'GST_REPAIR_ERROR',
                [ "unable to successfully execute GStreamer to repair '$fname'" ]));
        return $fname;
    }

    if( !-s $tmp_fname ){
        unlink( $tmp_fname );
        videoCheckSet( $repairResult, TIMELINE, ERROR,
            videoReason( 'GST_REPAIR_ERROR',
                [ "GStreamer produced an empty file '$tmp_fname'" ]));
        return $fname;
    }

    # Preserve source first.
    if( !rename( $fname, $orig_fname )){
        unlink( $tmp_fname );
        videoCheckSet( $repairResult, TIMELINE, ERROR,
            videoReason( 'GST_REPAIR_ERROR',
                [ "unable to rename '$fname' to '$orig_fname': $!" ]));
        return $fname;
    }

    # Install repaired Matroska.
    if( !rename( $tmp_fname, $new_fname )){

        my $error = $!;

        # Best effort rollback.
        if( !rename( $orig_fname, $fname )){
            videoCheckSet( $repairResult, TIMELINE, ERROR,
                videoReason( 'GST_REPAIR_ERROR', [
                    "unable to install '$new_fname': $error; ".
                    "rollback '$orig_fname' to '$fname' also failed: $!"
                ]));
        } else {
            videoCheckSet( $repairResult, TIMELINE, ERROR,
                videoReason( 'GST_REPAIR_ERROR',
                    [ "unable to install '$new_fname': $error" ]));
        }

        return $fname;
    }

    videoCheckSet( $repairResult, TIMELINE, OK );
    $repairResult->{fname} = $new_fname;

    return $new_fname;
}

# ------------------------------------------------------------------------------------------------
# Scan an audio file
# https://metacpan.org/release/AGRUNDMA/Audio-Scan-0.93/view/lib/Audio/Scan.pm
# The type of scan performed is determined by the file's extension.
# (I):
# - the full file pathname
# (O):
# - a hash ref with following keys:
#   > ok: true|false
#   > path: the original full file pathname
#   > suffix: the found suffix (uppercase, should be considered case insensitive)
#
#   if ok is true:
#   > info: from scan_info(), audio informations
#   > tags: from scan_tags(), found tags
#
#   if ok is false:
#   > errors: an array of error messages (e.g. if the audio file is malformed)

sub scan_file {
	my ( $path ) = @_;
	my $result = undef;

	my ( $res_out, $res_err, $res_code ) = capture {
		local $ENV{AUDIO_SCAN_NO_ARTWORK} = 1;
		$result = Audio::Scan->scan( $path );
	};
	if( $res_err ){
		chomp $res_err;
		$result->{ok} = false;
		my @errs = split( /[\r\n]/, $res_err );
		$result->{errors} = \@errs;
	} else {
		$result->{ok} = true;
		#print "$path scan result: ".Dumper( $result );
	}

	$result->{path} = $path;
	my $suffix = TTP::Path::suffix( $path );
	$result->{suffix} = uc( $suffix ) if $suffix;

	return $result;
}

# ------------------------------------------------------------------------------------------------
# Scan a source tree
# (I):
# - the source tree
# - an optional options hash with following keys:
#   > ignoreDirectories, defaulting to true
#   > ignoreNotSupported, defaulting to true
#   > sub: a ref to a code which will be called with two arguments:
#     - the full candidate pathname
#     - the result of the file scan if the candidate is a supported file, as a ref to a hash with following keys:
#       > info: the result of scan_info()
#       > tags: the result of scan_tags()
#       > path: the full candidate pathname
#       > suffix: the suffix of the candidate as an uppoercase string (e.g. 'MP3')
# (O):
# - a hash ref with following keys:
#   > ok: true|false
#   > ignoredDirectories: the count of ignored directories
#   > ignoredNotSupported: the count of ignored not supported files
#   > candidates: the count of candidates pathnames passed to above sub

sub scan_tree {
	my ( $tree, $opts ) = @_;
	$opts //= {};

	if( !$opts->{sub} || ref( $opts->{sub} ) ne 'CODE' ){
		msgErr( __PACKAGE__."::scan() expects an 'sub' option, not found" );
		TTP::stackTrace();
	}

	my $result = {
		ok => true,
		ignoredDirectories => 0,
		ignoredNotSupported => 0,
		candidates => 0
	};

	my $ignoreDirectories = true;
	$ignoreDirectories = $opts->{ignoreDirectories} if defined $opts->{ignoreDirectories};

	my $ignoreNotSupported = true;
	$ignoreNotSupported = $opts->{ignoreNotSupported} if defined $opts->{ignoreNotSupported};

	find({
		# receive here all found files and directories
		wanted => sub {
			my $fname = decode( 'UTF-8', $File::Find::name );
			my $isDirectory = false;
			my $isSupported = false;
			my $ignored = false;

			# have an ignored directory ?
			if( -d $_ ){
				if( $ignoreDirectories ){
					msgVerbose( "ignoring directory $fname" );
					$result->{ignoredDirectories} += 1;
					$ignored = true;
				} else {
					$isDirectory = true;
				}

			# have a not-supported file ?
			} else {
				$isSupported = Audio::Scan->is_supported( $fname );
				if( !$isSupported && $ignoreNotSupported ){
					msgVerbose( "ignoring not supported $fname" );
					$result->{ignoredNotSupported} += 1;
					$ignored = true;
				}
			}

			if( !$ignored ){
				my $scan = ( $isDirectory || !$isSupported ) ? undef : scan_file( $fname );
				$opts->{sub}( $fname, $scan );
				$result->{candidates} += 1;
			}
		},
	}, $tree );

	return $result;
}

# ------------------------------------------------------------------------------------------------
# When trying to repair a video whose timeline exhibits the known unsynchronized pathology,
#  we have to make sure that we will be able to demux the container
# (I):
# - the stream format, as a comma-separated string
# (O):
# - true if the audio stream is managed

sub timelineContainerSupported {
    my ( $format ) = @_;
	msgLog( "timelineContainerSupported() format='$format->{format_name}'" );

    return false if !$format;

    my $formatName = lc( $format->{format_name} // '' );
    return false if !$formatName;

    my %qtdemuxFormats = map { $_ => true } qw(
        mov
        mp4
        m4a
        3gp
        3g2
        mj2
    );

    foreach my $name ( split( /,/, $formatName )){
        return true if $qtdemuxFormats{$name};
    }

    return false;
}

# ------------------------------------------------------------------------------------------------
# When trying to repair a video whose timeline exhibits the known unsynchronized pathology,
#  we have to make sure all audio streams are correctly managed - thus this helper
# (I):
# - the stream information
# (O):
# - true if the audio stream is managed

sub timelineStreamSupported {
    my ( $stream ) = @_;

    return false if !$stream;

    my $type = $stream->{codec_type} // '';
    my $codec = $stream->{codec_name} // '';
	msgLog( "timelineStreamSupported() #$stream->{index} type='$type' codec='$codec'" );

    return true if $type eq 'video'
        && grep( /^$codec$/, qw( h264 hevc ));

    return true if $type eq 'audio'
        && $codec eq 'aac';

    return true if $type eq 'subtitle'
        && $codec eq 'mov_text';

    return false;
}

# ------------------------------------------------------------------------------------------------
# Extracts the track count from a full scan
# (I):
# - the scan result
# (O):
# - the track count, or undef

sub trackCountFromScan {
	my ( $scan ) = @_;

	my $value = undef;
	$value = $value || $scan->{tags}{TRCK};			# MP3 number/count
	$value = $value || $scan->{tags}{TRKN};			# M4A number/count
	my $haveCount = $value;
	$haveCount =~ s/[^\/]//g if $value;
	if( $haveCount ){
		if( $value ){
			$value =~ s/^[0-9]+\///;
		}
	} else {
		$value = undef;
	}
	$value = $value || $scan->{tags}{TRACKTOTAL};	# FLAC
	print "trackCountFromScan() $scan->{path} ".Dumper( $scan->{tags} ) if !$value;
	#msgVerbose( "$scan->{path} year $value" ) if $value;

	return $value;
}

# ------------------------------------------------------------------------------------------------
# Extracts the track number from a full scan
# (I):
# - the scan result
# (O):
# - the track number, or undef

sub trackNumberFromScan {
	my ( $scan ) = @_;

	my $value = undef;
	$value = $value || $scan->{tags}{TRCK};			# MP3 number/count
	$value = $value || $scan->{tags}{TRKN};			# M4A number/count
	if( $value ){
		$value =~ s/\/[0-9]+$//;
	}
	$value = $value || $scan->{tags}{TRACKNUMBER};	# FLAC

	if( !defined( $value )){
		print "trackNumberFromScan() $scan->{path} ".Dumper( $scan->{tags} );
	} elsif( !looks_like_number( $value )){
		print "trackNumberFromScan() $scan->{path} ".Dumper( $scan->{tags} );
		$value = undef;
	}
	#msgVerbose( "$scan->{path} year $value" ) if $value;

	return $value;
}

# ------------------------------------------------------------------------------------------------
# Extracts the track title from a full scan
# (I):
# - the scan result
# (O):
# - the track title, or undef

sub trackTitleFromScan {
	my ( $scan ) = @_;

	my $value = undef;
	$value = $value || $scan->{tags}{TIT1};			# MP3
	$value = $value || $scan->{tags}{TIT2};
	$value = $value || $scan->{tags}{NAM};			# M4A
	$value = $value || $scan->{tags}{TITLE};		# FLAC
	print "trackTitleFromScan() $scan->{path} ".Dumper( $scan->{tags} ) if !$value;
	#msgVerbose( "$scan->{path} year $value" ) if $value;

	return $value;
}

# ------------------------------------------------------------------------------------------------
# Set the result of a qualified check
# (I):
# - the result hash ref
# - the check qualifier (BITSTREAM, DURATION, TIMELINE, ...)
# - the status (OK, SUSPICIOUS, FAILED, REPAIRABLE, ...)
# - a reason or an array ref of reasons
# (O):
# - <nothing>
#   > result->{findings}{qualifier}{status} is updated
#   > result->{findings}{qualifier}{reasons} is incremented with the provided reasons

sub videoCheckSet {
	my ( $result, $qualifier, $status, $reasons ) = @_;

	$result->{findings}{$qualifier}{status} = $status;

	# clear the reasons when status is set to 'OK'
	if( $status eq OK ){
		$result->{findings}{$qualifier}{reasons} = [];

	# else push new available reasons
	} elsif( $reasons ){
		if( ref( $reasons ) eq 'HASH' ){
			push( @{$result->{findings}{$qualifier}{reasons}}, $reasons );
			msgLog( "videoCheckSet() $reasons->{id} ".sprintf( $reasons->{format}, @{$reasons->{args}} ));

		} elsif( ref( $reasons ) eq 'ARRAY' ){
			foreach my $reason ( @{$reasons} ){
				push( @{$result->{findings}{$qualifier}{reasons}}, $reason );
				msgLog( "videoCheckSet() $reason->{id} ".sprintf( $reason->{format}, @{$reason->{args}} ));
			}

		} else {
			msgErr( __PACKAGE__."::videoCheckSet() () reasons is neither a hash nor an array" );
		}

	# warn if not OK but no reason
	} else {
		msgWarn( "videoCheckSet() qualifier='$qualifier' status='$status' but no proposed reason" );
	}
}

# ------------------------------------------------------------------------------------------------
# Set an error when checking a video - 'ERROR' is at file level
# (I):
# - the result hash ref
# - a reason or an array ref of reasons
# (O):
# - <nothing>
#   > result->{status} is set to 'ERROR' - will never be able to go back to another value
#   > result->{reasons} is incremented with the provided reasons

sub videoError {
	my ( $result, $reasons ) = @_;

	$result->{status} = ERROR;

	if( ref( $reasons ) eq 'HASH' ){
		push( @{$result->{reasons}}, $reasons );
		msgLog( "videoError() $reasons->{id} ".sprintf( $reasons->{format}, @{$reasons->{args}} ));

	} elsif( ref( $reasons ) eq 'ARRAY' ){
		foreach my $reason ( @{$reasons} ){
			push( @{$result->{reasons}}, $reason );
			msgLog( "videoError() $reason->{id} ".sprintf( $reason->{format}, @{$reason->{args}} ));
		}

	} else {
		msgErr( __PACKAGE__."::videoError() reasons is neither a hash nor an array" );
	}
}

# ------------------------------------------------------------------------------------------------
# Consolidate all findings status in tho the global result status
#  Only goal is to display a FINDINGS status if and only if one check has something to say
# (I):
# - the result hash ref
# (O):
# - <nothing>
#   > the result status hash is updated

sub videoFinalizeStatus {
	my ( $result ) = @_;

	# do not modify nor override an 'ERROR' status
	return if $result->{status} eq ERROR;

	# either OK, ERROR or FINDINGS
	# stop as soon as we find anything other than OK
	my $findings = false;
	my $error = false;
	foreach my $key( sort keys( %{$result->{findings}} )){
		if( $result->{findings}{$key}{status} ne OK ){
			$findings = true;
		}
		if( $result->{findings}{$key}{status} eq ERROR ){
			$error = true;
			last;
		}
	}
	$result->{status} = $error ? ERROR : ( $findings ? FINDINGS : OK );
	msgLog( "videoFinalizeStatus() $result->{status}" );
}

# ------------------------------------------------------------------------------------------------
# Find the invoked reason, and return it after having build the relevant message
# (I):
# - the reason identfier
# - an array of format arguments
# (O):
# - the reason hash, with the current arguments

sub videoReason {
	my ( $id, $args ) = @_;

	foreach my $reason ( @{$Const->{videoReasons}} ){
		if( $reason->{id} eq $id ){
			return {
				id => $id,
				format => $reason->{format},
				args => $args // []
			};
		}
	}

	msgErr( __PACKAGE__."::videoReason() identifier not found: '$id'" );
	return undef;
}

# ------------------------------------------------------------------------------------------------
# Walk a media tree
# (I):
# - the source path, which may be a file or a directory
# - an optional options hash with following keys:
#   > recurse: whether to recursively walk subdirectories, defaulting to true
#   > sub: a ref to a code which will be called with the full candidate pathname
# (O):
# - a hash ref with following keys:
#   > ok: true|false
#   > candidates: the count of candidate pathnames passed to above sub
#
# Directories whose name begins with '.Trash' are ignored.

sub walkTree {
	my ( $path, $opts ) = @_;
	$opts //= {};

	if( !$opts->{sub} || ref( $opts->{sub} ) ne 'CODE' ){
		msgErr( __PACKAGE__."::walkTree() expects a 'sub' option, not found" );
		TTP::stackTrace();
	}

	my $recurse = true;
	$recurse = $opts->{recurse} if defined $opts->{recurse};

	my $result = {
		ok => true,
		candidates => 0
	};

	# a single file
	if( -f $path ){
		$opts->{sub}( $path );
		$result->{candidates} += 1;

	# a directory
	} elsif( -d $path ){
		find({
			no_chdir => true,

			wanted => sub {
				my $fname = decode( 'UTF-8', $File::Find::name );

				# do not enter ignored directories
				if( -d $File::Find::name ){
					my ( undef, undef, $name ) = File::Spec->splitpath( $File::Find::name );

					foreach my $re ( @{$Const->{walkingIgnore}{dirs}} ){
						if( $name =~ /$re/ ){
							$File::Find::prune = 1;
							return;
						}
					}

					# when not recursive, do not descend below the source directory
					if( !$recurse && $File::Find::name ne $path ){
						$File::Find::prune = 1;
					}

					return;
				}

				$opts->{sub}( $fname );
				$result->{candidates} += 1;
			}
		}, $path );

	} else {
		msgErr( __PACKAGE__."::walkTree() '$path' is neither a file nor a directory" );
		$result->{ok} = false;
	}

	return $result;
}

# ------------------------------------------------------------------------------------------------
# Extracts the year from a full scan
# (I):
# - the scan result
# (O):
# - the year, or undef

sub yearFromScan {
	my ( $scan ) = @_;

	my $value = undef;
	$value = $value || $scan->{tags}{TDRC};			# MP3
	$value = $value || $scan->{tags}{TDOR};
	$value = $value || $scan->{tags}{DAY};			# M4A
	$value = $value || $scan->{tags}{DATE};			# set by EasyTag in FLAC (first choice before MusicBrainz), converted by ffmpeg (flac -> mp3) to TDRC
	$value = $value || $scan->{tags}{ORIGINALYEAR};	# set by MusicBrainz, reconducted by ffmpeg (flac -> mp3)
	$value = $value || $scan->{tags}{ORIGINALDATE};	# set by MusicBrainz, reconducted by ffmpeg (flac -> mp3)
	print "yearFromScan() $scan->{path} ".Dumper( $scan->{tags} ) if !$value;
	#msgVerbose( "$scan->{path} year $value" ) if $value;

	return $value;
}

1;
