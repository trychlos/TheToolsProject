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
use File::Find;
use File::Spec;
use Scalar::Util qw( looks_like_number );

use TTP;
use vars::global qw( $ep );

use TTP::Constants qw( :all );
use TTP::Finder;
use TTP::Message qw( :all );
use TTP::Path;

my $Const = {
	# KDE Connect / Android /FAT32 filesystems do not like these characters
	forbidden => {
		'\s*\?' => '',
		'\s*:' => ' -',
		'[<>\/\\\|]' => '',
		'"' => '\'',
		'\*' => '_'
	}
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
		msgErr( $res->{results}[0]{stderr} );
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
# Convert the given string to replace forbidden chars
# (I):
# - the string to be converted
# (O):
# - the converted string

sub convertStr {
	my ( $str ) = @_;

	foreach my $ch ( keys %{$Const->{forbidden}} ){
		my $rep = $Const->{forbidden}{$ch};
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

sub isAudio {
	my ( $path ) = @_;

	my $audio = Audio::Scan->is_supported( $path );

	return $audio;
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
