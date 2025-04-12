# @(#) copy directories from a source to a target
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --sourcepath=s          the source path [${sourcepath}]
# @(-) --sourcecmd=s           the command which will give the source path [${sourcecmd}]
# @(-) --targetpath=s          the target path [${targetpath}]
# @(-) --targetcmd=s           the command which will give the target path [${targetcmd}]
# @(-) --exclude-dirs=<dir>    exclude these source directories from the copy [${excludedirs}]
# @(-) --exclude-files=<file>  exclude these files from the copy [${excludefiles}]
# @(-) --options=<options>     additional options to be passed to the command [${options}]
# @(-) --[no]empty             whether to empty the target tree before the copy [${empty}]
#
# @(@) Both --exclude-dir and --exclude-file can be specified several times, and/or as a comma-separated list of values, and/or as globs.
#
# The Tools Project - Tools System and Working Paradigm for IT Production
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

use TTP::Path;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	sourcepath => '',
	sourcecmd => '',
	targetpath => '',
	targetcmd => '',
	excludedirs => '',
	excludefiles => '',
	options => ''
};

my $opt_sourcepath = $defaults->{sourcepath};
my $opt_sourcecmd = $defaults->{sourcecmd};
my $opt_targetpath = $defaults->{targetpath};
my $opt_targetcmd = $defaults->{targetcmd};
my $opt_dirs = true;
my $opt_dirs_set = false;
my @opt_excludeDirs = ();
my @opt_excludeFiles = ();
my $opt_options = $defaults->{options};

my $opt_empty = $ep->var([ 'copyDir', 'before', 'emptyTree' ]);
$opt_empty = true if !defined $opt_empty;
$defaults->{empty} = $opt_empty ? 'yes' : 'no';

# -------------------------------------------------------------------------------------------------
# Copy directories from source to target

sub doCopyDirs {
	msgOut( "copying from '$opt_sourcepath' to '$opt_targetpath'..." );
	my $count = 0;
	my $res = false;
	if( -d $opt_sourcepath ){
		$res = TTP::Path::copyDir( $opt_sourcepath, $opt_targetpath, {
			excludeDirs => \@opt_excludeDirs,
			excludeFiles => \@opt_excludeFiles,
			options => $opt_options,
			emptyTree => $opt_empty
		});
		$count += 1 if $res;
	} else {
		msgOut( "'$opt_sourcepath' doesn't exist: nothing to copy" );
		$res = true;
	}
	if( $res ){
		msgOut( "$count copied directory(ies)" );
	} else {
		msgErr( "NOT OK", { incErr => false });
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> sub { $ep->runner()->help( @_ ); },
	"colored!"			=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"			=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"			=> sub { $ep->runner()->verbose( @_ ); },
	"sourcepath=s"		=> \$opt_sourcepath,
	"sourcecmd=s"		=> \$opt_sourcecmd,
	"targetpath=s"		=> \$opt_targetpath,
	"targetcmd=s"		=> \$opt_targetcmd,
	"dirs!"				=> sub {
		my( $name, $value ) = @_;
		$opt_dirs = $value;
		$opt_dirs_set = true;
	},
	"exclude-dirs=s@"	=> \@opt_excludeDirs,
	"exclude-files=s@"	=> \@opt_excludeFiles,
	"options=s"			=> \$opt_options,
	"empty!"			=> \$opt_empty )){

		msgOut( "try '".$ep->runner()->command()." ".$ep->runner()->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $ep->runner()->help()){
	$ep->runner()->verbHelp( $defaults );
	TTP::exit();
}

msgVerbose( "got colored='".( $ep->runner()->colored() ? 'true':'false' )."'" );
msgVerbose( "got dummy='".( $ep->runner()->dummy() ? 'true':'false' )."'" );
msgVerbose( "got verbose='".( $ep->runner()->verbose() ? 'true':'false' )."'" );
msgVerbose( "got sourcepath='$opt_sourcepath'" );
msgVerbose( "got sourcecmd='$opt_sourcecmd'" );
msgVerbose( "got targetpath='$opt_targetpath'" );
msgVerbose( "got targetcmd='$opt_targetcmd'" );
msgVerbose( "got dirs='".( $opt_dirs ? 'true':'false' )."'" );
msgVerbose( "got dirs_set='".( $opt_dirs_set ? 'true':'false' )."'" );
@opt_excludeDirs = split( /,/, join( ',', @opt_excludeDirs ));
msgVerbose( "got exclude_dirs='".join( ',', @opt_excludeDirs )."'" );
@opt_excludeFiles = split( /,/, join( ',', @opt_excludeFiles ));
msgVerbose( "got exclude_files='".join( ',', @opt_excludeFiles )."'" );
msgVerbose( "got options='$opt_options'" );
msgVerbose( "got empty='".( $opt_empty ? 'true':'false' )."'" );

# sourcecmd and sourcepath options are not compatible
my $count = 0;
$count += 1 if $opt_sourcepath;
$count += 1 if $opt_sourcecmd;
msgErr( "one of '--sourcepath' and '--sourcecmd' options must be specified" ) if $count != 1;

# targetcmd and targetpath options are not compatible
$count = 0;
$count += 1 if $opt_targetpath;
$count += 1 if $opt_targetcmd;
msgErr( "one of '--targetpath' and '--targetcmd' options must be specified" ) if $count != 1;

# if we have a source cmd, get the path
# no need to make dir exist: if not exist, just nothing to copy
$opt_sourcepath = TTP::Path::fromCommand( $opt_sourcecmd ) if $opt_sourcecmd;

# if we have a target cmd, get the path
$opt_targetpath = TTP::Path::fromCommand( $opt_targetcmd ) if $opt_targetcmd;

# --dirs option is deprecated as of v4.2
if( $opt_dirs_set ){
	msgWarn( "'--dirs' option is deprecated since v4.2. You should update your code." );
}

if( !TTP::errs()){
	doCopyDirs() if $opt_dirs;
}

TTP::exit();
