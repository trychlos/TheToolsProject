# @(#) list objects
#
# CAUTION - NOT STANDARD DISPLAY
#
# @(-) --[no]help                   print this message, and exit [${help}]
# @(-) --[no]colored                color the output depending of the message level [${colored}]
# @(-) --[no]dummy                  dummy run [${dummy}]
# @(-) --[no]verbose                run verbosely [${verbose}]
# @(-) --source-path=<source>       acts on this source [${sourcePath}]
# @(-) --[no]list-albums            list the albums [${listAlbums}]
# @(-) --[no]list-genres            list the recensed genres [${listGenres}]
# @(-) --format=<format>            print artists/albums with this format [${format}]
# @(-) --step=<count>               the progress indicator step when listing by genres, set to zero or a negative value to disable [${step}]
# @(-) album directory level options:
# @(-) --[no]check-path-album       check that the album directory corresponds to the album tag (of the first track) [${checkAlbumPath}]
# @(-) --[no]check-specials-album   check that the album title doesn't have special characters [${checkAlbumSpecials}]
# @(-) --[no]check-same-album       check that all the track of the album are tagged with the same album [${checkSameAlbum}]
# @(-) --[no]check-same-artist      check that all the track of the album are tagged with the same artist [${checkSameArtist}]
# @(-) --[no]check-same-count       check that all the track of the album are tagged with the same tracks count [${checkSameCount}]
# @(-) --[no]check-all-album        check all album-level available properties [${checkAllAlbum}]
# @(-) track file level options:
# @(-) --[no]check-artist           check that the track has a tagged artist [${checkArtist}]
# @(-) --[no]check-album            check that the track has a tagged album [${checkAlbum}]
# @(-) --[no]check-count            check that the track has a tagged tracks count [${checkCount}]
# @(-) --[no]check-cover            check that the track has a tagged cover [${checkCover}]
# @(-) --[no]check-genre            check that the track has a tagged genre [${checkGenre}]
# @(-) --[no]check-number           check that the track is numbered [${checkNumber}]
# @(-) --[no]check-specials-track   check that the track title doesn't have special characters [${checkTrackSpecials}]
# @(-) --[no]check-title            check that the track has a tagged title [${checkTitle}]
# @(-) --[no]check-year             check that the track has a tagged year [${checkYear}]
# @(-) --[no]check-path-track       check that the track filename corresponds to the title tag [${checkTrackPath}]
# @(-) --[no]check-all-track        check all track-level available properties [${checkAllTrack}]
# @(-) summary options:
# @(-) --[no]summary-list           display the list of erroneous albums/tracks [${summaryList}]
# @(-) --[no]summary-counters       display the counters [${summaryCounters}]
# @(-) --[no]summary-unchecked      display counters for unchecked options [${summaryUnchecked}]
#
# @(@) Note 1: 'format' is a sprintf() format string with following macros:
# @(@)         - %AP: artist from the path
# @(@)         - %BP: album from the path
# @(@)         - %AS: artist from the scan
# @(@)         - %BS: album from the scan
# @(@)         - %G: genre
# @(@)         - %Y: year
# @(@)         - %TC: track count
# @(@) Note 2: Checking that all tracks of an album are tagged with the same artist is prone to errors and not always really relevant,
# @(@)         e.g. when a track is played or singed by the main artist with another one or feat. someone.
# @(@) Note 3: Checking that all tracks of an album are tagged with the same tracks count is disabled when the album has several discs.

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

use File::Spec;

use TTP::Media;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	sourcePath => '',
	listAlbums => 'no',
	listGenres => 'no',
	checkAlbum => 'no',
	checkAlbumPath => 'no',
	checkAlbumSpecials => 'no',
	checkAllAlbum => 'no',
	checkArtist => 'no',
	checkCount => 'no',
	checkCover => 'no',
	checkGenre => 'no',
	checkNumber => 'no',
	checkSameAlbum => 'no',
	checkSameArtist => 'no',
	checkSameCount => 'no',
	checkTitle => 'no',
	checkTrackPath => 'no',
	checkTrackSpecials => 'no',
	checkYear => 'no',
	checkAllTrack => 'no',
	format => '%AP / %BP',
	step => 100,
	summaryList => 'yes',
	summaryCounters => 'yes',
	summaryUnchecked => 'no'
};

my $opt_sourcePath = $defaults->{sourcePath};
my $opt_listAlbums = false;
my $opt_listGenres = false;
my $opt_checkAlbum = false;
my $opt_checkAlbumPath = false;
my $opt_checkAlbumSpecials = false;
my $opt_checkAllAlbum = false;
my $opt_checkArtist = false;
my $opt_checkCount = false;
my $opt_checkCover = false;
my $opt_checkGenre = false;
my $opt_checkNumber = false;
my $opt_checkSameAlbum = false;
my $opt_checkSameArtist = false;
my $opt_checkSameCount = false;
my $opt_checkTitle = false;
my $opt_checkTrackPath = false;
my $opt_checkTrackSpecials = false;
my $opt_checkYear = false;
my $opt_checkAllTrack = false;
my $opt_format = $defaults->{format};
my $opt_step = $defaults->{step};
my $opt_step_set = false;
my $opt_summaryList = true;
my $opt_summaryCounters = true;
my $opt_summaryUnchecked = false;

# register here the counters at the album level
my $check_albums = [
	'album_dir',
	'album_specials',
	'same_album',
	'same_artist',
	'same_count'
];

# -------------------------------------------------------------------------------------------------
# given an audio file path, check that it contains an album tag
# https://id3.org/id3v2.3.0#Default_flags
#   TALB    [#TALB Album/Movie/Show title]
#   TOAL    [#TOAL Original album/movie/show title]
# for each album, count ok/notok
# + warn if the title contains slashes or backslashes which are special characters in linux/windows

sub checkAlbum {
	my ( $hash, $scan ) = @_;

	my $value = TTP::Media::albumFromScan( $scan );
	# do we have something set ?
	my $ok = $value && length( $value ) > 0;

	# maybe increment counters per album
	$hash->{album} //= {};
	$hash->{album}{count} //= 0;
	$hash->{album}{count} += 1;
	if( $ok ){
		$hash->{album}{ok} //= 0;
		$hash->{album}{ok} += 1;
	} else {
		$hash->{album}{notok} //= 0;
		$hash->{album}{notok} += 1;
		$hash->{album}{files} //= [];
		push( @{$hash->{album}{files}}, $scan->{path} );
		msgWarn( "album not ok for '$scan->{path}'" );
	}

	return $ok;
}

# -------------------------------------------------------------------------------------------------
# the directory name of the album should be formatted like "<album> [<year>]"
# it is checked only once

sub checkAlbumPath {
	my ( $hash, $scan ) = @_;

	# actual directory name, may be undef if we have only the 'artist' level
	my $albumFromPath = $scan->{albumFromPath};

	$hash->{album_dir} //= {};
	$hash->{album_dir}{count} //= 0;
	$hash->{album_dir}{count} += 1;
	my $ok = true;

	if( $albumFromPath ){

		# theorical directory name
		my $album = TTP::Media::albumFromScan( $scan ) || '';
		my $year = TTP::Media::yearFromScan( $scan ) || '';
		my $theorical = "$album [$year]";

		# are we equal ?
		$ok = $albumFromPath eq $theorical;

		# maybe increment counters per album
		if( $ok ){
			$hash->{album_dir}{ok} //= 0;
			$hash->{album_dir}{ok} += 1;
			msgVerbose( "album path '$albumFromPath' ok" );
		} else {
			$hash->{album_dir}{notok} //= 0;
			$hash->{album_dir}{notok} += 1;
			$hash->{album_dir}{theorical} = $theorical;
			msgWarn( "album path not ok for '$albumFromPath' (theorical='$theorical')" );
		}
	} else {
		$hash->{album_dir}{noalbum} //= 0;
		$hash->{album_dir}{notoknoalbum} += 1;
		msgVerbose( "no album from path for '$scan->{path}'" );
	}


	return $ok;
}

# -------------------------------------------------------------------------------------------------
# the album name (tagged in the track) should not have special characters if we want be part of the directory name
# this is checked at the album level on the first track

sub checkAlbumSpecials {
	my ( $hash, $scan ) = @_;

	my $value = TTP::Media::albumFromScan( $scan );
	my $ok = true;

	# maybe increment counters per album
	$hash->{album_specials} //= {};
	$hash->{album_specials}{count} //= 0;
	$hash->{album_specials}{count} += 1;

	if( $value ){
		$value =~ s/[^\/\\<>]//g;
		if( $value ){
			msgWarn( "album title contains special characters '$scan->{path}'" );
			$hash->{album_specials}{notok} //= 0;
			$hash->{album_specials}{notok} += 1;
			$hash->{album_specials}{files} //= [];
			push( @{$hash->{album_specials}{files}}, $scan->{path} );
			$ok = false;
		} else {
			$hash->{album_specials}{ok} //= 0;
			$hash->{album_specials}{ok} += 1;
		}
	}

	return $ok;
}

# -------------------------------------------------------------------------------------------------
# given an audio file path, check that it contains an artist tag
# https://id3.org/id3v2.3.0#Default_flags
#   TPE1    [#TPE1 Lead performer(s)/Soloist(s)]
#   TPE2    [#TPE2 Band/orchestra/accompaniment]
#   TPE3    [#TPE3 Conductor/performer refinement]
#   TPE4    [#TPE4 Interpreted, remixed, or otherwise modified by]
# for each album, count ok/notok

sub checkArtist {
	my ( $hash, $scan ) = @_;

	my $value = TTP::Media::artistFromScan( $scan );
	# do we have something set ?
	my $ok = $value && length( $value ) > 0;

	# maybe increment counters per album
	$hash->{artist} //= {};
	$hash->{artist}{count} //= 0;
	$hash->{artist}{count} += 1;
	if( $ok ){
		$hash->{artist}{ok} //= 0;
		$hash->{artist}{ok} += 1;
	} else {
		$hash->{artist}{notok} //= 0;
		$hash->{artist}{notok} += 1;
		$hash->{artist}{files} //= [];
		push( @{$hash->{artist}{files}}, $scan->{path} );
		msgWarn( "artist not ok for '$scan->{path}'" );
	}

	return $ok;
}

# -------------------------------------------------------------------------------------------------
# given an audio file path, check that it contains a track count tag
# https://id3.org/id3v2.3.0#Default_flags
#   TCON    [#TCON Content type]
# for each album, count ok/notok

sub checkCount {
	my ( $hash, $scan ) = @_;

	my $value = TTP::Media::trackCountFromScan( $scan );
	# do we have something set ?
	my $ok = $value && length( $value ) > 0;

	# maybe increment counters per album
	$hash->{count} //= {};
	$hash->{count}{count} //= 0;
	$hash->{count}{count} += 1;
	if( $ok ){
		$hash->{count}{ok} //= 0;
		$hash->{count}{ok} += 1;
	} else {
		$hash->{count}{notok} //= 0;
		$hash->{count}{notok} += 1;
		$hash->{count}{files} //= [];
		push( @{$hash->{count}{files}}, $scan->{path} );
		msgWarn( "tracks count not ok for '$scan->{path}'" );
	}

	return $ok;
}

# -------------------------------------------------------------------------------------------------
# given an audio file path, check that it contains a cover tag
# https://id3.org/id3v2.3.0#Default_flags
#   TCON    [#TCON Content type]
# for each album, count ok/notok

sub checkCover {
	my ( $hash, $scan ) = @_;

	my $value = TTP::Media::coverFromScan( $scan );
	# do we have something set ?
	my $ok = $value && length( $value ) > 0;

	# maybe increment counters per album
	$hash->{cover} //= {};
	$hash->{cover}{count} //= 0;
	$hash->{cover}{count} += 1;
	if( $ok ){
		$hash->{cover}{ok} //= 0;
		$hash->{cover}{ok} += 1;
	} else {
		$hash->{cover}{notok} //= 0;
		$hash->{cover}{notok} += 1;
		$hash->{cover}{files} //= [];
		push( @{$hash->{cover}{files}}, $scan->{path} );
		msgWarn( "cover not ok for '$scan->{path}'" );
	}

	return $ok;
}

# -------------------------------------------------------------------------------------------------
# given an audio file path, check that it contains a genre tag
# https://id3.org/id3v2.3.0#Default_flags
#   TCON    [#TCON Content type]
# for each album, count ok/notok

sub checkGenre {
	my ( $hash, $scan ) = @_;

	my $value = TTP::Media::genreFromScan( $scan );
	# do we have something set ?
	my $ok = $value && length( $value ) > 0;

	# maybe increment counters per album
	$hash->{genre} //= {};
	$hash->{genre}{count} //= 0;
	$hash->{genre}{count} += 1;
	if( $ok ){
		$hash->{genre}{ok} //= 0;
		$hash->{genre}{ok} += 1;
	} else {
		$hash->{genre}{notok} //= 0;
		$hash->{genre}{notok} += 1;
		$hash->{genre}{files} //= [];
		push( @{$hash->{genre}{files}}, $scan->{path} );
		msgWarn( "genre not ok for '$scan->{path}'" );
	}

	return $ok;
}

# -------------------------------------------------------------------------------------------------
# given an audio file path, check that it contains a track number tag (should be 'nn' though MusicBrainz just set 'n')
# for each album, count ok/notok

sub checkNumber {
	my ( $hash, $scan ) = @_;

	my $value = TTP::Media::trackNumberFromScan( $scan );
	# do we have something set ?
	my $ok = $value && length( $value ) > 0;

	# maybe increment counters per album
	$hash->{number} //= {};
	$hash->{number}{count} //= 0;
	$hash->{number}{count} += 1;
	if( $ok ){
		$hash->{number}{ok} //= 0;
		$hash->{number}{ok} += 1;
	} else {
		$hash->{number}{notok} //= 0;
		$hash->{number}{notok} += 1;
		$hash->{number}{files} //= [];
		push( @{$hash->{number}{files}}, $scan->{path} );
		msgWarn( "track number not ok for '$scan->{path}'" );
	}

	return $ok;
}

# -------------------------------------------------------------------------------------------------
# check that all tracks of an album (identified by its folder) have the same tagged album
# for each album, count ok/notok

sub checkSameAlbum {
	my ( $hash, $scan ) = @_;

	my $value = TTP::Media::albumFromScan( $scan );
	my $ok = true;

	# increment counters per album
	$hash->{same_album} //= {};
	$hash->{same_album}{count} //= 0;
	$hash->{same_album}{count} += 1;

	# during the scan we just set the files per tagged album
	# we will count the different keys at the end
	my $key = $value || 'empty';
	$hash->{same_album}{list} //= {};
	$hash->{same_album}{list}{$key} //= [];
	push( @{$hash->{same_album}{list}{$key}}, $scan->{path} );

	return $ok;
}

# -------------------------------------------------------------------------------------------------
# check that all tracks of an album (identified by its folder) have the same tagged artist
# for each album, count ok/notok

sub checkSameArtist {
	my ( $hash, $scan ) = @_;

	my $value = TTP::Media::artistFromScan( $scan );
	my $ok = true;

	# increment counters per album
	$hash->{same_artist} //= {};
	$hash->{same_artist}{count} //= 0;
	$hash->{same_artist}{count} += 1;

	# during the scan we just set the files per tagged album
	# we will count the different keys at the end
	my $key = $value || 'empty';
	$hash->{same_artist}{list} //= {};
	$hash->{same_artist}{list}{$key} //= [];
	push( @{$hash->{same_artist}{list}{$key}}, $scan->{path} );

	return $ok;
}

# -------------------------------------------------------------------------------------------------
# check that all tracks of an album (identified by its folder) have the same tagged tracks count
# for each album, count ok/notok

sub checkSameCount {
	my ( $hash, $scan ) = @_;

	my $value = TTP::Media::trackCountFromScan( $scan );
	my $ok = true;

	# increment counters per album
	$hash->{same_count} //= {};
	$hash->{same_count}{count} //= 0;
	$hash->{same_count}{count} += 1;

	# during the scan we just set the files per tagged album
	# we will count the different keys at the end
	my $key = $value || 'empty';
	$hash->{same_count}{list} //= {};
	$hash->{same_count}{list}{$key} //= [];
	push( @{$hash->{same_count}{list}{$key}}, $scan->{path} );

	return $ok;
}

# -------------------------------------------------------------------------------------------------
# given an audio file path, check that it contains a track title tag
# for each album, count ok/notok
# + warn if the title contains slashes or backslashes which are special characters in linux/windows

sub checkTitle {
	my ( $hash, $scan ) = @_;

	my $value = TTP::Media::trackTitleFromScan( $scan );
	# do we have something set ?
	my $ok = $value && length( $value ) > 0;

	# maybe increment counters per album
	$hash->{title} //= {};
	$hash->{title}{count} //= 0;
	$hash->{title}{count} += 1;
	if( $ok ){
		$hash->{title}{ok} //= 0;
		$hash->{title}{ok} += 1;
	} else {
		$hash->{title}{notok} //= 0;
		$hash->{title}{notok} += 1;
		$hash->{title}{files} //= [];
		push( @{$hash->{title}{files}}, $scan->{path} );
		msgWarn( "track title not ok for '$scan->{path}'" );
	}

	return $ok;
}

# -------------------------------------------------------------------------------------------------
# the track file name should be formatted like "<nn> - <title>".extension
# it is checked only once

sub checkTrackPath {
	my ( $hash, $scan ) = @_;

	# actual file name without the extension
	my ( $vol, $directories, $filename ) = File::Spec->splitpath( $scan->{path} );
	$filename =~ s/\.[^\.]+$//;

	# theorical track name
	my $number = TTP::Media::trackNumberFromScan( $scan ) || '';
	my $str = sprintf( "%02u", ( 0+$number ));
	my $title = TTP::Media::trackTitleFromScan( $scan ) || '';
	my $theorical = "$str - $title";

	# are we equal ?
	my $ok = $filename eq $theorical;

	# maybe increment counters per album
	$hash->{trackpath} //= {};
	$hash->{trackpath}{count} //= 0;
	$hash->{trackpath}{count} += 1;
	if( $ok ){
		$hash->{trackpath}{ok} //= 0;
		$hash->{trackpath}{ok} += 1;
	} else {
		$hash->{trackpath}{notok} //= 0;
		$hash->{trackpath}{notok} += 1;
		$hash->{trackpath}{files} //= [];
		push( @{$hash->{trackpath}{files}}, $scan->{path} );
		msgWarn( "track pathname not ok for '$scan->{path}' (theorical='$theorical')" );
	}

	return $ok;
}

# -------------------------------------------------------------------------------------------------
# the track title (tagged in the track) should not have special characters if we want be part of the track filename

sub checkTrackSpecials {
	my ( $hash, $scan ) = @_;

	my $value = TTP::Media::trackTitleFromScan( $scan );
	my $ok = true;

	# maybe increment counters per album
	$hash->{track_specials} //= {};
	$hash->{track_specials}{count} //= 0;
	$hash->{track_specials}{count} += 1;

	if( $value ){
		$value =~ s/[^\/\\<>]//g;
		if( $value ){
			msgWarn( "track title contains special characters '$scan->{path}'" );
			$hash->{track_specials}{notok} //= 0;
			$hash->{track_specials}{notok} += 1;
			$hash->{track_specials}{files} //= [];
			push( @{$hash->{track_specials}{files}}, $scan->{path} );
			$ok = false;
		} else {
			$hash->{track_specials}{ok} //= 0;
			$hash->{track_specials}{ok} += 1;
		}
	}

	return $ok;
}

# -------------------------------------------------------------------------------------------------
# given an audio file path, check that it contains a year tag
# https://id3.org/id3v2.3.0#Default_flags
#   TORY    [#TORY Original release year]
#   TYER    [#TYER Year]
# for each album, count ok/notok

sub checkYear {
	my ( $hash, $scan ) = @_;

	my $value = TTP::Media::yearFromScan( $scan );
	# do we have something set ?
	my $ok = $value && length( $value ) > 0;

	# maybe increment counters per album
	$hash->{year} //= {};
	$hash->{year}{count} //= 0;
	$hash->{year}{count} += 1;
	if( $ok ){
		$hash->{year}{ok} //= 0;
		$hash->{year}{ok} += 1;
	} else {
		$hash->{year}{notok} //= 0;
		$hash->{year}{notok} += 1;
		$hash->{year}{files} //= [];
		push( @{$hash->{year}{files}}, $scan->{path} );
		msgWarn( "year not ok for '$scan->{path}'" );
	}

	return $ok;
}

# -------------------------------------------------------------------------------------------------
# list the albums in the specified tree
# audio tree are set as ROOT/type/letter/artist/albums[/disc]/file

sub listAlbums {
	my $counters = {
		albums => {
			total => 0,
			path => ( $opt_checkAlbumPath || $opt_checkAllAlbum ) ? 0 : -1,
			same_album => ( $opt_checkSameAlbum || $opt_checkAllAlbum ) ? 0 : -1,
			same_artist => ( $opt_checkSameArtist || $opt_checkAllAlbum ) ? 0 : -1,
			same_count => ( $opt_checkSameCount || $opt_checkAllAlbum ) ? 0 : -1,
			same_count_disabled => ( $opt_checkSameCount || $opt_checkAllAlbum ) ? 0 : -1,
			specials => ( $opt_checkAlbumSpecials || $opt_checkAllAlbum ) ? 0 : -1
		},
		audios => {
			total => 0,
			album => ( $opt_checkAlbum || $opt_checkAllTrack ) ? 0 : -1,
			artist => ( $opt_checkArtist || $opt_checkAllTrack ) ? 0 : -1,
			count => ( $opt_checkCount || $opt_checkAllTrack ) ? 0 : -1,
			cover => ( $opt_checkCover || $opt_checkAllTrack ) ? 0 : -1,
			filename => ( $opt_checkTrackPath || $opt_checkAllTrack ) ? 0 : -1,
			genre => ( $opt_checkGenre || $opt_checkAllTrack ) ? 0 : -1,
			number => ( $opt_checkNumber || $opt_checkAllTrack ) ? 0 : -1,
			specials => ( $opt_checkTrackSpecials || $opt_checkAllTrack ) ? 0 : -1,
			title => ( $opt_checkTitle || $opt_checkAllTrack ) ? 0 : -1,
			valid => 0,
			year => ( $opt_checkYear || $opt_checkAllTrack ) ? 0 : -1
		}
	};
	my $albums = {};
	msgOut( "displaying music albums in '$opt_sourcePath'..." );
	my $result = TTP::Media::scan_tree( $opt_sourcePath, {
		sub => sub {
			# expect to have only supported files
			my ( $fname, $scan ) = @_;
			my $albumFromPath = TTP::Media::albumFromPath( $fname );
			my $artistFromPath = TTP::Media::artistFromPath( $fname );
			$counters->{audios}{total} += 1;
			# unless the very rare case where we do not know how to compute the key
			if( $albumFromPath || $artistFromPath ){
				$scan->{albumFromPath} = $albumFromPath;
				$scan->{artistFromPath} = $artistFromPath;
				my $key = "$artistFromPath $albumFromPath";
				$key =~ s/\s/-/g;
				if( !$albums->{$key} ){
					printAlbum( $scan );
					$counters->{albums}{total} += 1;
					$albums->{$key} //= {};
					$albums->{$key}{albumFromPath} = $albumFromPath;
					$albums->{$key}{artistFromPath} = $artistFromPath;
					$albums->{$key}{valid} //= {};
					$albums->{$key}{valid}{count} //= 0;
					$albums->{$key}{valid}{notok} //= 0;
					# check at the album level what can be done on the first track
					$counters->{albums}{path} += ( checkAlbumPath( $albums->{$key}, $scan ) ? 1 : 0 ) if $opt_checkAlbumPath || $opt_checkAllAlbum;
					$counters->{albums}{specials} += ( checkAlbumSpecials( $albums->{$key}, $scan ) ? 1 : 0 ) if $opt_checkAlbumSpecials || $opt_checkAllAlbum;
				}
				$albums->{$key}{valid}{count} += 1;
				# and check only if a valid audio file
				if( $scan->{ok} ){
					$counters->{audios}{valid} += 1;
					$albums->{$key}{valid}{ok} //= 0;
					$albums->{$key}{valid}{ok} += 1;
					# check for the whole album
					checkSameAlbum( $albums->{$key}, $scan ) if $opt_checkSameAlbum || $opt_checkAllAlbum;
					checkSameArtist( $albums->{$key}, $scan ) if $opt_checkSameArtist || $opt_checkAllAlbum;
					checkSameCount( $albums->{$key}, $scan ) if $opt_checkSameCount || $opt_checkAllAlbum;
					# check at the track level
					$counters->{audios}{album} += ( checkAlbum( $albums->{$key}, $scan ) ? 1 : 0 ) if $opt_checkAlbum || $opt_checkAllTrack;
					$counters->{audios}{artist} += ( checkArtist( $albums->{$key}, $scan ) ? 1 : 0 ) if $opt_checkArtist || $opt_checkAllTrack;
					$counters->{audios}{count} += ( checkCount( $albums->{$key}, $scan ) ? 1 : 0 ) if $opt_checkCount || $opt_checkAllTrack;
					$counters->{audios}{cover} += ( checkCover( $albums->{$key}, $scan ) ? 1 : 0 ) if $opt_checkCover || $opt_checkAllTrack;
					$counters->{audios}{genre} += ( checkGenre( $albums->{$key}, $scan ) ? 1 : 0 ) if $opt_checkGenre || $opt_checkAllTrack;
					$counters->{audios}{number} += ( checkNumber( $albums->{$key}, $scan ) ? 1 : 0 ) if $opt_checkNumber || $opt_checkAllTrack;
					$counters->{audios}{title} += ( checkTitle( $albums->{$key}, $scan ) ? 1 : 0 ) if $opt_checkTitle || $opt_checkAllTrack;
					$counters->{audios}{filename} += ( checkTrackPath( $albums->{$key}, $scan ) ? 1 : 0 ) if $opt_checkTrackPath || $opt_checkAllTrack;
					$counters->{audios}{specials} += ( checkTrackSpecials( $albums->{$key}, $scan ) ? 1 : 0 ) if $opt_checkTrackSpecials || $opt_checkAllTrack;
					$counters->{audios}{year} += ( checkYear( $albums->{$key}, $scan ) ? 1 : 0 ) if $opt_checkYear || $opt_checkAllTrack;
				} else {
					msgErr( $fname );
					msgErr( $scan->{errors}, { incErr => false });
					$albums->{$key}{valid}{notok} += 1;
					$albums->{$key}{valid}{files} //= [];
					push( @{$albums->{$key}{scan}{files}}, $fname );
				}
			} else {
				msgErr( "neither artist nor album can be computed from '$fname'" );
			}
		}
	});

	# have a summary
	summaryUpdateCounters( $counters, $albums );
	summaryAlbumsList( $counters, $albums ) if $opt_summaryList;
	summaryAlbumsCounters( $counters, $albums ) if $opt_summaryCounters;
	msgOut( "done" );
}

# -------------------------------------------------------------------------------------------------
# list the genres found in the specified tree
# audio tree are set as ROOT/type/letter/artist/albums[/disc]/file
# have an follow-up dot mark every 100 items

sub listGenres {
	my $counters = {
		total => 0,
		valid => 0,
		genre => {
			undef => 0
		}
	};
	my $genres = {};
	my $prev_cents = 0;
	msgOut( "scanning .", { withEol => false });
	my $result = TTP::Media::scan_tree( $opt_sourcePath, {
		sub => sub {
			# expect to have only supported files
			my ( $fname, $scan ) = @_;
			$counters->{total} += 1;
			if( $opt_step > 0 ){
				my $cent = int( $counters->{total} / $opt_step );
				if( $cent > $prev_cents ){
					print STDOUT ".";
					$prev_cents = $cent;
				}
			}
			if( $scan->{ok} ){
				$counters->{valid} += 1;
				my $albumFromPath = TTP::Media::albumFromPath( $fname );
				my $artistFromPath = TTP::Media::artistFromPath( $fname );

				my $genre = TTP::Media::genreFromScan( $scan, { dumpIfEmpty => false });
				if( $genre ){
					$genres->{$genre} //= {};
					$genres->{$genre}{$artistFromPath} //= {};
					$genres->{$genre}{$artistFromPath}{$albumFromPath} //= [];
					push( @{$genres->{$genre}{$artistFromPath}{$albumFromPath}}, $fname );
				} else {
					$counters->{genre}{undef} += 1;
				}
			} else {
				msgErr( "scan failed on $fname" );
			}
		}
	});
	print STDOUT EOL;
	# display the genres
	foreach my $genre ( sort keys %{$genres} ){
		print STDOUT $genre.EOL;
		foreach my $artist ( sort keys %{$genres->{$genre}} ){
			foreach my $album ( sort keys %{$genres->{$genre}{$artist}} ){
				print "  $artist / $album".EOL;
			}
		}
	}
	# display a summary
	msgOut( "Summary list:" );
	msgOut( "  $counters->{total} found track(s), among them:" );
	msgOut( "  - ".( $counters->{total} - $counters->{valid} )." were not valid" );
	msgOut( "  - $counters->{genre}{undef} didn't have a genre" );
	msgOut( "done" );
}

# -------------------------------------------------------------------------------------------------
# print the album depending of the required format
# (I):
# - the result of the scan
# - an optional options hash with following keys:
#   > prefix: a prefix to be prepended to each output line, defaulting to ' '

sub printAlbum {
	my ( $scan, $opts ) = @_;
	$opts //= {};
	my $str = $opt_format;
	$str =~ s/%AP/$scan->{artistFromPath}/g;
	$str =~ s/%BP/$scan->{albumFromPath}/g;
	my $value = TTP::Media::albumFromScan( $scan );
	$str =~ s/%BS/$value/g;
	$value = TTP::Media::artistFromScan( $scan );
	$str =~ s/%AS/$value/g;
	$value = TTP::Media::genreFromScan( $scan );
	$str =~ s/%G/$value/g;
	$value = TTP::Media::trackCountFromScan( $scan );
	$str =~ s/%TC/$value/g;
	$value = TTP::Media::yearFromScan( $scan );
	$str =~ s/%Y/$value/g;
	my $prefix = " ";
	$prefix = $opts->{prefix} if defined $opts->{prefix};
	print STDOUT "$prefix$str".EOL;
}

# -------------------------------------------------------------------------------------------------
# display the list of counters as a summary
# (I):
# - the counters
# - the albums

sub summaryAlbumsCounters {
	my ( $counters, $albums ) = @_;

	msgOut( "Summary counters:" );
	my @types = sort keys( %{$counters} );
	foreach my $type ( @types ){
		msgOut( "  $type:" );
		foreach my $key ( sort keys %{$counters->{$type}} ){
			if( $key eq 'same_count_disabled' ){
				next;
			} elsif( $counters->{$type}{$key} == -1 && !$opt_summaryUnchecked ){
				next;
			} else {
				my $str = "    $key: ";
				if( $key eq 'total' || $key eq 'valid' ){
					$str .= $counters->{$type}{$key};
				} elsif( $counters->{$type}{$key} == -1 ){
					$str .= "not checked";
				} else {
					$str .= "$counters->{$type}{$key} ok";
					if( $counters->{$type}{$key} != $counters->{$type}{total} ){
						if( $key eq 'same_count' ){
							$str .= " ($counters->{$type}{same_count_disabled} disabled";
							if( $counters->{$type}{$key} + $counters->{$type}{same_count_disabled} != $counters->{$type}{total} ){
								$str .= $counters->{$type}{total} - $counters->{$type}{$key} - $counters->{$type}{same_count_disabled}." not ok";
							}
							$str .= ")";
						} else {
							$str .= " (".( $counters->{$type}{total} - $counters->{$type}{$key} )." not ok";
							if( $key eq 'same_artist' ){
								$str .= ", see help notes as this may be not relevant"
							}
							$str .= ")";
						}
					}
				}
				msgOut( $str );
			}
		}
	}
}

# -------------------------------------------------------------------------------------------------
# display the list of erroneous albums as a summary
# (I):
# - the counters
# - the albums

sub summaryAlbumsList {
	my ( $counters, $albums ) = @_;

	# display the albums which have at least one error
	my $countOk = 0;
	my $errAlbums = [];
	foreach my $key ( sort keys %{$albums} ){
		my $haveError = false;
		$albums->{$key}{errfiles} //= {};
		foreach my $counter ( sort keys %{$albums->{$key}} ){
			if( ref( $albums->{$key}{$counter} ) eq 'HASH' ){
				if( $albums->{$key}{$counter}{notok} ){
					$haveError = true;
					if( grep( /^$counter$/, @{$check_albums} )){
						$albums->{$key}{erralbums} //= [];
						push( @{$albums->{$key}{erralbums}}, $counter );
					} else {
						foreach my $f ( @{$albums->{$key}{$counter}{files}} ){
							$albums->{$key}{errfiles}{$f} //= [];
							push( @{$albums->{$key}{errfiles}{$f}}, $counter );
						}
					}
				}
			}
		}
		if( $haveError ){
			push( @{$errAlbums}, $key );
		} else {
			$countOk += 1;
		}
	}
	msgOut( "Summary list:" );
	msgOut( "  $counters->{albums}{total} found album(s), among them $countOk were ok" );
	if( scalar( @{$errAlbums} )){
		msgOut(( "  ".scalar( @{$errAlbums} ))." album(s) were NOT ok:" );
		foreach my $key ( @{$errAlbums} ){
			my $album = $albums->{$key};
			#print Dumper( $album );
			msgOut( "    $album->{artistFromPath} / $album->{albumFromPath}" );
			if( $albums->{$key}{erralbums} && scalar( @{$albums->{$key}{erralbums}} )){
				msgOut( "      ".join( ',', @{$album->{erralbums}}));
			}
			foreach my $f ( sort keys %{$album->{errfiles}} ){
				msgOut( "      $f: ".join( ',', @{$album->{errfiles}{$f}}));
			}
		}
	}
}

# -------------------------------------------------------------------------------------------------
# update the counters before displaying the summaries
# update the counters for the checks which are on all the tracks on an album
# (I):
# - the counters
# - the albums

sub summaryUpdateCounters {
	my ( $counters, $albums ) = @_;

	# same counters (if any)
	foreach my $key ( sort keys %{$albums} ){
		foreach my $same ( 'same_album', 'same_artist', 'same_count' ){
			if( $albums->{$key}{$same} && $albums->{$key}{$same}{count} ){
				my @distincts = keys %{$albums->{$key}{$same}{list}};
				if( scalar( @distincts ) == 1 ){
					$counters->{albums}{$same} += 1;
				} elsif( $same eq 'same_count' && TTP::Media::hasDiscLevel( $albums->{$key}{$same}{list}{$distincts[0]}->[0] )){
					$counters->{albums}{same_count_disabled} += 1;
				} else {
					# count but do not warn when we find several artists (which is rather frequent)
					msgWarn( "$albums->{$key}{artistFromPath} / $albums->{$key}{albumFromPath} not $same" ) if $same ne 'same_artist';
				}
			}
		}
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"					=> sub { $ep->runner()->help( @_ ); },
	"colored!"				=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"				=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"				=> sub { $ep->runner()->verbose( @_ ); },
	"source-path=s"			=> \$opt_sourcePath,
	"list-albums!"			=> \$opt_listAlbums,
	"list-genres!"			=> \$opt_listGenres,
	"check-album!"			=> \$opt_checkAlbum,
	"check-album-path!"		=> \$opt_checkAlbumPath,
	"check-album-specials!"	=> \$opt_checkAlbumSpecials,
	"check-all-album!"		=> \$opt_checkAllAlbum,
	"check-artist!"			=> \$opt_checkArtist,
	"check-count!"			=> \$opt_checkCount,
	"check-cover!"			=> \$opt_checkCover,
	"check-genre!"			=> \$opt_checkGenre,
	"check-number!"			=> \$opt_checkNumber,
	"check-same-album!"		=> \$opt_checkSameAlbum,
	"check-same-artist!"	=> \$opt_checkSameArtist,
	"check-same-count!"		=> \$opt_checkSameCount,
	"check-title!"			=> \$opt_checkTitle,
	"check-track-path!"		=> \$opt_checkTrackPath,
	"check-track-specials!"	=> \$opt_checkTrackSpecials,
	"check-year!"			=> \$opt_checkYear,
	"check-all-track!"		=> \$opt_checkAllTrack,
	"format=s"				=> \$opt_format,
	"step=s"				=> sub {
		my ( $name, $value ) = @_;
		$opt_step = $value;
		$opt_step_set = true;
	},
	"summary-list!"			=> \$opt_summaryList,
	"summary-counters!"		=> \$opt_summaryCounters,
	"summary-unchecked!"	=> \$opt_summaryUnchecked )){

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
msgVerbose( "got source-path='$opt_sourcePath'" );
msgVerbose( "got list-albums='".( $opt_listAlbums ? 'true':'false' )."'" );
msgVerbose( "got list-genres='".( $opt_listGenres ? 'true':'false' )."'" );
msgVerbose( "got check-album='".( $opt_checkAlbum ? 'true':'false' )."'" );
msgVerbose( "got check-album-path='".( $opt_checkAlbumPath ? 'true':'false' )."'" );
msgVerbose( "got check-album-specials='".( $opt_checkAlbumSpecials ? 'true':'false' )."'" );
msgVerbose( "got check-all-album='".( $opt_checkAllAlbum ? 'true':'false' )."'" );
msgVerbose( "got check-artist='".( $opt_checkArtist ? 'true':'false' )."'" );
msgVerbose( "got check-count='".( $opt_checkCount ? 'true':'false' )."'" );
msgVerbose( "got check-cover='".( $opt_checkCover ? 'true':'false' )."'" );
msgVerbose( "got check-genre='".( $opt_checkGenre ? 'true':'false' )."'" );
msgVerbose( "got check-number='".( $opt_checkNumber ? 'true':'false' )."'" );
msgVerbose( "got check-same-album='".( $opt_checkSameAlbum ? 'true':'false' )."'" );
msgVerbose( "got check-same-artist='".( $opt_checkSameArtist ? 'true':'false' )."'" );
msgVerbose( "got check-same-count='".( $opt_checkSameCount ? 'true':'false' )."'" );
msgVerbose( "got check-title='".( $opt_checkTitle ? 'true':'false' )."'" );
msgVerbose( "got check-track-path='".( $opt_checkTrackPath ? 'true':'false' )."'" );
msgVerbose( "got check-track-specials='".( $opt_checkTrackSpecials ? 'true':'false' )."'" );
msgVerbose( "got check-year='".( $opt_checkYear ? 'true':'false' )."'" );
msgVerbose( "got check-all-track='".( $opt_checkAllTrack ? 'true':'false' )."'" );
msgVerbose( "got format='$opt_format'" );
msgVerbose( "got step='$opt_step'" );
msgVerbose( "got summary-list='".( $opt_summaryList ? 'true':'false' )."'" );
msgVerbose( "got summary-counters='".( $opt_summaryCounters ? 'true':'false' )."'" );
msgVerbose( "got summary-unchecked='".( $opt_summaryUnchecked ? 'true':'false' )."'" );

# must have --source-path option
msgErr( "'--source-path' option is mandatory, but is not specified" ) if !$opt_sourcePath;

# some options are only relevant for some actions
if( !$opt_listAlbums ){
	msgWarn( "'--check-album' option is only relevant when listing albums, ignored" ) if $opt_checkAlbum;
	msgWarn( "'--check-album-path' option is only relevant when listing albums, ignored" ) if $opt_checkAlbumPath;
	msgWarn( "'--check-album-specials' option is only relevant when listing albums, ignored" ) if $opt_checkAlbumSpecials;
	msgWarn( "'--check-all-album' option is only relevant when listing albums, ignored" ) if $opt_checkAllAlbum;
	msgWarn( "'--check-all-album' option is only relevant when listing albums, ignored" ) if $opt_checkAllAlbum;
	msgWarn( "'--check-artist' option is only relevant when listing albums, ignored" ) if $opt_checkArtist;
	msgWarn( "'--check-count' option is only relevant when listing albums, ignored" ) if $opt_checkCount;
	msgWarn( "'--check-cover' option is only relevant when listing albums, ignored" ) if $opt_checkCover;
	msgWarn( "'--check-number' option is only relevant when listing albums, ignored" ) if $opt_checkNumber;
	msgWarn( "'--check-same-album' option is only relevant when listing albums, ignored" ) if $opt_checkSameAlbum;
	msgWarn( "'--check-same-artist' option is only relevant when listing albums, ignored" ) if $opt_checkSameArtist;
	msgWarn( "'--check-same-count' option is only relevant when listing albums, ignored" ) if $opt_checkSameCount;
	msgWarn( "'--check-title' option is only relevant when listing albums, ignored" ) if $opt_checkTitle;
	msgWarn( "'--check-track-path' option is only relevant when listing albums, ignored" ) if $opt_checkTrackPath;
	msgWarn( "'--check-track-specials' option is only relevant when listing albums, ignored" ) if $opt_checkTrackSpecials;
	msgWarn( "'--check-year' option is only relevant when listing albums, ignored" ) if $opt_checkYear;
	msgWarn( "'--check-all-track' option is only relevant when listing albums, ignored" ) if $opt_checkAllTrack;
}
if( !$opt_listGenres ){
	msgWarn( "'--step' option is only relevant when listing genres, ignored" ) if $opt_step_set;
}

# should have something to do
# at the moment the '--list-albums' is a default action
if( !$opt_listAlbums && !$opt_listGenres ){
	msgWarn( "none of '--list-albums' or '--list-genres' options have been specified, nothing to do" );
}

if( !TTP::errs()){
	listAlbums() if $opt_listAlbums;
	listGenres() if $opt_listGenres;
}

TTP::exit();
