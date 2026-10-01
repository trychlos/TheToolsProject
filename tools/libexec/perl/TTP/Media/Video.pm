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

package TTP::Media::Video;
die __PACKAGE__ . " must be loaded as TTP::Media::Video\n" unless __PACKAGE__ eq 'TTP::Media::Video';

use strict;
use utf8;
use warnings;

use Data::Dumper;
use File::Basename;
use File::Copy;
use File::Path qw( make_path );
use File::Spec;
use JSON::PP;

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
			id => 'BACKUP_CHECK_ERROR',
			format => "an unfinished repair transaction has left a '%s' backup behind; this must be fixed"
		},
		{
			id => 'BACKUP_CREATE_ERROR',
			format => "unable to create the '%s' backup: %s"
		},
		{
			id => 'BACKUP_RENAME_ERROR',
			format => "unable to rename '%s' backup to expected '%s': %s"
		},
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
			id => 'SPECIAL_CHARS',
			format => "name='%s' exhibits forbidden special characters"
		},
		{
			id => 'SPECIAL_ERRORS',
			format => '%s'
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
	]
};

# have some constant short names, and export them to be addressable with these short names
use constant {
	# check qualifiers
	BITSTREAM => 'BITSTREAM',
	DURATION => 'DURATION',
	SPECIALS => 'SPECIALS',
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
# Check that a repair transsaction didn't left a .backup file behind
# (I):
# - the video filename
# - the result hash
# (O):
# - nothing

sub backupCheck {
	my ( $fname, $result ) = @_;
	msgLog( __PACKAGE__."::backupCheck()" );

	my $backup_fname = "$fname.backup";

	if( -e $backup_fname ){
		setError( $result, setReason( 'BACKUP_CHECK_ERROR', [ $backup_fname ]));

	} else {
		msgLog( __PACKAGE__."::backupCheck() backup '$backup_fname' doesn't exist" );
	}

	# no return value
}

# ------------------------------------------------------------------------------------------------
# Create a backup file before beginning a repair transaction
# (I):
# - the video filename
# - the result hash
# (O):
# - nothing

sub backupCreate {
	my ( $fname, $result ) = @_;
	msgLog( __PACKAGE__."::backupCreate()" );

	my $backup_fname = "$fname.backup";

	if( !copy( $fname, $backup_fname )){
		setError( $result, setReason( 'BACKUP_CREATE_ERROR', [ $backup_fname, $! ]));

	} else {
		msgLog( __PACKAGE__."::backupCreate() backup '$backup_fname' successfully created" );
	}

	# no return value
}

# ------------------------------------------------------------------------------------------------
# Check that a video is consistent (i.e. that all streams are consistently declared and identified)
# (I):
# - the video filename
# - an optional options hash with following keys:
#   > bitstream: whether to test for bitstream pathology, defaulting to true
#   > duration: whether to test for minimal duration, defaulting to -1 (disabled)
#   > timeline: whether to test for timeline pathology, defaulting to true
#   > displayResult: whether to display a check summary per check type, defaulting to true
#   > summaryPrefix: a prefix to be displayed on the start of each summary line, defaulting to ''
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
#   > fname: the checked filename (same than on input)
# + all ERROR reasons are leveled-up to the file-level status
# + findings are only initialized if the corresponding check is enabled

sub check {
	my ( $fname, $opts ) = @_;
	msgLog( __PACKAGE__."::check() fname='$fname'" );

	$opts //= {};
	my $result = checkDo( $fname, $opts );

	return $result;
}

# ------------------------------------------------------------------------------------------------
# The stage 1 has given the media a SUSPICIOUS status due to usage of 'divx_packed' flag
# Sample the file to try to find the 'Discarding excessive bitstream in packed xvid' which would
# confirm the SUSPICIOUS status - else just return to OK
# (I):
# - the result hash
#   > status is 'FINDINGS'
#   > info contains the first-stage ffprobe JSON informations on the current media
# - an optional options hash with following keys:
#   > verifyRun: whether we are running a verify operation, defaulting to false
# (O):
# - nothing

sub checkBitstream {
	my ( $result, $opts ) = @_;
	msgLog( __PACKAGE__."::checkBitstream()" );

	checkBitstreamSample( $result );

	if( $result->{findings}{BITSTREAM}{status} ne OK && $opts->{verifyRun} ){
		$result->{findings}{BITSTREAM}{status} = ERROR;
	}

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

sub checkBitstreamSample {
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
		$found = checkBitstreamSingleSample( $result, $start );
		return if $result->{status} eq ERROR;
		last if $found;
		last if !$spread;
	}
	if( $found ){
		setQualifierStatus( $result, BITSTREAM, REPAIRABLE, setReason( 'STREAM_DIVX_SAMPLE', [ $start ]));
	} else {
		setQualifierStatus( $result, BITSTREAM, OK );
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

sub checkBitstreamSingleSample {
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
		setError( $result, setReason( 'FFMPEG_ERROR', [ "ffmpeg failed at start='$start'" ]));
	}
	return $errorFound;
}

# ------------------------------------------------------------------------------------------------
# Check that a video is consistent (i.e. that all streams are consistently declared and identified)
# (I):
# - the video filename
# - an optional options hash with following keys:
#   > bitstream: whether to test for bitstream pathology, defaulting to true
#   > duration: whether to test for minimal duration, defaulting to -1 (disabled)
#   > specials: whether to test for special characters pathology, defaulting to true
#   > timeline: whether to test for timeline pathology, defaulting to true
#   > displayResult: whether to display a check summary per check type, defaulting to true
#   > summaryPrefix: a prefix to be displayed on the start of each summary line, defaulting to ''
#   > verifyRun: whether we are running a verify operation, defaulting to false
#     when true, then SUSPICIOUS and REPAIRABLE files are set to ERROR'neous
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
#     - SPECIALS: a hash with following keys:
#       > status: OK or REPAIRABLE
#       > reasons: an array ref of error reasons, empty because this check doesn't identify errors
#         but left here for homogeneity reasons
#     - TIMELINE: a hash with following keys:
#       > status: OK, SUSPICIOUS or REPAIRABLE
#       > reasons: an array ref of reasons
#   > info: the ffprobe informations
#   > fname: the checked filename (same than on input)
# + all ERROR reasons are leveled-up to the file-level status
# + findings are only initialized if the corresponding check is enabled

sub checkDo {
	my ( $fname, $opts ) = @_;
	msgLog( __PACKAGE__."::checkDo() fname='$fname'" );

	# set default values
	$opts //= {};
	$opts->{bitstream} //= true;
	$opts->{duration} //= -1;
	$opts->{specials} //= true;
	$opts->{timeline} //= true;
	$opts->{displayResult} //= true;
	$opts->{verifyRun} //= false;

	# prepare the returned result
	my $result = {
		status => OK,
		reasons => [],
		info => undef,
		fname => $fname
	};
	if( $opts->{bitstream} ){
		$result->{findings}{BITSTREAM} = {
			status => OK,
			reasons => []
		};
	}
	if( $opts->{duration} > 0 && !$opts->{verifyRun} ){
		$result->{findings}{DURATION} = {
			status => OK,
			reasons => []
		};
	}
	if( $opts->{specials} ){
		$result->{findings}{SPECIALS} = {
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
	# should never happen as the verb is expected to protect against that - so the warning
	if( !$opts->{bitstream} && $opts->{duration} <= 0 && !$opts->{specials} && !$opts->{timeline} ){
		msgWarn( __PACKAGE__."::check() nothing to do for '$fname'" );
		return $result;
	}

	# before the first stage, check that a previous transaction didn't left a .backup file behind
	# status is OK or ERROR
	backupCheck( $fname, $result );
	if( $result->{status} ne OK ){
		return $result;
	}

	# first stage: the cheapest metadata check
	# if nothing suspicious is found: then this cheapest path ends here
	# status is OK or ERROR
	ffprobeInfo( $fname, $result );
	if( $result->{status} ne OK ){
		return $result;
	}

	my $qualifiers = ffprobeStage( $result, $opts );
	return $result if $result->{status} ne FINDINGS;

	# any SUSPICIOUS media should have set a qualifier which determine
	# some more expensive tests to be done to confirm or infirm the suspicion
	# the status begins its life with 'OK'

	if( scalar( grep( /BITSTREAM/, @{$qualifiers} ))){
		checkBitstream( $result, $opts );
	}

	# if minimal duration has been requested and is not satisfied, there is nothing we can do here to repair
	# just keep the media failed
	if( scalar( grep( /DURATION/, @{$qualifiers} ))){
		# nothing to do to confirm a failed duration
	}

	if( scalar( grep( /SPECIALS/, @{$qualifiers} ))){
		# nothing to do to confirm a repairable special chars anomaly
	}

	if( scalar( grep( /TIMELINE/, @{$qualifiers} ))){
		checkTimeline( $result, $opts );
	}

	consolidateStatus( $result);
	return $result;
}

# ------------------------------------------------------------------------------------------------
# The stage 1 has given the media a SUSPICIOUS status due to a difference between a video stream
# duration and the container duration which happens to be greater than the accepted tolerance
# Handle complementary checks for a possible - and maybe repairable - anomaly
# (I):
# - the result hash
#   > status is 'FINDINGS'
#   > info contains the first-stage ffprobe JSON informations on the current media
# - an optional options hash with following keys:
#   > verifyRun: whether we are running a verify operation, defaulting to false
# (O):
# - <nothing>
# - the result hash may have been updated

sub checkTimeline {
	my ( $result, $opts ) = @_;

	msgLog( "checkTimeline() $result->{info}{format}{filename}" );

	# count packets
	# if we find something suspicious, we will ask a confirmation to GStreamer
	ffprobeInfo( $result->{info}{format}{filename}, $result, { countPackets => true });
	if( $result->{status} eq ERROR ){
		return;
	}

	# check in each video stream that the count of packets is compatible with the stream duration
	# return unless still SUSPICIOUS
	checkTimelineStage2( $result );
	return if $result->{status} eq ERROR;
	return if $result->{findings}{TIMELINE}{status} ne SUSPICIOUS;

	# ask a confirmation to GStreamer
	my $durationGet = durationGet( $result );
	return if $result->{status} eq ERROR;

	checkTimelineStage3( $result, $durationGet );
	return if $result->{status} eq ERROR;

	if( $result->{findings}{TIMELINE}{status} ne OK && $opts->{verifyRun} ){
		$result->{findings}{TIMELINE}{status} = ERROR;

	# if said REPAIRABLE, make sure all streams can be handled
	} elsif( $result->{findings}{TIMELINE}{status} eq REPAIRABLE ){
		checkTimelineHandledStreams( $result );
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

sub checkTimelineHandledStreams {
	my ( $result ) = @_;

    my $format = $result->{info}{format} // {};
    my $formatName = $format->{format_name} // 'unknown';
	my $formatDuration = $result->{info}{format}{duration};

	msgLog( "checkTimelineHandledStreams() ".
		"result->{info}{format}{filename} format='$formatName'" );

    if( !timelineContainerSupported( $format )){
        setQualifierStatus( $result, TIMELINE, SUSPICIOUS,
            setReason( 'CONTAINER_UNSUPPORTED_FOR_REPAIR', [ $formatName ])
        );
        return;
    }

	foreach my $stream ( @{$result->{info}{streams} || []} ){
		msgLog( "checkTimelineHandledStreams() ".
			"stream #$stream->{index} codec_type='$stream->{codec_type}' codec_name='$stream->{codec_name}'" );

		if( !timelineStreamSupported( $stream )){
			my $index = $stream->{index} // '?';
			my $type = $stream->{codec_type} // 'unknown';
			my $codec = $stream->{codec_name} // 'unknown';

			setQualifierStatus( $result, TIMELINE, SUSPICIOUS,
				setReason( 'STREAM_UNSUPPORTED_FOR_REPAIR', [
					$index, $type, $codec
				]));

			return;
		}
	}

	msgLog( "checkTimelineHandledStreams() all streams validated for repair" );
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

sub checkTimelineStage2 {
	my ( $result ) = @_;

	my $formatDuration = $result->{info}{format}{duration};
	msgLog( "checkTimelineStage2() $result->{info}{format}{filename}" );

	foreach my $stream ( @{$result->{info}{streams} || []} ){
		msgLog( "checkTimelineStage2() stream #$stream->{index} codec_type='$stream->{codec_type}'" );
		next if $stream->{codec_type} ne 'video';

		my $packets = $stream->{nb_read_packets};
		msgLog( "checkTimelineStage2() stream #$stream->{index} packets=".( $packets // '(undefined)' ));

		if( defined( $packets )){
			if( $packets !~ /^\d+(?:\.\d+)?$/ || $packets <= 0 ){
				setError( $result, setReason( 'STREAM_PACKETS_INVALID', [ $stream->{index}, $packets ]));

			} elsif( $formatDuration > $Const->{durationThreshold}{minDuration} && 
						$packets < $Const->{durationThreshold}{minPackets} ){
				setQualifierStatus( $result, TIMELINE, SUSPICIOUS,
					setReason( 'STREAM_PACKETS_THRESHOLD',
						[ $stream->{index}, $packets, sprintf( "%.1f", $formatDuration )]));

			} else {
				msgLog( "checkTimelineStage2() ".
					"stream #$stream->{index} formatDuration is compatible with packets count" );
			}
		} else {
			setQualifierStatus( $result, TIMELINE, SUSPICIOUS,
				setReason( 'STREAM_PACKETS_UNDEFINED', [ $stream->{index} ]));
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

sub checkTimelineStage3 {
	my ( $result, $durationGet ) = @_;

	my $formatDuration = $result->{info}{format}{duration};
	msgLog( "checkTimelineStage3() $result->{info}{format}{filename} durationGet='$durationGet'" );

	my $delta = durationDelta( $durationGet, $formatDuration );
	msgLog( "checkTimelineStage3() ".
		"formatDuration=".sprintf( "%.3f", $formatDuration )." ".
		"delta=".sprintf( "%.3f", $delta )." ".
		"durationTolerance=".sprintf( "%.3f", $Const->{durationTolerance}{gstreamer} ));

	# a normal container duration (say 2500s),
	#   associatied with a very low video stream duration (often zero),
	#   associated with a very low count of packets reported by ffmpeg
	#   while gstreamer confirms the duration of the whole video
	#   -> is a known and repairable issue
	if( $delta < $Const->{durationTolerance}{gstreamer} ){
		setQualifierStatus( $result, TIMELINE, REPAIRABLE, setReason( 'GST_DURATION_DELTA',
			[ sprintf( "%.3f", $durationGet )]));
		return;
	}

	# but:
	# a normal container duration (say 2500s),
	#   associatied with a very low video stream duration (often zero),
	#   associated with a very low count of packets reported by ffmpeg
	#   but gstreamer DOES NOT confirms the duration of the whole video
	# the issue has not been yet found
	setQualifierStatus( $result, TIMELINE, OK );

	# no return value
}

# ------------------------------------------------------------------------------------------------
# Consolidate all check status into the global file-level result status
#  Goals are:
#  - any ERROR is leveled-up to file-level status
#  - to display a FINDINGS status if and only if one check has something to say
# (I):
# - the result hash ref
# (O):
# - the file-level result status
# + the result status hash has been updated

sub consolidateStatus {
	my ( $result ) = @_;

	# do not modify nor override an 'ERROR' status
	return if $result->{status} eq ERROR;

	# either OK, ERROR or FINDINGS
	my $findings = false;
	my $error = false;
	foreach my $key( sort keys( %{$result->{findings}} )){
		if( $result->{findings}{$key}{status} eq ERROR ){
			$error = true;
			last;
		}
		if( $result->{findings}{$key}{status} ne OK ){
			$findings = true;
		}
	}
	$result->{status} = $error ? ERROR : ( $findings ? FINDINGS : OK );

	msgLog( "consolidateStatus() $result->{status}" );
	return $result->{status};
}

# ------------------------------------------------------------------------------------------------
# Display an execution summary
# (I):
# - the result hash
# - an optional options hash with following keys:
#   > bitstream: whether to test for bitstream pathology, defaulting to true
#   > duration: whether to test for minimal duration, defaulting to -1 (disabled)
#   > timeline: whether to test for timeline pathology, defaulting to true
#   > displayResult: whether to display a check summary per check type, defaulting to true
#   > summaryPrefix: a prefix to be displayed on the start of each summary line, defaulting to ''
#   > repairRun: whether we are displaying the repair summary, defaulting to false
# (O):
# - <nothing>

sub displayResult {
	my ( $result, $opts ) = @_;
	msgLog( __PACKAGE__."::displayResult()" );

	$opts //= {};
	$opts->{repairRun} //= false;

	my $prefix = $opts->{summaryPrefix} // '';

	# file-level summary
	# can be OK, FINDINGS or ERROR
	msgOut( sprintf( "%s%-8s %s", $prefix, $result->{status}, $result->{fname} ));
	if( $result->{status} ne OK ){
		# if error
		foreach my $reason ( @{$result->{reasons}} ){
			msgOut( sprintf( "%s%-8s %s", $prefix, '', sprintf( $reason->{format}, @{$reason->{args} // [] })));
		}
		# for findings
		foreach my $key ( sort keys( %{$result->{findings}} )){
			foreach my $reason ( @{$result->{findings}{$key}{reasons}} ){
				msgOut( sprintf( "%s%-8s %s", $prefix, '', sprintf( $reason->{format}, @{$reason->{args} // [] })));
			}
		}
	}
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

sub durationGet {
	my ( $result ) = @_;

	my $args = [
		$result->{info}{format}{filename}
	];
	my $res = TTP::commandExec({ command => 'gst-discoverer-1.0', args => $args });

	if( !$res->{success} ){
		msgErr( __PACKAGE__."::durationGet() gst-discoverer-1.0 failed for '$result->{info}{format}{filename}'" );
		setError( $result, setReason( 'GST_ERROR',
			[ "durationGet() gst-discoverer-1.0 failed for '$result->{info}{format}{filename}'" ]));
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
		setError( $result, setReason( 'GST_ERROR',
			[ "durationGet() unable to find the duration reported by GStreamer" ]));
		return undef;
	}

	if( $duration !~ /^\d+(?:\.\d+)?$/ ){
		setError( $result, setReason( 'GST_ERROR',
			[ "durationGet() duration='$duration' is not valid" ]));
		return undef;
	}

	if( $duration < 0 ){
		setError( $result, setReason( 'GST_ERROR',
			[ "durationGet() duration='$duration' is not valid" ]));
		return undef;
	}

	return $duration;
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
# - the got informations as a hash ref
# + the result hash has been updated:
#   > info: the decoded ffprobe JSON structure, or undef on error
#   > reasons: if error, an array ref of error reason(s)
#   > status: 'OK' or 'ERROR'

sub ffprobeInfo {
	my ( $fname, $result, $opts ) = @_;

	ffprobeInfoGet( $fname, $result, $opts );

	if( $result->{status} ne ERROR ){
		ffprobeInfoCheck( $result );
	}

	return $result->{info};
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
# + the result hash has been updated:
#   > reasons: if error, an array ref of error reason(s)
#   > status: 'OK' or 'ERROR'

sub ffprobeInfoCheck {
	my ( $result ) = @_;

	if( !$result->{info} ){
		setError( $result, setReason( 'FFPROBE_ERROR',
			[ "ffprobeInfoCheck() called while 'info' is not defined" ]));

	} elsif( !$result->{info}{format} ){
		setError( $result, setReason( 'FFPROBE_ERROR',
			[ "ffprobeInfoCheck() info->{format} is not defined" ]));

	} else {
		# check filename
		if( !$result->{info}{format}{filename} ){
			setError( $result, setReason( 'FFPROBE_ERROR',
				[ 'ffprobeInfoCheck() info->{format}{filename} is not defined' ]));
		} else {
			msgLog( __PACKAGE__."::ffprobeInfoCheck() info->{format}{filename}='$result->{info}{format}{filename}'" );
		}

		# check container duration
		if( defined( $result->{info}{format}{duration} )){
			my $duration = $result->{info}{format}{duration};
			if( $duration !~ /^\d+(?:\.\d+)?$/  || $duration <= 0 ){
				setError( $result, setReason( 'FFPROBE_ERROR',
					[ "ffprobeInfoCheck() info->{format}{duration}='$duration' is not valid" ]));
			} else {
				msgLog( __PACKAGE__."::ffprobeInfoCheck() info->{format}{duration}='$duration'" );
			}
		} else {
			setError( $result, setReason( 'FFPROBE_ERROR',
				[ "ffprobeInfoCheck() info->{format}{duration} is not defined" ]));
		}
	}

	msgLog( __PACKAGE__."::ffprobeInfoCheck() status='$result->{status}'" );
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
# - the got informations as a hash ref, or undef
# + the result hash has been updated:
#   > info: the decoded ffprobe JSON structure, or undef on error
#   > reasons: if error, an array ref of error reason(s)
#   > status: 'OK' or 'ERROR'

sub ffprobeInfoGet {
	my ( $fname, $result, $opts ) = @_;
	$opts //= {};
	msgLog( __PACKAGE__."::ffprobeInfoGet() fname='$fname'" );

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
			$reason = setReason( 'FFPROBE_ERROR', [ "ffprobeInfoGet() unable to decode ffprobe output for '$fname': $@" ] );
			$decoded = undef;
		}
	} else {
		$reason = setReason( 'FFPROBE_ERROR', [ "ffprobeInfoGet() failed for '$fname'" ] );
	}

	# summary and sanity checks
	if( $reason ){
		setError( $result, $reason );
		if( $decoded ){
			msgErr( __PACKAGE__."::ffprobeInfoget() have both reason and decoded" );
		}
	} else {
		if( !$decoded ){
			$result->{status} = ERROR;
			msgErr( __PACKAGE__."::ffprobeInfoget() have neither reason nor decoded" );
		}
	}

	if( $decoded ){
		$result->{info} = $decoded;
		msgLog( __PACKAGE__."::ffprobeInfoGet() status='$result->{status}'" );
	}

	return $decoded;
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

sub ffprobeStage {
	my ( $result, $opts ) = @_;

	my $qualifiers = [];
	msgLog( __PACKAGE__."::ffprobeStage() fname='$result->{info}{format}{filename}'" );

	my $formatDuration = $result->{info}{format}{duration};

	foreach my $stream ( @{$result->{info}{streams} || []} ){
		msgLog( __PACKAGE__."::ffprobeStage() stream #$stream->{index} codec_type='$stream->{codec_type}'" );
		next if $stream->{codec_type} ne 'video';

		if( $opts->{bitstream} ){
			msgLog( __PACKAGE__."::ffprobeStage() stream #$stream->{index} checking for bitstream pathology" );
			if( defined( $stream->{divx_packed}) && $stream->{divx_packed} eq 'true' ){
				my $qualifier = BITSTREAM;
				setQualifierStatus( $result,
					$qualifier, SUSPICIOUS,
					setReason( 'STREAM_DIVX_PACKED', [ $stream->{index} ]));
				push( @{$qualifiers}, $qualifier );
			} else {
				msgLog( __PACKAGE__."::ffprobeStage() stream #$stream->{index} bitstream pathology not identified" );
			}
		}

		if( $opts->{timeline} ){
			msgLog( __PACKAGE__."::ffprobeStage() stream #$stream->{index} checking for timeline pathology" );
			my $duration = $stream->{duration};
			msgLog( __PACKAGE__."::ffprobeStage() stream #$stream->{index} duration=".( $duration // '(undefined)' ));
			if( defined( $duration ) && $duration ne 'N/A' ){
				if( $duration !~ /^\d+(?:\.\d+)?$/ || $duration < 0 ){
					setError( $result, setReason( 'STREAM_DURATION_INVALID', [ $stream->{index}, $duration ]));

				} else {
					my $delta = durationDelta( $duration, $formatDuration );
					msgLog( __PACKAGE__."::ffprobeStage() stream #$stream->{index} ".
						"formatDuration=".sprintf( "%.3f", $formatDuration )." ".
						"delta=".sprintf( "%.3f", $delta )." ".
						"durationTolerance=".sprintf( "%.3f", $Const->{durationTolerance}{video} ));

					# video stream duration should be close or equal to the known container duration
					# we accept a 10% tolerance, but a greater delta makes the media suspicious
					if( $delta > $Const->{durationTolerance}{video} ){
						my $qualifier = TIMELINE;
						setQualifierStatus( $result,
							$qualifier, SUSPICIOUS,
							setReason( 'STREAM_DURATION_DELTA', 
								[ $stream->{index}, sprintf( "%.3f", $duration ), sprintf( "%.3f", $formatDuration ) ]));
						push( @{$qualifiers}, $qualifier );
		
					} else {
						msgLog( __PACKAGE__."::ffprobeStage() stream #$stream->{index} delta is inside the accepted tolerance" );
					}
				}
			} else {
				# video stream with undefined duration
				#  -> no video-duration check applicable for that stream
				# this can be normal in particular for Matroska containers
				msgLog( __PACKAGE__."::ffprobeStage() stream #$stream->{index} duration not considered" );
			}
		}
	}

	if( $opts->{duration} > 0 && !$opts->{verifyRun} ){
		msgLog( __PACKAGE__."::ffprobeStage() checking for duration greater than $opts->{duration}s" );
		if( $opts->{duration} > $formatDuration ){
			my $qualifier = DURATION;
			setQualifierStatus( $result,
				$qualifier, FAILED,
				setReason( 'MEDIA_MIN_DURATION',
					[ sprintf( "%.3f", $formatDuration ), sprintf( "%.3f", $opts->{duration} ) ]));
			push( @{$qualifiers}, $qualifier );
		} else {
			msgLog( __PACKAGE__."::ffprobeStage() formatDuration is accepted" );
		}
	}

	# have to check each element of the full filename
	if( $opts->{specials} ){
		msgLog( __PACKAGE__."::ffprobeStage() checking for special characters" );
		my $qualifier = SPECIALS;
		my ( $base, $dir, $suffix ) = File::Basename::fileparse( $result->{info}{format}{filename}, qr/\.[^.]*/ );
		my $names = [ "$base$suffix" ];
		push( @{$names}, File::Spec->splitdir( $dir ));
		my $errs = 0;
		foreach my $piece ( @{$names} ){
			if( TTP::Media::hasForbiddenChars( $piece )){
				setQualifierStatus( $result,
					$qualifier, REPAIRABLE,
					setReason( 'SPECIAL_CHARS', [ $piece ]));
				$errs += 1;
			}
		}
		if( $errs ){
			push( @{$qualifiers}, $qualifier );
		} else {
			msgLog( __PACKAGE__."::ffprobeStage() no specials detected" );
		}
	}

	# doesn't override a potential file-level ERROR
	return [] if $result->{status} eq ERROR;

	# all what we may say here is whether we have found something
	$result->{status} = FINDINGS if scalar( @{$qualifiers} );
	return $qualifiers;
}

# ------------------------------------------------------------------------------------------------
# Whether the filename exhibits a path which may let us think this is a video file
# (I):
# - the full file pathname
# (O):
# - true if this may be a video file, false else

sub isCapable {
	my ( $path ) = @_;

	my ( undef, undef, $suffix ) = File::Basename::fileparse( $path, qr/\.[^.]*/ );

	my $video = grep( { lc( $suffix ) eq $_ } @{$Const->{videoExtensions}} ) ? true : false;

	return $video;
}

# ------------------------------------------------------------------------------------------------
# Repair a video where check() has identified a repairable pathology
# (I):
# - the check results as a hash ref
# - an optional options hash with following keys:
#   > bitstream: whether to test for bitstream pathology, defaulting to true
#   > specials: whether to test for special characters pathology, defaulting to true
#   > timeline: whether to test for timeline pathology, defaulting to true
#   > keepOrig: whether to keep the original file, defaulting to true
# (O):
# - a hash with following keys:
#   > status: 'OK' or 'ERROR'
#   > reasons: an array ref of error reasons
#   > findings: a hash ref per done repair:
#     - BITSTREAM: a hash with following keys:
#       > status: OK or ERROR
#       > reasons: an array ref of reasons
#     - SPECIALS: a hash with following keys:
#       > status: OK or ERROR
#       > reasons: an array ref of reasons
#     - TIMELINE: a hash with following keys:
#       > status: OK or ERROR
#       > reasons: an array ref of reasons
#   > info: the ffprobe informations
#
# nb: 'findings' is the same name than in check() to be able to reuse '$result'-oriented functions

sub repair {
	my ( $checkResult, $opts ) = @_;

	my $fname = $checkResult->{fname};
	msgLog( __PACKAGE__."::repair() fname='$fname'" );

	$opts //= {};
	$opts->{bitstream} //= true;
	$opts->{specials} //= true;
	$opts->{timeline} //= true;
	$opts->{displayResult} //= true;
	$opts->{keepOrig} //= true;

	my $new_fname = $fname;

	# prepare the returned result
	my $result = {
		status => OK,
		reasons => [],
		info => undef,
		fname => $new_fname,
		findings => {}
	};

	# a guard against a pre-existant backup
	#  this is normally a check error, but just to be sure
	backupCheck( $checkResult->{fname}, $result );
	return $result if $result->{status} eq ERROR;

	# create a backup file before beginning with any repair
	backupCreate( $checkResult->{fname}, $result );
	return $result if $result->{status} eq ERROR;

	my $errorsCount = 0;

	if( $opts->{bitstream} && $checkResult->{findings}{BITSTREAM}{status} eq REPAIRABLE ){
		$result->{findings}{BITSTREAM} = {
			status => OK,
			reasons => []
		};
		msgOut( sprintf( "%-8s %s", " ", "trying to repair bitstream..."));
		repairBitstream( $result, $fname, $checkResult, $opts );
		$fname = $result->{fname};
		$errorsCount += 1 if $result->{findings}{BITSTREAM}{status} ne OK;
	}

	if( $opts->{specials} && $checkResult->{findings}{SPECIALS}{status} eq REPAIRABLE ){
		$result->{findings}{SPECIALS} = {
			status => OK,
			reasons => []
		};
		msgOut( sprintf( "%-8s %s", " ", "trying to repair special characters..."));
		repairSpecials( $result, $fname, $checkResult, $opts );
		$fname = $result->{fname};
		$errorsCount += 1 if $result->{findings}{SPECIALS}{status} ne OK;
	}

	if( $opts->{timeline} && $checkResult->{findings}{TIMELINE}{status} eq REPAIRABLE ){
		$result->{findings}{TIMELINE} = {
			status => OK,
			reasons => []
		};
		msgOut( sprintf( "%-8s %s", " ", "trying to repair timeline..."));
		repairTimeline( $result, $fname, $checkResult, $opts );
		$fname = $result->{fname};
		$errorsCount += 1 if $result->{findings}{TIMELINE}{status} ne OK;
	}

	# if no error happened, then we can safely remove the backup, either keeping it as an original
	#  or just removing it
	if( !$errorsCount ){
		my $backup_fname = "$checkResult->{fname}.backup";
		my $orig_fname = "$checkResult->{fname}.orig";
		if( $opts->{keepOrig} ){
			if( rename( $backup_fname, $orig_fname )){
				msgLog( __PACKAGE__."::repair() original copy kept as '$orig_fname'" );
			} else {
				setError( $result, setReason( 'BACKUP_RENAME_ERROR', [ $backup_fname, $orig_fname, $! ]));
			}
		} else {
			msgLog( __PACKAGE__."::repair() deleting '$backup_fname'" );
			unlink( $backup_fname );
			# remove the directory (last level only) if it becomes empty
		    my ( undef, $backup_dir, undef ) = File::Basename::fileparse( $backup_fname, qr/\.[^.]*/ );
			TTP::Path::removeEmptyDir( $backup_dir );
		}
	}

	consolidateStatus( $result );
	return $result;
}

# ------------------------------------------------------------------------------------------------
# Repair an 'excessive bitstream' divx video
# (I):
# - the repair result hash for this file
# - the video filename
# - the check() result hash
# - an optional options has with following keys:
#   > keepOrig, whether to keep a copy of the original file, defaulting to true
# (O):
# - the new filename (should be unchanged)
# + the global result->{findings}{BITSTREAM}{status} has been updated

sub repairBitstream {
	my ( $repairResult, $fname, $checkResult, $opts ) = @_;

	my $new_fname = $fname;

	my ( undef, undef, $suffix ) = File::Basename::fileparse( $fname, qr/\.[^.]*/ );
	my $tmp_fname = "$fname.tmp$suffix";

    # Do not overwrite anything
    if( -e $tmp_fname ){
        setQualifierStatus( $repairResult, BITSTREAM, ERROR,
            setReason( 'GST_REPAIR_ERROR',
                [ "temp output already exists: '$tmp_fname'" ]));
        return $fname;
    }

	my $args = [
		'-i', $fname,
		'-map', '0',
		'-c', 'copy',
		'-bsf:v',
		'mpeg4_unpack_bframes',
		$tmp_fname
	];

	my $res = TTP::commandExec({ command => 'ffmpeg', args => $args });

	if( !$res->{success} ){
		unlink( $tmp_fname );
		setQualifierStatus( $repairResult, BITSTREAM, ERROR, setReason( 'FFMPEG_ERROR', [
			"unable to successfully execute ffmpeg to repair \'$fname\'"
		]));
		return $fname;
	}

    if( !-s $tmp_fname ){
        unlink( $tmp_fname );
		setQualifierStatus( $repairResult, BITSTREAM, ERROR, setReason( 'FFMPEG_ERROR', [
			"ffmpeg produced an empty file '$tmp_fname'"
		]));
        return $fname;
    }

	# install the repaired copy
	if( rename( $tmp_fname, $new_fname )){
		msgLog( __PACKAGE__."::repairBitstream() repaired copy successfully installed as '$new_fname'" );

	} else {
		setQualifierStatus( $repairResult, BITSTREAM, ERROR, setReason( 'FFMPEG_ERROR', [
			"unable to install '$new_fname': $!"
		]));
		return $fname;
	}

	# filename is left unchanged by that repair
	setQualifierStatus( $repairResult, BITSTREAM, OK );
	$repairResult->{fname} = $new_fname;
	return $new_fname;
}

# ------------------------------------------------------------------------------------------------
# Repair a filename which exhibits forbidden special characters
# Reminder: these 'forbidden' special characters are those which are not supported by either
#  KDE Connect application or Android OS or FAT32 filesystems. They prevent a correct synchronisation
#  between a NFS storage space and various remote devices.
# (I):
# - the repair result hash for this file
# - the video filename
# - the check() result hash
# - an optional options has with following keys:
#   > keepOrig, whether to keep a copy of the original file, defaulting to true
# (O):
# - the new filename
# + the global result->{findings}{SPECIALS}{status} has been updated

sub repairSpecials {
	my ( $repairResult, $fname, $checkResult, $opts ) = @_;

	my ( $base, $dir, $suffix ) = File::Basename::fileparse( $fname, qr/\.[^.]*/ );
	my @names = File::Spec->splitdir( $dir );
	push( @names, "$base$suffix" );
	my @new_names = ();
	foreach my $piece ( @names ){
		push( @new_names, TTP::Media::convertStr( $piece ));
	}
	my $new_base = pop( @new_names );
	my $new_fname = File::Spec->catfile( @new_names, $new_base );
	my $new_dir = File::Spec->catdir( @new_names );

	# install the repaired (renamed) copy
	if( make_path( $new_dir ) && move( $fname, $new_fname )){
		msgLog( __PACKAGE__."::repairSpecials() repaired (renamed) copy successfully installed as '$new_fname'" );

	} else {
		setQualifierStatus( $repairResult, SPECIALS, ERROR, setReason( 'SPECIALS_ERROR', [
			"unable to install '$new_fname': $!"
		]));
		return $fname;
	}

	# filename is changed by that repair
	setQualifierStatus( $repairResult, SPECIALS, OK );
	$repairResult->{fname} = $new_fname;
	return $new_fname;
}

# ------------------------------------------------------------------------------------------------
# Repair a broken MP4 timeline by remuxing supported streams into Matroska
# without transcoding.
# (I):
# - the global repair result hash
# - the video filename
# - the check() result hash
# - an optional options has with following keys:
#   > keepOrig, whether to keep a copy of the original file, defaulting to true
# (O):
# - the new filename
# + the global result->{findings}{TIMELINE}{status} has been updated

sub repairTimeline {
    my ( $repairResult, $fname, $checkResult, $opts ) = @_;

    my ( $base, $dir, $suffix ) = File::Basename::fileparse( $fname, qr/\.[^.]*/ );
    my $new_fname = File::Spec->catfile( $dir, "$base.mkv" );
    my $tmp_fname = "$new_fname.part";

    # Do not overwrite anything.
    if( -e $new_fname ){
        setQualifierStatus( $repairResult, TIMELINE, ERROR,
            setReason( 'GST_REPAIR_ERROR',
                [ "destination already exists: '$new_fname'" ]));
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
				setQualifierStatus( $repairResult, TIMELINE, ERROR,
					setReason( 'GST_REPAIR_ERROR', [
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
				'mux.'
			));

			$video_idx += 1;

		} elsif( $type eq 'audio' ){

			if( $codec ne 'aac' ){
				setQualifierStatus( $repairResult, TIMELINE, ERROR,
					setReason( 'GST_REPAIR_ERROR', [
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
				'mux.'
			));

			$audio_idx += 1;

		} elsif( $type eq 'subtitle' ){

			if( $codec ne 'mov_text' ){
				setQualifierStatus( $repairResult, TIMELINE, ERROR,
					setReason( 'GST_REPAIR_ERROR', [
						"unsupported subtitle codec '$codec' in '$fname'"
					]));
				return $fname;
			}

			push( @branches,
				"d.subtitle_$subtitle_idx",
				'!',
				'queue',
				'!',
				'mux.'
			);

			$subtitle_idx += 1;

		} else {
			setQualifierStatus( $repairResult, TIMELINE, ERROR,
				setReason( 'GST_REPAIR_ERROR', [
					"unsupported stream type '$type' codec '$codec' in '$fname'"
				]));
			return $fname;
		}
	}

	# theorically impossible guards

	if( !$video_idx ){
		setQualifierStatus( $repairResult, TIMELINE, ERROR,
			setReason( 'GST_REPAIR_ERROR',
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
        setQualifierStatus( $repairResult, TIMELINE, ERROR, setReason( 'GST_REPAIR_ERROR', [
			"unable to successfully execute GStreamer to repair '$fname'"
		]));
        return $fname;
    }

    if( !-s $tmp_fname ){
        unlink( $tmp_fname );
        setQualifierStatus( $repairResult, TIMELINE, ERROR, setReason( 'GST_REPAIR_ERROR', [
			"GStreamer produced an empty file '$tmp_fname'"
		]));
        return $fname;
    }

    # Install repaired Matroska
	#  must be done here so that the next repair get a valid video filename on input
    if( rename( $tmp_fname, $new_fname )){
		msgLog( __PACKAGE__."::repairTimeline() repaired copy successfully installed as '$new_fname'" );

	} else {
		setQualifierStatus( $repairResult, TIMELINE, ERROR, setReason( 'GST_REPAIR_ERROR', [
			"unable to install '$new_fname': $!"
		]));
        return $fname;
    }

	# as we have defined a new container, have to remove the old one
	if( unlink( $fname )){
		msgLog( __PACKAGE__."::repairTimeline() suspicious file successfully removed" );

	} else {
		setQualifierStatus( $repairResult, TIMELINE, ERROR, setReason( 'GST_REPAIR_ERROR', [
			"unable to remove original '$fname': $!"
		]));
	    $repairResult->{fname} = $new_fname;
		return $new_fname;
	}

    setQualifierStatus( $repairResult, TIMELINE, OK );
    $repairResult->{fname} = $new_fname;
    return $new_fname;
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

sub setError {
	my ( $result, $reasons ) = @_;

	$result->{status} = ERROR;

	if( ref( $reasons ) eq 'HASH' ){
		push( @{$result->{reasons}}, $reasons );
		msgLog( "setError() $reasons->{id} ".sprintf( $reasons->{format}, @{$reasons->{args}} ));

	} elsif( ref( $reasons ) eq 'ARRAY' ){
		foreach my $reason ( @{$reasons} ){
			push( @{$result->{reasons}}, $reason );
			msgLog( "setError() $reason->{id} ".sprintf( $reason->{format}, @{$reason->{args}} ));
		}

	} else {
		msgErr( __PACKAGE__."::setError() reasons is neither a hash nor an array" );
	}
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

sub setQualifierStatus {
	my ( $result, $qualifier, $status, $reasons ) = @_;

	$result->{findings}{$qualifier}{status} = $status;

	# clear the reasons when status is set to 'OK'
	if( $status eq OK ){
		$result->{findings}{$qualifier}{reasons} = [];

	# else push new available reasons
	} elsif( $reasons ){
		if( ref( $reasons ) eq 'HASH' ){
			push( @{$result->{findings}{$qualifier}{reasons}}, $reasons );
			msgLog( "setQualifierStatus() $reasons->{id} ".sprintf( $reasons->{format}, @{$reasons->{args}} ));

		} elsif( ref( $reasons ) eq 'ARRAY' ){
			foreach my $reason ( @{$reasons} ){
				push( @{$result->{findings}{$qualifier}{reasons}}, $reason );
				msgLog( "setQualifierStatus() $reason->{id} ".sprintf( $reason->{format}, @{$reason->{args}} ));
			}

		} else {
			msgErr( __PACKAGE__."::setQualifierStatus() () reasons is neither a hash nor an array" );
		}

	# warn if not OK but no reason
	} else {
		msgWarn( "setQualifierStatus() qualifier='$qualifier' status='$status' but no proposed reason" );
	}
}

# ------------------------------------------------------------------------------------------------
# Find the invoked reason, and return it after having build the relevant message
# (I):
# - the reason identfier
# - an array of format arguments
# (O):
# - the reason hash, with the current arguments

sub setReason {
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

	msgErr( __PACKAGE__."::setReason() identifier not found: '$id'" );
	return undef;
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
# Verify that a repaired video is fine
# (I):
# - the repair results as a hash ref
# - an optional options hash with following keys:
#   > bitstream: whether to test for bitstream pathology, defaulting to true
#   > duration: whether to test for minimal duration, defaulting to -1 (disabled)
#   > timeline: whether to test for timeline pathology, defaulting to true
#   > displayResult: whether to display a check summary per check type, defaulting to true
#   > summaryPrefix: a prefix to be displayed on the start of each summary line, defaulting to ''
# (O):
# - a hash with following keys:
#   > status: OK or ERROR
#   > reasons: an array ref of error reasons
#   > findings: a hash ref per done check:
#     - BITSTREAM: a hash with following keys:
#       > status: OK or ERROR
#       > reasons: an array ref of reasons
#     - TIMELINE: a hash with following keys:
#       > status: OK or ERROR
#       > reasons: an array ref of reasons
#   > info: the ffprobe informations
#   > fname: the checked filename (same than on input)
# + all ERROR reasons are leveled-up to the file-level status (but not the reasons)
# + findings are only initialized if the corresponding check is enabled

sub verify {
	my ( $repairResult, $opts ) = @_;

	my $fname = $repairResult->{fname};
	msgLog( __PACKAGE__."::verify() fname='$fname'" );

	$opts //= {};
	$opts->{verifyRun} = true;

	msgOut( sprintf( "%-8s %s", " ", "verifying..." ));

	return checkDo( $fname, $opts );
}

1;
