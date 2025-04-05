# @(#) publish code and configurations from development environment to pull target
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]check             whether to check for cleanity [${check}]
# @(-) --[no]tag               tag the git repository [${tag}]
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

use Config;
use File::Copy::Recursive qw( dircopy pathrmdir );
use File::Spec;
use Time::Piece;

my $running = $ep->runner();

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	check => 'yes',
	tag => 'yes'
};

my $opt_check = true;
my $opt_tag = true;

# -------------------------------------------------------------------------------------------------
# publish the development trees to the pull target

sub doPush {
	my $result = false;
	msgOut( "publishing..." );
	my $asked = 0;
	my $done = 0;
	# if a byOS command is specified, then use it
	my $command = $ep->var([ 'deployments', 'command', 'byOS', $Config{osname} ]);
	msgVerbose( "found command='$command'" );
	# may have several source trees: will iterate on each
	my $sourceTrees = $ep->var([ 'deployments', 'push', 'trees' ]);
	foreach my $tree ( @{$sourceTrees} ){
		my $res = doPush_byTree( $tree, $command );
		$asked += $res->{asked};
		$done += $res->{done};
	}
	if( 0 ){
		if( $done == $asked && !TTP::errs() && $opt_tag ){
			msgOut( "tagging the git repository" );
			my $now = localtime->strftime( '%Y%m%d_%H%M%S' );
			my $message = $running->command()." ".$running->verb();
			my $command = "git tag -am \"$message\" $now";
			if( $running->dummy()){
				msgDummy( $command );
			} else {
				msgVerbose( $command );
				print `$command`;
			}
		}
	}
	my $str = "$done/$asked copied subdir(s)";
	if( $done == $asked && !TTP::errs()){
		msgOut( "success ($str)" );
	} else {
		msgErr( "NOT OK ($str)" );
	}
}

# push one source tree
# 'tree' is an object { source, target }

sub doPush_byTree {
	my ( $tree, $command ) = @_;
	my $result = {
		asked => 0,
		done => 0
	};
	msgVerbose( "pushing source='$tree->{source}' to target='$tree->{target}'" );
	$result->{asked} += 1;
	if( $command ){
		my $cmdres = TTP::commandByOs({
			command => $command,
			macros => {
				SOURCE => $tree->{source},
				TARGET => $tree->{target}
			}
		});
		$result->{done} += 1 if $cmdres->{result};
	} else {
		my $rc = pathrmdir( $tree->{target} );
		if( defined $rc ){
			msgVerbose( "doPush.pathrmdir() got rc=$rc" );
		} else {
			msgErr( "error detected in pathrmdir(): $!" );
		}
		# may happen:
		# (ERR) error detected in dircopy(): Permission denied
		# (ERR) error detected in dircopy(): Not a directory
		my( $num_of_files_and_dirs, $num_of_dirs, $depth_traversed ) = dircopy( $tree->{source}, $tree->{target} );
		if( defined $num_of_files_and_dirs ){
			msgVerbose( "num_of_files_and_dirs='$num_of_files_and_dirs'" );
			msgVerbose( "num_of_dirs='$num_of_dirs'" );
			msgVerbose( "depth_traversed='$depth_traversed'" );
		} else {
			msgErr( "error detected in dircopy(): $!" );
		}
		if( !TTP::errs()){
			$result->{done} += 1;
		}
	}
	return $result;
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$ep->{run}{help},
	"colored!"			=> \$ep->{run}{colored},
	"dummy!"			=> \$ep->{run}{dummy},
	"verbose!"			=> \$ep->{run}{verbose},
	"check!"			=> \$opt_check,
	"tag!"				=> \$opt_tag )){

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
msgVerbose( "got check='".( $opt_check ? 'true':'false' )."'" );
msgVerbose( "got tag='".( $opt_tag ? 'true':'false' )."'" );

if( $opt_check ){
	# must publish a clean development environment from master branch
	my $status = `git status`;
	my @status = split( /[\r\n]/, $status );
	my $branch = '';
	my $changes = false;
	my $untracked = false;
	my $clean = false;
	foreach my $line ( @status ){
		if( $line =~ /^On branch/ ){
			$branch = $line;
			$branch =~ s/^On branch //;
		}
		if( $line =~ /working tree clean/ ){
			$clean = true;
		}
		# either changes not staged or changes to be committed
		if( $line =~ /^Changes / ){
			$changes  = true;
		}
		if( $line =~ /^Untracked files:/ ){
			$untracked  = true;
		}
	}
	if( $branch ne 'master' ){
		msgErr( "must publish from 'master' branch, found '$branch'" );
	} else {
		msgVerbose( "publishing from '$branch' branch: fine" );
	}
	if( $changes ){
		msgErr( "have found uncommitted changes, but shouldn't" );
	} else {
		msgVerbose( "no uncommitted change found: fine" );
	}
	if( $untracked ){
		msgErr( "have found untracked files, but shouldn't (maybe move them to uncommitted/)" );
	} else {
		msgVerbose( "no untracked file found: fine" );
	}
	if( !$clean ){
		msgErr( "must publish from a clean working tree, but this one is not" );
	} else {
		msgVerbose( "found clean working tree: fine" );
	}
} else {
	msgWarn( "no check is made as '--check' option has been set to false" );
}

if( !TTP::errs()){
	doPush();
}

TTP::exit();
