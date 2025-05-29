# @(#) change objects
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --source-path=<source>  acts on this source [${sourcePath}]
# @(-) --format=<format>       accept the file format, may be specified several times or as a comma-separated list [${format}]
# @(-) --[no]dynamics          apply dynamics normalization [${dynamics}]
# @(-) --[no]loudness          apply loudness normalization [${loudness}]
# @(-) --target-path=<target>  writes the result on this target [${targetPath}]
# @(-) --limit=<limit>         limits the count of changed files, less than zero for no limit [${limit}]
# @(-) --[no]video             reconduct found video streams [${video}]
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
	loudness => 'no',
	dynamics => 'no',
	limit => -1,
	video => 'no'
};

my $opt_sourcePath = $defaults->{sourcePath};
my $opt_targetPath = $defaults->{targetPath};
my $opt_dynamics = false;
my $opt_loudness = false;
my @opt_formats = ();
my $opt_limit = $defaults->{limit};
my $opt_video = false;

# -------------------------------------------------------------------------------------------------
# returns the command-line for applying a dynamics normalization (source ChatGPT)

sub dynamics {
	return "acompressor=threshold=-18dB:ratio=3";
}

# -------------------------------------------------------------------------------------------------
# returns the command-line for applying a loudness normalization (source ChatGPT)

sub loudness {
	return "loudnorm=I=-16:TP=-1.5:LRA=11";
}

# -------------------------------------------------------------------------------------------------
# given the scan result, must something be changed for this file

sub mustChange {
	my ( $scan ) = @_;

	my $must_change = false;

	if( scalar( @opt_formats )){
		my $is_accepted = grep( /$scan->{suffix}/i, @opt_formats );
		$must_change = !$is_accepted;
	}

	$must_change |= $opt_dynamics;
	$must_change |= $opt_loudness;

	return $must_change;
}

# -------------------------------------------------------------------------------------------------
# compute the output file pathname

sub output {
	my ( $scan ) = @_;

	my $output = $scan->{path};
	my $options = undef;

	# maybe change the pathname
	$output =~ s/$opt_sourcePath/$opt_targetPath/ if $opt_targetPath;

	# maybe change the suffix
	if( scalar( @opt_formats )){
		my $is_accepted = grep( /$scan->{suffix}/i, @opt_formats );
		if( !$is_accepted ){
			$output =~ s/\.$scan->{suffix}$/.$opt_formats[0]/i;
			$options = "-acodec aac" if $opt_formats[0] =~ /M4A/i;
		}
	}

	return ( $output, $options );
}

# -------------------------------------------------------------------------------------------------
# List the source,
#  applying the desired changes for each file

sub listSource {
	my $countAlbums = 0;
	my $total_files = 0;
	my $files_err = 0;
	my $files_unchanged = 0;
	my $changed_files_ok = 0;
	my $changed_files_notok = 0;
	my $albums = {};
	my $current_key = undef;
	msgOut( "acting on '$opt_sourcePath'..." );
	find({
		# receive here all found files and directories
		wanted => sub {
			my $fname = decode( 'UTF-8', $File::Find::name );
			# ignore directories
			if( ! -d $_ && TTP::Media::isAudio( $fname )){
				$total_files += 1;
				return if $opt_limit >= 0 && $total_files > $opt_limit;
				my $scan = TTP::Media::scan( $fname );
				my $albumFromPath = TTP::Media::albumFromPath( $fname );
				my $artistFromPath = TTP::Media::artistFromPath( $fname );
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
						my $cmd = "ffmpeg -i \"$fname\"";
						$cmd .= " -vn" if !$opt_video;
						my $dynamics = dynamics() if $opt_dynamics;
						my $loudness = loudness() if $opt_loudness;
						if( $dynamics || $loudness ){
							$cmd .= " -af \"$dynamics,$loudness\"" if $dynamics && $loudness;
							$cmd .= " -af \"$dynamics\"" if $dynamics && !$loudness;
							$cmd .= " -af \"$loudness\"" if !$dynamics && $loudness;
						}
						my ( $output, $options ) = output( $scan );
						$cmd .= " $options" if $options;
						# make sure the target directory exists
						if( !$ep->runner()->dummy() && $output ne $fname ){
							my( $vol, $directories, $file ) = File::Spec->splitpath( $output );
							my $dir = File::Spec->catpath( $vol, $directories, "" );
							TTP::Path::makeDirExist( $dir );
						}
						# if input file is not moved nor renamed - must use an intermediate temp file
						if( $output eq $fname ){
							my $tmpfile = tmpnam().".$scan->{suffix}";
							$cmd .= " -y \"$tmpfile\" && mv \"$tmpfile\" \"$fname\"";
						} else {
							$cmd .= " -y \"$output\"";
						}
						# and execute the command
						my $res = TTP::commandExec( $cmd );
						if( $res->{success} ){
							$changed_files_ok += 1;
						} else {
							$changed_files_notok += 1;
							# stderr can be empty, but stdout is far too numerous
							if( scalar( @{$res->{stderr}} )){
								msgErr( $res->{stderr} );
							} else {
								msgErr( "change failed" );
							}
						}

					} else {
						msgVerbose( "nothing to change in $scan" );
						$files_unchanged += 1;
					}
				} else {
					msgErr( "neither artist nor album can be computed from '$fname'" );
					$files_err += 1;
				}
			} else {
				msgVerbose( "ignoring directory or non-audio $fname" );
			}
		},
	}, $opt_sourcePath );
	msgOut( "", { withPrefix => false }) if $countAlbums > 0;
	# have a summary
	msgOut( "$countAlbums found album(s)" );
	msgOut( "$total_files found files(s), among them $files_err were erroneous, $changed_files_ok were successfully changed and $changed_files_notok cannot be" );
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
	"dynamics!"			=> \$opt_dynamics,
	"loudness!"			=> \$opt_loudness,
	"format=s"			=> \@opt_formats,
	"limit=i"			=> \$opt_limit,
	"video!"			=> \$opt_video )){

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
msgVerbose( "got dynamics='".( $opt_dynamics ? 'true':'false' )."'" );
msgVerbose( "got loudness='".( $opt_loudness ? 'true':'false' )."'" );
@opt_formats= split( /,/, join( ',', @opt_formats ));
msgVerbose( "got formats='".join( ',', @opt_formats )."'" );
msgVerbose( "got limit='$opt_limit'" );
msgVerbose( "got video='".( $opt_video ? 'true':'false' )."'" );

# must have --source-path option
msgErr( "'--source-path' option is mandatory, but is not specified" ) if !$opt_sourcePath;

# should have something to do
if( !$opt_dynamics && !$opt_loudness && !scalar( @opt_formats )){
	msgWarn( "neither '--dynamics', '--loudness' of '--format' options have been specified, nothing to do" );
}

if( !TTP::errs()){
	listSource();
}

TTP::exit();
