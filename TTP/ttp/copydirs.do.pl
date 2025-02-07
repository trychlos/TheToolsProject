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
# @(-) --[no]dirs              copy directories and their content [${dirs}]
# @(-) --skip=<count>          skip count directories from source (ignored at the moment) [${skip}]
#
# The Tools Project: a Tools System and Paradigm for IT Production
# Copyright (©) 1998-2023 Pierre Wieser (see AUTHORS)
# Copyright (©) 2023-2024 PWI Consulting
#
# The Tools Project is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version.
#
# The Tools Project is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with The Tools Project; see the file COPYING. If not,
# see <http://www.gnu.org/licenses/>.

use utf8;
use strict;
use warnings;

use File::Spec;

my $running = $ep->runner();

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	sourcepath => '',
	sourcecmd => '',
	targetpath => '',
	targetcmd => '',
	dirs => 'no',
	skip => 0
};

my $opt_sourcepath = $defaults->{sourcepath};
my $opt_sourcecmd = $defaults->{sourcecmd};
my $opt_targetpath = $defaults->{targetpath};
my $opt_targetcmd = $defaults->{targetcmd};
my $opt_dirs = false;
my $opt_skip = $defaults->{skip};

# -------------------------------------------------------------------------------------------------
# Copy directories from source to target

sub doCopyDirs {
	msgOut( "copying from '$opt_sourcepath' to '$opt_targetpath'..." );
	my $count = 0;
	my $res = false;
	if( -d $opt_sourcepath ){
		$res = TTP::copyDir( $opt_sourcepath, $opt_targetpath );
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
	"help!"				=> \$ep->{run}{help},
	"colored!"			=> \$ep->{run}{colored},
	"dummy!"			=> \$ep->{run}{dummy},
	"verbose!"			=> \$ep->{run}{verbose},
	"sourcepath=s"		=> \$opt_sourcepath,
	"sourcecmd=s"		=> \$opt_sourcecmd,
	"targetpath=s"		=> \$opt_targetpath,
	"targetcmd=s"		=> \$opt_targetcmd,
	"dirs!"				=> \$opt_dirs,
	"skip=i"			=> \$opt_skip )){

		msgOut( "try '".$running->command()." ".$running->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $running->help()){
	$running->verbHelp( $defaults );
	TTP::exit();
}

msgVerbose( "got colored='".( $running->colored() ? 'true':'false' )."'" );
msgVerbose( "got dummy='".( $running->dummy() ? 'true':'false' )."'" );
msgVerbose( "got verbose='".( $running->verbose() ? 'true':'false' )."'" );
msgVerbose( "got sourcepath='$opt_sourcepath'" );
msgVerbose( "got sourcecmd='$opt_sourcecmd'" );
msgVerbose( "got targetpath='$opt_targetpath'" );
msgVerbose( "got targetcmd='$opt_targetcmd'" );
msgVerbose( "got dirs='".( $opt_dirs ? 'true':'false' )."'" );
msgVerbose( "got skip='$opt_skip'" );

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
$opt_sourcepath = TTP::fromCommand( $opt_sourcecmd ) if $opt_sourcecmd;

# if we have a target cmd, get the path
$opt_targetpath = TTP::fromCommand( $opt_targetcmd ) if $opt_targetcmd;

# --dirs option must be specified at the moment
msgErr( "--dirs' option must be specified (at the moment)" ) if !$opt_dirs;

if( !TTP::errs()){
	doCopyDirs();
}

TTP::exit();
