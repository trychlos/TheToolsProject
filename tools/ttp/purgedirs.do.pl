# @(#) purge directories from a path
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --dirpath=s             the source path [${dirpath}]
# @(-) --dircmd=s              the command which will give the source path [${dircmd}]
# @(-) --keep=s                count of to-be-kept directories [${keep}]
#
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

use strict;
use utf8;
use warnings;

use File::Path qw( remove_tree );
use File::Spec;

use TTP::Path;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	dirpath => '',
	dircmd => '',
	keep => '0'
};

my $opt_dirpath = $defaults->{dirpath};
my $opt_dircmd = $defaults->{dircmd};
my $opt_keep = $defaults->{keep};

# -------------------------------------------------------------------------------------------------
# Purge directories from source, only keeping some in source
# - ignore dot files and dot dirs
# - ignore files, only considering dirs

sub doPurgeDirs {
	msgOut( "purging from '$opt_dirpath', keeping '$opt_keep' item(s)" );
	my $count = 0;
	if( -d $opt_dirpath ){
		opendir( FD, "$opt_dirpath" ) || msgErr( "unable to open directory $opt_dirpath: $!" );
		if( !TTP::errs()){
			my @list = ();
			while ( my $it = readdir( FD )){
				my $path = File::Spec->catdir( $opt_dirpath, $it );
				if( $it =~ /^\./ ){
					msgVerbose( "ignoring '$path'" );
					next;
				}
				if( -d "$path" ){
					push( @list, "$it" );
					next;
				}
				msgVerbose( "ignoring '$path'" );
			}
			closedir( FD );
			# sort in reverse order: most recent first as we expect a periodic naming
			@list = sort { $b cmp $a } @list;
			msgVerbose( "got ".scalar @list." item(s) in $opt_dirpath" );
			# build the lists to be kept and moved
			my @keep = ();
			if( $opt_keep >= scalar @list ){
				msgOut( "found ".scalar @list." item(s) in '$opt_dirpath' while wanting keep $opt_keep: nothing to do" );
			} else {
				for( my $i=0 ; $i<$opt_keep ; ++$i ){
					my $it = shift( @list );
					msgVerbose( "keeping "._sourcePath( $it ));
					push( @keep, $it );
				}
				# and remove the rest
				foreach my $it ( @list ){
					my $dir = File::Spec->catdir( $opt_dirpath, $it );
					msgOut( " removing '$dir'" );
					my $res = TTP::Path::removeTree( $dir );
					if( $res ){
						$count += 1;
					}
				}
			}
		}
	} else {
		msgOut( "'$opt_dirpath' doesn't exist: nothing to purge" );
	}
	msgOut( "$count purged directory(ies)" );
}

sub _sourcePath {
	my ( $it ) = @_;
	return File::Spec->catdir( $opt_dirpath, $it );
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> sub { $ep->runner()->help( @_ ); },
	"colored!"			=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"			=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"			=> sub { $ep->runner()->verbose( @_ ); },
	"dirpath=s"			=> \$opt_dirpath,
	"dircmd=s"			=> \$opt_dircmd,
	"keep=s"			=> \$opt_keep )){

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
msgVerbose( "got dirpath='$opt_dirpath'" );
msgVerbose( "got dircmd='$opt_dircmd'" );
msgVerbose( "got keep='$opt_keep'" );

# dircmd and dirpath options are not compatible
my $count = 0;
$count += 1 if $opt_dirpath;
$count += 1 if $opt_dircmd;
msgErr( "one of '--dirpath' and '--dircmd' options must be specified" ) if $count != 1;

# if we have a source cmd, get the path
# no need to make it exist: if not exist, there is just nothing to purge
$opt_dirpath = TTP::Path::fromCommand( $opt_dircmd ) if $opt_dircmd;

if( !TTP::errs()){
	doPurgeDirs();
}

TTP::exit();
