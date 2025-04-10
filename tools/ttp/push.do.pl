# @(#) publish code and configurations from a development environment to pull target
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]check             whether to check for cleanity [${check}]
# @(-) --[no]tag               tag the git repository [${tag}]
# @(-) --options=<options>     additional options to be passed to the command [${options}]
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
	tag => 'yes',
	options => ''
};

my $opt_check = true;
my $opt_check_set = false;
my $opt_tag = true;
my $opt_tag_set = false;
my $opt_options = $defaults->{options};

# -------------------------------------------------------------------------------------------------
# publish the development trees to the pull target

sub doPush {
	my $result = false;
	my $asked = 0;
	my $done = 0;
	my $command = 'ttp.pl copydirs --sourcepath <SOURCE> --targetpath <TARGET> --exclude-dir \'.git*\' --exclude-file \'.git*\' <OPTIONS>';
	# may have several source trees: will iterate on each
	my $trees = $ep->var([ 'deployments', 'trees' ]) || [];
	my $count = scalar( @{$trees} );
	if( $count ){
		# if source checks are asked, then all must be OK before copying first
		if( $opt_check ){
			foreach my $tree ( @{$trees} ){
				doPush_gitCheck( $tree );
			}
		} else {
			msgWarn( "no check is made as '--check' option has been set to false" );
		}
		# only copy if checks have no error at all
		if( !TTP::errs()){
			foreach my $tree ( @{$trees} ){
				my $res = doPush_byTree( $tree, $command );
				$asked += $res->{asked};
				$done += $res->{done};
			}
		}
		# only tag git repositories if all copies are OK and tag has been asked and this tree allows tagging
		if( !TTP::errs() && $done == $asked && $opt_tag ){
			foreach my $tree ( @{$trees} ){
				doPush_gitTag( $tree );
			}
		}
		my $str = "$done/$asked copied subdir(s)";
		if( $done == $asked && !TTP::errs()){
			msgOut( "success ($str)" );
		} else {
			msgErr( "NOT OK ($str)" );
		}
	} else {
		msgOut( "'deployments.trees' is not set or empty: nothing to do" );
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
	msgOut( "pushing source='$tree->{source}' to target='$tree->{target}'" );
	$result->{asked} += 1;
	my $cmdres = TTP::commandExec({
		command => $command,
		macros => {
			SOURCE => $tree->{source},
			TARGET => $tree->{target},
			OPTIONS => $opt_options
		}
	});
	$result->{done} += 1 if $cmdres->{success};
	return $result;
}

# check a source tree
# must publish a clean development environment from master branch
# 'tree' is an object { source, target }

sub doPush_gitCheck {
	my ( $tree ) = @_;
	my $allowed = false;
	$allowed = $tree->{'git-check'} if defined $tree->{'git-check'};
	if( $allowed ){
		msgOut( "checking source='$tree->{source}'" );
		my @status = `git -C $tree->{source} status`;
		my $branch = '';
		my $changes = false;
		my $untracked = false;
		my $clean = false;
		foreach my $line ( @status ){
			chomp $line;
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
			msgErr( "$tree->{source}: must publish from 'master' branch, found '$branch'" );
		} else {
			msgVerbose( "$tree->{source}: publishing from '$branch' branch: fine" );
		}
		if( $changes ){
			msgErr( "$tree->{source}: have found uncommitted changes, but shouldn't" );
		} else {
			msgVerbose( "$tree->{source}: no uncommitted change found: fine" );
		}
		if( $untracked ){
			msgErr( "$tree->{source}: have found untracked files, but shouldn't (maybe move them to uncommitted/)" );
		} else {
			msgVerbose( "$tree->{source}: no untracked file found: fine" );
		}
		if( !$clean ){
			msgErr( "$tree->{source}: must publish from a clean working tree, but this one is not" );
		} else {
			msgVerbose( "$tree->{source}: found clean working tree: fine" );
		}
	} else {
		msgVerbose( "do not git-check '$tree->{source}' source tree as not allowed by the configuration" );
	}
}

# git-tag a source tree
# not all source trees are candidate to git tagging - this must be allowed in the JSON configuration
# 'tree' is an object { source, target, git-tag }

sub doPush_gitTag {
	my ( $tree ) = @_;
	my $allowed = false;
	$allowed = $tree->{'git-tag'} if defined $tree->{'git-tag'};
	if( $allowed ){
		msgOut( "tagging '$tree->{source}' git repository" );
		my $now = localtime->strftime( '%Y%m%d_%H%M%S' );
		my $message = $running->command()." ".$running->verb();
		my $command = "git -C $tree->{source} tag -am \"$message\" $now";
		if( $running->dummy()){
			msgDummy( $command );
		} else {
			msgVerbose( $command );
			print `$command`;
		}
	} else {
		msgVerbose( "do not git-tag '$tree->{source}' source tree as not allowed by the configuration" );
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
	"check!"			=> sub {
		my( $name, $value ) = @_;
		$opt_check = $value;
		$opt_check_set = true;
	},
	"tag!"				=> sub {
		my( $name, $value ) = @_;
		$opt_tag = $value;
		$opt_tag_set = true;
	},
	"options=s"			=> \$opt_options )){

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
msgVerbose( "got options='$opt_options'" );

# check that we are pushing only on the pull reference host
my $ref_host = $ep->var([ 'deployments', 'reference' ]);
if( $ref_host ){
	my $this_host = $ep->node()->name();
	if( $ref_host ne $this_host ){
		msgErr( "must push on pull reference host '$ref_host', found '$this_host'" );
	} else {
		msgVerbose( "pushing on pull reference host '$ref_host': fine" );
	}
} else {
	msgWarn( "'deployements.reference' node name expected, not found. Terminating..." );
	TTP::exit();
}

# cannot git-tag if not previously git-checked
if( $opt_tag && !$opt_check ){
	if( $opt_tag_set ){
		msgErr( "cannot git-tag if not previously git-checked" );
	} else {
		msgVerbose( "not git-tagging as not git-checking" );
		$opt_tag = false;
	}
}

if( !TTP::errs()){
	doPush();
}

TTP::exit();
