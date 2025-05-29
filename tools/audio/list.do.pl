# @(#) list objects
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --source-path=<source>  acts on this source [${sourcePath}]
# @(-) --[no]list-albums       list the albums [${listAlbums}]
# @(-) --[no]check-artist      check the artist [${checkArtist}]
# @(-) --[no]check-album       check the album [${checkAlbum}]
# @(-) --[no]check-year        check the year [${checkYear}]
# @(-) --[no]check-genre       check the genre [${checkGenre}]
# @(-) --[no]check-cover       check the cover [${checkCover}]
# @(-) --[no]check-title       check the track title [${checkTitle}]
# @(-) --[no]check-number      check the track number [${checkNumber}]
# @(-) --[no]check-count       check the tracks count [${checkCount}]
# @(-) --[no]check-path-album  check the album directory name [${checkAlbumPath}]
# @(-) --[no]check-path-track  check the track file name [${checkTrackPath}]
# @(-) --[no]check-all         check all available properties [${checkAll}]
# @(-) --format=<format>       output albums with this format [${format}]
#
# @(@) Note 1: 'format' is a sprintf() format string with following macros:
# @(@)         - %AP: artist from the path
# @(@)         - %BP: album from the path
# @(@)         - %AS: artist from the scan
# @(@)         - %BS: album from the scan
# @(@)         - %G: genre
# @(@)         - %Y: year
# @(@)         - %TC: track count
# @(@) Note 2: '--check-album-path' acts as the album level, and so is not covered by the '--check-all' option

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

use Encode qw( decode );
use File::Find;
use File::Spec;

use TTP::Media;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	sourcePath => '',
	listAlbums => 'no',
	checkAlbum => 'no',
	checkAlbumPath => 'no',
	checkArtist => 'no',
	checkCount => 'no',
	checkCover => 'no',
	checkGenre => 'no',
	checkNumber => 'no',
	checkTitle => 'no',
	checkTrackPath => 'no',
	checkYear => 'no',
	checkAll => 'no',
	format => '%AP / %BP'
};

my $opt_sourcePath = $defaults->{sourcePath};
my $opt_listAlbums = false;
my $opt_checkAlbum = false;
my $opt_checkAlbumPath = false;
my $opt_checkArtist = false;
my $opt_checkCount = false;
my $opt_checkCover = false;
my $opt_checkGenre = false;
my $opt_checkNumber = false;
my $opt_checkTitle = false;
my $opt_checkTrackPath = false;
my $opt_checkYear = false;
my $opt_checkAll = false;
my $opt_format = $defaults->{format};

# register here the counters at the album level
my $check_albums = [
	'albumdir'
];

# -------------------------------------------------------------------------------------------------
# given an audio file path, check that it contains an album tag
# https://id3.org/id3v2.3.0#Default_flags
#   TALB    [#TALB Album/Movie/Show title]
#   TOAL    [#TOAL Original album/movie/show title]
# for each album, count ok/notok

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

	# actual directory name
	my $albumFromPath = $scan->{albumFromPath};

	# theorical directory name
	my $album = TTP::Media::albumFromScan( $scan ) || '';
	my $year = TTP::Media::yearFromScan( $scan ) || '';
	my $theorical = "$album [$year]";

	# are we equal ?
	my $ok = $albumFromPath eq $theorical;

	# maybe increment counters per album
	$hash->{albumdir} //= {};
	$hash->{albumdir}{count} //= 0;
	$hash->{albumdir}{count} += 1;
	if( $ok ){
		$hash->{albumdir}{ok} //= 0;
		$hash->{albumdir}{ok} += 1;
	} else {
		$hash->{albumdir}{notok} //= 0;
		$hash->{albumdir}{notok} += 1;
		msgWarn( "album path not ok for '$albumFromPath' (theorical='$theorical')" );
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
# given an audio file path, check that it contains a track title tag
# for each album, count ok/notok

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
	my $countAlbums = 0;
	my $countCheckAlbums = 0;
	my $countCheckAlbumPaths = 0;
	my $countCheckArtists = 0;
	my $countCheckCounts = 0;
	my $countCheckCovers = 0;
	my $countCheckGenres = 0;
	my $countCheckNumbers = 0;
	my $countCheckTitles = 0;
	my $countCheckTrackPaths = 0;
	my $countCheckYears = 0;
	my $albums = {};
	msgOut( "displaying music albums in '$opt_sourcePath'..." );
	my $check_file = $opt_checkAlbum || $opt_checkArtist || $opt_checkCount || $opt_checkCover || $opt_checkGenre || $opt_checkNumber || $opt_checkTitle || $opt_checkYear || $opt_checkAll;
	find({
		# receive here all found files and directories
		wanted => sub {
			my $fname = decode( 'UTF-8', $File::Find::name );
			# the album should be one of the directory levels
			# but unless we have a file pathname, we cannot guess if the directory is - or not - an album path
			if( -d $_ ){
				msgVerbose( "ignoring directory $fname" );
			# 	as soon as we have a file, we can try to guess the artist / album
			} else {
				if( TTP::Media::isAudio( $fname )){
					# scan may be not ok but we need a key and some stats in all cases
					my $scan = TTP::Media::scan( $fname );
					my $albumFromPath = TTP::Media::albumFromPath( $fname );
					my $artistFromPath = TTP::Media::artistFromPath( $fname );
					# unless the very rare case where we do not know how to compute the key
					if( $albumFromPath || $artistFromPath ){
						$scan->{albumFromPath} = $albumFromPath;
						$scan->{artistFromPath} = $artistFromPath;
						my $key = "$artistFromPath $albumFromPath";
						$key =~ s/\s/-/g;
						if( !$albums->{$key} ){
							printAlbum( $scan );
							$countAlbums += 1;
							$albums->{$key}{albumFromPath} = $albumFromPath;
							$albums->{$key}{artistFromPath} = $artistFromPath;
							$countCheckAlbumPaths += ( checkAlbumPath( $albums->{$key}, $scan ) ? 1 : 0 ) if $opt_checkAlbumPath;
						}
						$albums->{$key}{valid} //= {};
						$albums->{$key}{valid}{count} //= 0;
						$albums->{$key}{valid}{count} += 1;
						# and check only if a valid audio file
						if( $scan->{ok} ){
							$albums->{$key}{valid}{ok} //= 0;
							$albums->{$key}{valid}{ok} += 1;
							if( $check_file ){
								$countCheckAlbums += ( checkAlbum( $albums->{$key}, $scan ) ? 1 : 0 ) if $opt_checkAlbum || $opt_checkAll;
								$countCheckArtists += ( checkArtist( $albums->{$key}, $scan ) ? 1 : 0 ) if $opt_checkArtist || $opt_checkAll;
								$countCheckCounts += ( checkCount( $albums->{$key}, $scan ) ? 1 : 0 ) if $opt_checkCount || $opt_checkAll;
								$countCheckCovers += ( checkCover( $albums->{$key}, $scan ) ? 1 : 0 ) if $opt_checkCover || $opt_checkAll;
								$countCheckGenres += ( checkGenre( $albums->{$key}, $scan ) ? 1 : 0 ) if $opt_checkGenre || $opt_checkAll;
								$countCheckNumbers += ( checkNumber( $albums->{$key}, $scan ) ? 1 : 0 ) if $opt_checkNumber || $opt_checkAll;
								$countCheckTitles += ( checkTitle( $albums->{$key}, $scan ) ? 1 : 0 ) if $opt_checkTitle || $opt_checkAll;
								$countCheckTrackPaths += ( checkTrackPath( $albums->{$key}, $scan ) ? 1 : 0 ) if $opt_checkTrackPath || $opt_checkAll;
								$countCheckYears += ( checkYear( $albums->{$key}, $scan ) ? 1 : 0 ) if $opt_checkYear || $opt_checkAll;
							}
						} else {
							msgErr( $scan->{errors}, { incErr => false });
							$albums->{$key}{valid}{notok} //= 0;
							$albums->{$key}{valid}{notok} += 1;
							$albums->{$key}{valid}{files} //= [];
							push( @{$albums->{$key}{scan}{files}}, $fname );
						}
					} else {
						msgErr( "neither artist nor album can be computed from '$fname'" );
					}
				} else {
					msgVerbose( "ignoring non-audio $fname" );
				}
			}
		},
	}, $opt_sourcePath );
	# have a summary
	#print Dumper( $albums );
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
	msgOut( "$countAlbums found album(s), among them $countOk were ok" );
	if( scalar( @{$errAlbums} )){
		msgOut(( scalar( @{$errAlbums} ))." album(s) were NOT ok:" );
		foreach my $key ( @{$errAlbums} ){
			my $album = $albums->{$key};
			#print Dumper( $album );
			msgOut( "  $album->{artistFromPath} / $album->{albumFromPath}" );
			if( $albums->{$key}{erralbums} && scalar( @{$albums->{$key}{erralbums}} )){
				msgOut( "    ".join( ',', @{$album->{erralbums}}));
			}
			foreach my $f ( sort keys %{$album->{errfiles}} ){
				msgOut( "    $f: ".join( ',', @{$album->{errfiles}{$f}}));
			}
		}
	}
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

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> sub { $ep->runner()->help( @_ ); },
	"colored!"			=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"			=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"			=> sub { $ep->runner()->verbose( @_ ); },
	"source-path=s"		=> \$opt_sourcePath,
	"list-albums!"		=> \$opt_listAlbums,
	"check-album!"		=> \$opt_checkAlbum,
	"check-album-path!"	=> \$opt_checkAlbumPath,
	"check-artist!"		=> \$opt_checkArtist,
	"check-count!"		=> \$opt_checkCount,
	"check-cover!"		=> \$opt_checkCover,
	"check-genre!"		=> \$opt_checkGenre,
	"check-number!"		=> \$opt_checkNumber,
	"check-title!"		=> \$opt_checkTitle,
	"check-track-path!"	=> \$opt_checkTrackPath,
	"check-year!"		=> \$opt_checkYear,
	"check-all!"		=> \$opt_checkAll,
	"format=s"			=> \$opt_format )){

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
msgVerbose( "got check-album='".( $opt_checkAlbum ? 'true':'false' )."'" );
msgVerbose( "got check-album-path='".( $opt_checkAlbumPath ? 'true':'false' )."'" );
msgVerbose( "got check-artist='".( $opt_checkArtist ? 'true':'false' )."'" );
msgVerbose( "got check-count='".( $opt_checkCount ? 'true':'false' )."'" );
msgVerbose( "got check-cover='".( $opt_checkCover ? 'true':'false' )."'" );
msgVerbose( "got check-genre='".( $opt_checkGenre ? 'true':'false' )."'" );
msgVerbose( "got check-number='".( $opt_checkNumber ? 'true':'false' )."'" );
msgVerbose( "got check-title='".( $opt_checkTitle ? 'true':'false' )."'" );
msgVerbose( "got check-track-path='".( $opt_checkTrackPath ? 'true':'false' )."'" );
msgVerbose( "got check-year='".( $opt_checkYear ? 'true':'false' )."'" );
msgVerbose( "got check-all='".( $opt_checkAll ? 'true':'false' )."'" );
msgVerbose( "got format='$opt_format'" );

# must have --source-path option
msgErr( "'--source-path' option is mandatory, but is not specified" ) if !$opt_sourcePath;

# should have something to do
if( !$opt_listAlbums ){
	msgWarn( "none of '--list-albums' options have been specified, nothing to do" );
}

if( !TTP::errs()){
	listAlbums() if $opt_listAlbums;
}

TTP::exit();
