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

package TTP::Media;
die __PACKAGE__ . " must be loaded as TTP::Media\n" unless __PACKAGE__ eq 'TTP::Media';

use strict;
use utf8;
use warnings;

use Audio::Scan;
use Capture::Tiny qw( capture );
use Data::Dumper;
use File::Spec;

use TTP;
use vars::global qw( $ep );

use TTP::Constants qw( :all );
use TTP::Finder;
use TTP::Message qw( :all );
use TTP::Path;

my $Const = {
	audio => {
		commonTags => {
			album => {},
			artist => {},
			cover => {},
			genre => {},
			year => {}
		},
		# some common suffixes for audio files
		formats => {
			AAC => {
				compress => true,
				lossy => true,
				label => 'Advanced Audio Coding',
				getAlbum => sub {
					my ( $scan ) = @_;
					my $value = $scan->{tags}{TALB};
					return $value;
				}
			},
			AIFF => {
				compress => false,
				lossy => false,
				label => 'Audio Interchange File Format'
			},
			alac => {
				compress => true,
				lossy => false,
				label => 'Apple Lossless Audio Codec'
			},
			ASF => {

			},
			FLAC => {
				compress => true,
				lossy => false,
				label => 'Free Lossless Audio Codec',
				getAlbum => sub {
					my ( $scan ) = @_;
					my $value = $scan->{tags}{TALB};
					return $value;
				}
			},
			M4A => {
			},
			MP3 => {
				compress => true,
				lossy => true,
				label => 'MPEG-1 Audio Layer 3'
			},
			MP4 => {
				compress => true,
				lossy => true,
				label => 'MPEG-4 Part 14',
				container => 'm4a',
				getAlbum => sub {
					my ( $scan ) = @_;
					my $value = $scan->{tags}{TALB};
					return $value;
				}
			},
			Ogg => {
				compress => true,
				lossy => true,
				label => 'Ogg Vorbis',
				getAlbum => sub {
					my ( $scan ) = @_;
					my $value = $scan->{tags}{TALB};
					return $value;
				}
			},
			opus => {
				compress => true,
				lossy => true,
				label => 'Opus',
				getAlbum => sub {
					my ( $scan ) = @_;
					my $value = $scan->{tags}{TALB};
					return $value;
				}
			},
			pcm => {
				compress => false,
				lossy => false,
				label => 'Pulse-Code Modulation'
			},
			WAV => {
				compress => false,
				lossy => false,
				label => 'Waveform Audio File Format'
			},
			wma => {
				compress => true,
				lossy => true,
				label => 'Windows Media Audio'
			}
		},
		suffixes => undef
	}
};

# ------------------------------------------------------------------------------------------------
# Extracts from the path the album level
# our standard audio trees are set as ROOT/type/letter/artist/albums[/disc]/file
# (I):
# - the full file pathname
# (O):
# - the album directory, which may be undef

sub albumFromPath {
	my ( $path ) = @_;
	my $album = undef;

	if( -d $path ){
		my @dirs = File::Spec->splitdir( $path );
		$album = $dirs[6];
	} else {
		my ( $volume,$directories,$file ) = File::Spec->splitpath( $path );
		my @dirs = File::Spec->splitdir( $directories );
		$album = $dirs[6];
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
	print Dumper( $scan->{tags} ) if !$value;
	#msgVerbose( "$scan->{path} album $value" ) if $value;

	return $value;
}

# ------------------------------------------------------------------------------------------------
# Extracts from the path the artist level
# our standard audio trees are set as ROOT/type/letter/artist/albums[/disc]/file
# (I):
# - the full file pathname
# (O):
# - the artist directory

sub artistFromPath {
	my ( $path ) = @_;
	my $artist = undef;

	if( -d $path ){
		my @dirs = File::Spec->splitdir( $path );
		$artist = $dirs[5];
	} else {
		my ( $volume,$directories,$file ) = File::Spec->splitpath( $path );
		my @dirs = File::Spec->splitdir( $directories );
		$artist = $dirs[5];
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
	print Dumper( $scan->{tags} ) if !$value;
	#msgVerbose( "$scan->{path} artist $value" ) if $value;

	return $value;
}

# ------------------------------------------------------------------------------------------------
# Returns a ref to the array of known audio containers
# (I):
# - none
# (O):
# - an array ref

#sub containers {
# 
#	if( !defined( $Const->{audio}{suffixes} )){
#		my $formats = formats();
#		foreach my $it ( @{$formats} ){
#			push( @{$Const->{audio}{suffixes}}, ".$it" );
#		}
#	}
#
#	return $Const->{audio}{suffixes};
#}

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
	print Dumper( $scan->{tags} ) if !$value;
	#msgVerbose( "$scan->{path} cover $value" ) if $value;

	return $value;
}

# ------------------------------------------------------------------------------------------------
# Returns a ref to the array of known audio formats
# (I):
# - none
# (O):
# - an array ref

#sub formats {
#	my $formats = [];
#
#	foreach my $format ( sort keys %{$Const->{audio}{formats}} ){
#		my $it = $Const->{audio}{formats}{$format};
#		if( $it->{container} ){
#			push( @{$formats}, $it->{container} );
#		} else {
#			push( @{$formats}, $format );
#		}
#	}
#
#	return $formats;
#}

# ------------------------------------------------------------------------------------------------
# Extracts the genre from a full scan
# (I):
# - the scan result
# (O):
# - the genre, or undef

sub genreFromScan {
	my ( $scan ) = @_;

	my $value = undef;
	$value = $value || $scan->{tags}{TCON};		# MP3
	$value = $value || $scan->{tags}{GEN};		# MP4
	$value = $value || $scan->{tags}{GENRE};	# FLAC
	print Dumper( $scan->{tags} ) if !$value;
	#msgVerbose( "$scan->{path} genre $value" ) if $value;

	return $value;
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

sub scan {
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
	}

	$result->{path} = $path;
	my $suffix = TTP::Path::suffix( $path );
	$result->{suffix} = uc( $suffix ) if $suffix;

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
	$value = $value || $scan->{tags}{TRCK};			# MP3  number/count
	$value = $value || $scan->{tags}{TRKN};			# M4A number/count
	if( $value ){
		$value =~ s/^[0-9]+\///;
	}
	$value = $value || $scan->{tags}{TRACKTOTAL};	# FLAC
	print Dumper( $scan->{tags} ) if !$value;
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
	print Dumper( $scan->{tags} ) if !$value;
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
	print Dumper( $scan->{tags} ) if !$value;
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
	$value = $value || $scan->{tags}{ORIGINALYEAR};
	$value = $value || $scan->{tags}{DATE};			# FLAC
	print Dumper( $scan->{tags} ) if !$value;
	#msgVerbose( "$scan->{path} year $value" ) if $value;

	return $value;
}

1;
