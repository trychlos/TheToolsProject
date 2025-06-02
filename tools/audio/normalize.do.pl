# @(#) change objects
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --source-path=<source>  acts on this source [${sourcePath}]
# @(-) --target-path=<target>  writes the result on this target [${targetPath}]
# @(-) --format=<format>       accept the file format, may be specified several times or as a comma-separated list [${format}]
# @(-) --album-level=<level>   the directory level where the album is to be find [${albumLevel}]
# @(-) --artist-level=<level>  the directory level where the artist is to be find [${artistLevel}]
# @(-) --[no]dynamics          apply dynamics normalization [${dynamics}]
# @(-) --[no]loudness          apply loudness normalization [${loudness}]
# @(-) --[no]video             reconduct found video streams, including attached images [${video}]
# @(-) --[no]filename          change the track filename [${filename}]
# @(-) --[no]remove            remove original file [${remove}]
# @(-) --limit=<limit>         limits the count of changed files, less than zero for no limit [${limit}]
#
# @(@) Note 1: when no target is specified, results are written in the source tree.
# @(@) Note 2: the first specified '--format' option is the target of format changes.
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

use Encode qw( decode );
use File::Copy qw( move );
use File::Find;
use File::Spec;
use File::Temp qw( :POSIX );

use TTP::Media;
use TTP::Path;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	sourcePath => '',
	targetPath => '',
	format => '',
	albumLevel => 6,
	artistLevel => 5,
	dynamics => 'no',
	filename => 'no',
	loudness => 'no',
	remove => 'no',
	video => 'yes',
	limit => -1
};

my $opt_sourcePath = $defaults->{sourcePath};
my $opt_targetPath = $defaults->{targetPath};
my @opt_formats = ();
my $opt_albumLevel = $defaults->{albumLevel};
my $opt_artistLevel = $defaults->{artistLevel};
my $opt_dynamics = false;
my $opt_loudness = false;
my $opt_filename = false;
my $opt_remove = false;
my $opt_video = true;
my $opt_limit = $defaults->{limit};

# -------------------------------------------------------------------------------------------------
# works on the (existing) dir

sub doFind {
	my $countAlbums = 0;
	my $total_files = 0;
	my $files_err = 0;
	my $files_unchanged = 0;
	my $files_tochange = 0;
	my $changed_files_ok = 0;
	my $changed_files_notok = 0;
	my $albums = {};
	my $current_key = undef;
	msgOut( "acting on '$opt_sourcePath'..." );
	my $result = TTP::Media::scan_tree( $opt_sourcePath, {
		sub => sub {
			# expect to have only supported files
			my ( $fname, $scan ) = @_;
			$total_files += 1;
			return if $opt_limit >= 0 && $total_files > $opt_limit;
			my $albumFromPath = TTP::Media::albumFromPath( $fname, { level => $opt_albumLevel });
			my $artistFromPath = TTP::Media::artistFromPath( $fname, { level => $opt_artistLevel });
			if( $albumFromPath || $artistFromPath ){
				$scan->{albumFromPath} = $albumFromPath;
				$scan->{artistFromPath} = $artistFromPath;
				my $key = "$artistFromPath $albumFromPath";
				$key =~ s/\s/-/g;
				msgOut( "", { withPrefix => false }) if $current_key && $key ne $current_key;
				if( !$albums->{$key} ){
					printAlbum( $scan );
					$current_key = $key;
					$countAlbums += 1;
					$albums->{$key}{albumFromPath} = $scan->{albumFromPath};
					$albums->{$key}{artistFromPath} = $scan->{artistFromPath};
				}
				msgOut( ".", { withPrefix => false, withEol => false });
				if( mustChange( $scan )){
					$files_tochange += 1;
					if( $scan->{changes}{dynamics} || $scan->{changes}{loudness} || $scan->{changes}{format} ){
						my $cmd = ffmpeg_command( $scan );

						# make sure the target directory exists
						if( !$ep->runner()->dummy() && $scan->{output}{path} ne $fname ){
							my( $vol, $directories, $file ) = File::Spec->splitpath( $scan->{output}{path} );
							my $dir = File::Spec->catpath( $vol, $directories, "" );
							TTP::Path::makeDirExist( $dir );
						}
						# and execute the commands
						# plus, maybe, mv and rm commands
						my $res = TTP::commandExec( $cmd );
						if( $res->{success} ){
							if( $scan->{commands} && $scan->{commands}{mv} ){
								$res = TTP::commandExec({
									command => 'mv',
									args => [
										$scan->{commands}{mv},
										$scan->{path}
									]
								});
							}
						}
						if( $res->{success} ){
							if( $scan->{commands} && $scan->{commands}{rm} ){
								$res = TTP::commandExec({
									command => 'rm',
									args => [
										"-f",
										$scan->{path}
									]
								});
							}
						}
						if( $res->{success} ){
							$changed_files_ok += 1;
						} else {
							$changed_files_notok += 1;
							# stderr can be empty, but stdout is far too numerous
							if( $res->{stderr} && scalar( @{$res->{stderr}} )){
								msgErr( $res->{stderr} );
							} else {
								msgErr( "change failed" );
							}
						}

					} elsif( $opt_filename && $fname ne $scan->{output}{path} ){
						move( $fname, $scan->{output}{path} );
						$changed_files_ok += 1;
					}
				} else {
					$files_unchanged += 1;
				}
			} else {
				msgErr( "neither artist nor album can be computed from '$fname'" );
				$files_err += 1;
			}
		}
	});
	msgOut( "", { withPrefix => false }) if $countAlbums > 0;
	# have a summary
	msgOut( "$countAlbums found album(s)" );
	msgOut( "$total_files found files(s), among them $files_err were erroneous, $files_tochange were to be changed, $changed_files_ok were successfully changed and $changed_files_notok changes failed" );
}

# -------------------------------------------------------------------------------------------------
# returns the 'ffmpeg' command-line arguments for applying a dynamics normalization (source ChatGPT)
# note that these arguments should be applied with a '-af' switch, which can only be specified once

sub dynamics_args {
	return "acompressor=threshold=-18dB:ratio=3";
}

# -------------------------------------------------------------------------------------------------
# build the ffmpeg command
# returns a ref to a hash with following keys:
# - command: the 'ffmpeg' command itself, as a string
# - args: a ref to an array of arguments

sub ffmpeg_command {
	my ( $scan ) = @_;

	my @args = ();
	push( @args, "-i" );
	push( @args, "$scan->{path}" );
	
	# happens that attached images are considered as video streams - so do not ignore them
	if( $opt_video ){
		push( @args, "-map" );
		push( @args, "0:a" );
		push( @args, "-map" );
		push( @args, "0:v" );
		push( @args, "-c:v" );
		push( @args, "copy" );
	} else {
		push( @args, "-vn" );	# else remove video streams
	}

	my $dynamics = dynamics_args() if $opt_dynamics;
	my $loudness = loudness_args() if $opt_loudness;
	if( $dynamics || $loudness ){
		push( @args, "-af" );
		push( @args, "$dynamics,$loudness" ) if $dynamics && $loudness;
		push( @args, "$dynamics" ) if $dynamics && !$loudness;
		push( @args, "$loudness" ) if !$dynamics && $loudness;
	}

	# computed options depending of the output format
	push( @args, $scan->{output}{options} ) if $scan->{output}{options};

	# output
	push( @args, "-y" );

	# if input file is not moved nor renamed - must use an intermediate temp file
	if( $scan->{output}{path} eq $scan->{path} ){
		my $tmpfile = tmpnam().".$scan->{suffix}";
		push( @args, "$tmpfile" );
		$scan->{commands} //= {};
		$scan->{commands}{mv} = $tmpfile;

	} else {
		push( @args, "$scan->{output}{path}" );
		# remove the source file ?
		if( $opt_remove ){
			$scan->{commands} //= {};
			$scan->{commands}{rm} = $scan->{path};
		}
	}

	# and return the command object
	return {
		command => 'ffmpeg',
		args => \@args
	};
}

# -------------------------------------------------------------------------------------------------
# List the source,
#  applying the desired changes for each file

sub listSource {
	if( -d $opt_sourcePath ){
		doFind();
	} else {
		msgWarn( "'$opt_sourcePath' doesn't exist, nothing to do" );
	}
}

# -------------------------------------------------------------------------------------------------
# returns the command-line for applying a loudness normalization (source ChatGPT)
# note that these arguments should be applied with a '-af' switch, which can only be specified once

sub loudness_args {
	return "loudnorm=I=-16:TP=-1.5:LRA=11";
}

# -------------------------------------------------------------------------------------------------
# given the scan result, must something be changed for this file
# simultaneously computes the target output file pathname

sub mustChange {
	my ( $scan ) = @_;

	$scan->{changes} //= {};

	# apply loudness and dynamics changes
	$scan->{changes}{dynamics} = true if $opt_dynamics;
	$scan->{changes}{loudness} = true if $opt_loudness;

	# have to change the format ?
	if( scalar( @opt_formats )){
		my $is_accepted = grep( /$scan->{suffix}/i, @opt_formats );
		$scan->{changes}{format} = !$is_accepted;
	}

	# have to normalize the filename ?
	if( $opt_filename ){
		# actual file name without the extension
		my ( $vol, $directories, $filename ) = File::Spec->splitpath( $scan->{path} );
		$filename =~ s/\.[^\.]+$//;
		# theorical track name
		my $number = TTP::Media::trackNumberFromScan( $scan ) || '';
		my $title = TTP::Media::trackTitleFromScan( $scan ) || '';
		if( defined( $number ) && $title ){
			my $str = sprintf( "%02u", ( 0+$number ));
			my $theorical = "$str - $title";

			if( $theorical ne $filename ){
				$scan->{changes}{filename} = {
					old => $filename,
					new => $theorical
				};
			}
		}
	}

	# compute the output file pathname
	my $output = $scan->{path};
	my $options = undef;

	# apply the target directory
	$output =~ s/$opt_sourcePath/$opt_targetPath/ if $opt_targetPath;

	# maybe change the suffix
	if( $scan->{changes}{format} ){
		$output =~ s/\.$scan->{suffix}$/.$opt_formats[0]/i;
		$options = "-acodec aac" if $opt_formats[0] =~ /M4A/i;
	}

	# maybe change the filename
	if( $scan->{changes}{filename} ){
		$output =~ s/\Q$scan->{changes}{filename}{old}\E/$scan->{changes}{filename}{new}/;
	}

	$scan->{output} = {
		path => $output,
		options => $options
	};
	$scan->{changes}{path} = ( $output ne $scan->{path} );

	my $must_change = $scan->{changes}{dynamics} || $scan->{changes}{loudness} || $scan->{changes}{format} || $scan->{changes}{filename} || $scan->{changes}{path};
	msgVerbose( "path='$scan->{path}' mustChange='".( $must_change ? 'true' : 'false' )."'" );

	return $must_change;
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
	my $str = " ";
	$str = $opts->{prefix} if defined $opts->{prefix};
	$str .= "$scan->{artistFromPath} / $scan->{albumFromPath}" if $scan->{artistFromPath} && $scan->{albumFromPath};
	$str .= "$scan->{artistFromPath}" if $scan->{artistFromPath} && !$scan->{albumFromPath};
	$str .= "$scan->{albumFromPath}" if !$scan->{artistFromPath} && $scan->{albumFromPath};
	print STDOUT "$str ";
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
	"target-path=s"		=> \$opt_targetPath,
	"format=s"			=> \@opt_formats,
	"album-level=i"		=> \$opt_albumLevel,
	"artist-level=i"	=> \$opt_artistLevel,
	"dynamics!"			=> \$opt_dynamics,
	"filename!"			=> \$opt_filename,
	"loudness!"			=> \$opt_loudness,
	"remove!"			=> \$opt_remove,
	"video!"			=> \$opt_video,
	"limit=i"			=> \$opt_limit )){

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
msgVerbose( "got target-path='$opt_targetPath'" );
@opt_formats= split( /,/, join( ',', @opt_formats ));
msgVerbose( "got formats='".join( ',', @opt_formats )."'" );
msgVerbose( "got album-level='$opt_albumLevel'" );
msgVerbose( "got artist-level='$opt_artistLevel'" );
msgVerbose( "got dynamics='".( $opt_dynamics ? 'true':'false' )."'" );
msgVerbose( "got loudness='".( $opt_loudness ? 'true':'false' )."'" );
msgVerbose( "got filename='".( $opt_filename ? 'true':'false' )."'" );
msgVerbose( "got remove='".( $opt_remove ? 'true':'false' )."'" );
msgVerbose( "got video='".( $opt_video ? 'true':'false' )."'" );
msgVerbose( "got limit='$opt_limit'" );

# must have --source-path option
msgErr( "'--source-path' option is mandatory, but is not specified" ) if !$opt_sourcePath;

# albumLevel and artistLevel must be greater than zero integers
$opt_albumLevel = int( $opt_albumLevel );
msgErr( "--album-level' option must provide a greater than zero integer, got $opt_albumLevel" ) if $opt_albumLevel <= 0;
$opt_artistLevel = int( $opt_artistLevel );
msgErr( "--artist-level' option must provide a greater than zero integer, got $opt_artistLevel" ) if $opt_artistLevel <= 0;

# maybe should remove when the target path is same than the source
msgWarn( "neither '--target-path' nor '--remove' options are specified, there is a risk of duplicated track files in the same directory" ) if !$opt_targetPath && !$opt_remove;

# should have something to do
if( !$opt_dynamics && !$opt_loudness && !scalar( @opt_formats ) && !$opt_filename ){
	msgWarn( "none of '--dynamics', '--loudness', '--filename' or '--format' options have been specified, nothing to do" );
}

if( !TTP::errs()){
	listSource();
}

TTP::exit();
