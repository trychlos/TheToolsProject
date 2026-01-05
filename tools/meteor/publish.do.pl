# @(#) publish a package
#
# @(-) --[no]help                  print this message, and exit [${help}]
# @(-) --[no]colored               color the output depending of the message level [${colored}]
# @(-) --[no]dummy                 dummy run [${dummy}]
# @(-) --[no]verbose               run verbosely [${verbose}]
# @(-) --package=<path>            package root path [${package}]
# @(-) --[no]github                publish to Github [${github}]
# @(-) --[no]meteor                publish to Meteor [${meteor}]
# @(-) --[no]all                   publish to all targets [${all}]
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

use File::Spec;
use JSON;
use Path::Tiny;
use Time::Moment;

use TTP::Meteor;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	package => Path::Tiny->cwd,
	github => 'no',
	meteor => 'no',
	all => 'no'
};

my $opt_package = $defaults->{package};
my $opt_github = false;
my $opt_meteor = false;
my $opt_all = false;

# the package object
my $package;

# -------------------------------------------------------------------------------------------------
# return the date as yyyy, Jan. 1st

sub dateWithCommas {
	my $str = Time::Moment->now->strftime( '%Y, %b.' );
	my $day = Time::Moment->now->strftime( '%d' );
	$day =~ s/^0//;
	if( $day == 1 ){
		$day .= 'st';
	} elsif( $day == 2 ){
		$day .= 'nd';
	} elsif( $day == 3 ){
		$day .= 'rd';
	} else {
		$day .= 'th';
	}
	return "$str $day";
}

# -------------------------------------------------------------------------------------------------
# return the date as yyyy- m- d

sub dateWithDashes {
	my $str = Time::Moment->now->strftime( '%Y-%m-%d' );
	$str =~ s/-0/- /g;
	return $str;
}

# -------------------------------------------------------------------------------------------------
# we expect to run from the 'vnext' branch, and have a master branch
# return true|false

sub checkGitBranch {
    my $res = true;
    my $stdout = execLocal( 'git branch', { withDummy => false });
	return false if !$stdout;
	# if we have found git branch(es), we check that current is vnext and that master exists
	if( scalar( @{$stdout} )){
		my @currents = grep( /^\* /, @{$stdout} );
		if( scalar( @currents ) != 1 ){
			msgWarn( "unable to identify the current git branch" );
			$res = false;
		} else {
			msgVerbose( "found a current git branch, fine" );
			my $current = $currents[0];
			$current =~ s/^\*\s*//;
			if( $current eq 'vnext' ){
				msgVerbose( "found 'vnext' branch, fine" );
				my @masters = grep( /^\s*master$/, @{$stdout} );
				if( scalar( @masters ) == 1 ){
					msgVerbose( "found 'master' branch, fine" );
				} else {
					msgWarn( "unable to identify the 'master' branch" );
					$res = false;
				}

			} else {
				msgWarn( "found current branch = '$current', while 'vnext' was expected" );
				$res = false;
			}
		}
	} else {
		msgWarn( "no git branch found" );
		return false;
	}
	return $res;
}

# -------------------------------------------------------------------------------------------------
# check that the git repository is clean
# return true|false

sub checkGitClean {
    my $res = true;
    my $stdout = execLocal( 'git status', { withDummy => false });
	return false if !$stdout;
	# if we have found git branch(es), check that we have nothing to commit
	if( scalar( @{$stdout} )){
		my @commits = grep( /nothing to commit, working tree clean/, @{$stdout} );
		if( scalar( @commits ) != 1 ){
			msgWarn( "you still have changes in your git working tree" );
			$res = false;
		} else {
			msgVerbose( "git working tree is clean, fine" );
		}
	} else {
		msgWarn( "no git branch found" );
		return false;
	}
	return $res;
}

# -------------------------------------------------------------------------------------------------
# compute the next candidate version
# returning the next rc version

sub computeNextVersion {
    my ( $releasedVersion ) = @_;
	my $nextVersion = undef;

	my @words = split( /\./, $releasedVersion );
	$words[$#words] = $words[$#words]+1;
	$nextVersion = join( '.', @words ).'-rc';

    return $nextVersion;
}

# -------------------------------------------------------------------------------------------------
# publish

sub doPublish {
	# some common tasks before actually publishing to anywhere
	return if !checkGitBranch();
	return if !checkGitClean();
	# remove -rc.* from package.js and get new version
	my $releasedVersion = filePackageRemoveRC();
	return if !$releasedVersion;
	msgOut( "releasing $package->{name} v $releasedVersion" );
	# remove -rc from ChangeLog.md and update release date
	my $releaseDate = dateWithDashes();
	return if !fileChangeLogRemoveRC( $releaseDate );
	# update release date in bottom of README.md, ChangeLog.md, TODO.md
	my $abbrevDate = dateWithCommas();
	return if !fileMDAbbrevDate( $abbrevDate );
	# update required npms in README.md
	return if !fileReadmeUpdateNpms( $releasedVersion );
	# commit Releasing v x.x.x
	return if !gitCommitReleasing( $releasedVersion );
	# checkout master and merge
	return if !gitMerge();
	# publish to Meteor if opted
	if( $opt_meteor ){
		return if !publishMeteor();
	}
	# publish to Github if opted
	if( $opt_github ){
		return if !publishGithub( $releasedVersion );
	}
	my $nextVersion = computeNextVersion( $releasedVersion );
	msgOut( "preparing next $nextVersion release" );
	# back to vnext branch
	return if !gitBackToVNext();
	# bump version in package.js
	return if !filePackageBump( $nextVersion );
	# set new paragraph in ChangeLog.md
	return if !fileChangeLogBump( $nextVersion );
    # commit post-release
	return if !gitCommitPostRelease();
	msgOut( "done" );
}

# -------------------------------------------------------------------------------------------------
# all commands from the functions are described as run from root package directory
# which we force here
# after execution, stderr is printed as errors
# return $stdout or undef if an errors have been printed

sub execLocal {
    my ( $cmd, $opts ) = @_;
	$opts //= {};
	msgVerbose( $cmd );
	# execute the command in a subshell within the package working directory
	my $local_cmd = "(cd $opt_package && $cmd )";
	my $res = TTP::commandExec( $local_cmd, $opts );
	# some commands send some output to stderr even when they are successful
	my $ignoreStderr = false;
	$ignoreStderr = $opts->{ignoreStderr} if defined $opts->{ignoreStderr};
	if( scalar( @{$res->{stderrs}} ) && !$ignoreStderr ){
		msgErr( $res->{stderrs} );
		delete $res->{stdouts};
	}
	return $res->{stdouts};
}

# -------------------------------------------------------------------------------------------------
# add to ChangeLog a paragraph with the next release candidate
# returns true|false

sub fileChangeLogBump {
	my ( $nextVersion ) = @_;
	my @content = path( $package->{'ChangeLog.md'} )->lines_utf8;
	my $found = false;
	my @adds = (
		"",
		"### $nextVersion",
		"",
		"    Release date: ",
		"",
		"    - "
	);
	# lines_utf8() returns non-chomped lines - so need an EOL char suffix
	for( my $i=0 ; $i<=$#adds ; ++$i ){
		$adds[$i] .= EOL;
	}
	for( my $i=0 ; $i<=$#content ; ++$i ){
		my $line = $content[$i];
		# search the start of the file
		if( $line =~ m/^## ChangeLog\s*$/ ){
			splice( @content, $i+1, 0, @adds );
			$found = true;
			last;
		}
	}
	if( $found ){
	    msgVerbose( "$package->{'ChangeLog.md'}: installing next candidate release as '$nextVersion'" );
		if( $ep->runner()->dummy()){
			msgDummy( "writing into $package->{'ChangeLog.md'}" );
		} else {
			path( $package->{'ChangeLog.md'} )->spew_utf8( @content );
		}
	} else {
		msgErr( "$package->{'ChangeLog.md'}: unable to install next candidate release" );
	}
    return $found;
}

# -------------------------------------------------------------------------------------------------
# remove the release candidate flag from ChangeLog.md and install the release date
# returns true|false

sub fileChangeLogRemoveRC {
	my ( $releaseDate ) = @_;
	my $versionFound = false;
	my $dateFound = false;
	my $ok = true;
	my @content = path( $package->{'ChangeLog.md'} )->lines_utf8;
	for( my $i=0 ; $i<=$#content ; ++$i ){
		my $line = $content[$i];
		# should find first the version -rc
		if( $line =~ m/^### \d+\.\d+\.\d+-rc/ ){
			$line =~ s/-rc.*$//;
			$content[$i] = $line;
			$versionFound = true;
			next;
		}
		# should find then the release date
		if( $line =~ m/^\s*Release date\s*:\s*$/ ){
			$line =~ s/(Release date).*$/$1: $releaseDate/;
			$content[$i] = $line;
			$dateFound = true;
			next;
		}
		# stop when we find a version which is not a release candidate
		if( $line =~ m/^### \d+\.\d+\.\d+\s*$/ ){
			last;
		}
	}
	if( $versionFound && $dateFound ){
	    msgVerbose( "$package->{'ChangeLog.md'}: updated release date as '$releaseDate'" );
		if( $ep->runner()->dummy()){
			msgDummy( "writing into $package->{'ChangeLog.md'}" );
		} else {
			path( $package->{'ChangeLog.md'} )->spew_utf8( @content );
		}
	} else {
		msgErr( "$package->{'ChangeLog.md'}: unable to install the release date (versionFound='".( $versionFound ? 'true':'false' )."', dateFound='".( $dateFound ? 'true':'false' )."')" );
		$ok = false;
	}
    return $ok;
}

# -------------------------------------------------------------------------------------------------
# install the last update date into .md files
# returns true|false

sub fileMDAbbrevDate {
	my ( $abbrevDate ) = @_;
	my $ok = true;
	my $mdlist = TTP::Meteor::getPackageMD();
	foreach my $md ( @{$mdlist} ){
		my @content = path( $package->{$md} )->lines_utf8;
		my $found = false;
		for( my $i=$#content ; $i>=0 ; --$i ){
			my $line = $content[$i];
			#print "$i: $line".EOL;
			# should find first the rc version
			if( $line =~ m/^-\s+Last updated on/ ){
				$line = "- Last updated on $abbrevDate";
				$content[$i] = $line;
				$found = true;
				last;
			}
		}
		if( $found ){
			msgVerbose( "$package->{$md}: updating last update date to '$abbrevDate'" );
			if( $ep->runner()->dummy()){
				msgDummy( "writing into $package->{$md}" );
			} else {
				path( $package->{$md} )->spew_utf8( @content );
			}
		} else {
			msgErr( "$package->{$md}: unable to install the last update date" );
			$ok = false;
		}
	}
    return $ok;
}

# -------------------------------------------------------------------------------------------------
# compute the next candidate version and install it in package.js
# returning the next rc version

sub filePackageBump {
    my ( $nextVersion ) = @_;
	my @content = path( $package->{jspck} )->lines_utf8;
	for( my $i=0 ; $i<=$#content ; ++$i ){
		my $line = $content[$i];
		if( $line =~ m/^\s*version\s*:\s*'(\d+\.\d+\.\d+)/ ){
			$line =~ s/^(\s*version)\s*:.*$/$1: '$nextVersion',/;
			$content[$i] = $line;
			last;
		}
	}
	msgVerbose( "$package->{jspck}: updating next version to '$nextVersion'" );
	if( $ep->runner()->dummy()){
		msgDummy( "writing into $package->{jspck}" );
	} else {
		path( $package->{jspck} )->spew_utf8( @content );
	}
    return $nextVersion;
}

# -------------------------------------------------------------------------------------------------
# remove the release candidate flag from package.js
# returning the to-be-released version

sub filePackageRemoveRC {
    my $version;
	my @content = path( $package->{jspck} )->lines_utf8;
	for( my $i=0 ; $i<=$#content ; ++$i ){
		my $line = $content[$i];
		if( $line =~ m/^\s*version\s*:\s*'(\d+\.\d+\.\d+)/ ){
			$version = $1;
			$line =~ s/-rc.*$/',/;
			$content[$i] = $line;
			last;
		}
	}
	if( $version ){
	    msgVerbose( "$package->{jspck}: computed released version as '$version'" );
		if( $ep->runner()->dummy()){
			msgDummy( "writing into $package->{jspck}" );
		} else {
			path( $package->{jspck} )->spew_utf8( @content );
		}
	} else {
		msgErr( "$package->{jspck}: unable to compute the to-be-released version" );
	}
    return $version;
}

# -------------------------------------------------------------------------------------------------
# update the list of required NPMs in the README file
# the listed npms come from the checked ones
# the version set is rounded to the minor x.y.0 (as a change in the list should bump this minor version)
# returns true|false

sub fileReadmeUpdateNpms {
	my ( $releasedVersion ) = @_;
    my $ok = true;
	my $src = File::Spec->catfile( File::Spec->catdir( $opt_package, 'src', 'server', 'js' ), 'check_npms.js' );
	if( -r $src ){
		my @npms = ();
		my @content = path( $src )->lines_utf8;
		my $started  = false;
		my $ended = false;
		foreach my $line ( @content ){
			$line =~ s/\/\/.*$//;	# before all, ignore javascript comments
			if( !$started ){
				if( $line =~ m/^\s*checkNpmVersions\s*\(\s*{/ ){
					$started = true;
				}
			} elsif( !$ended ){
				if( $line =~ m/^\s*}\s*,/ ){
					$ended = true;
				} else {
					push( @npms, $line ) if $line;
				}
			}
		}
		msgVerbose( "got required npms [".join( ',', @npms )."]" );
		# successively find chapter title '## NPM peer dependencies' and then the paragraph title 'Dependencies as of v 1.3.0:'
        #  update the version and replace all that is between following ```
		$releasedVersion =~ s/\.\d+$/.0/;
		@content = path( $package->{'README.md'} )->lines_utf8;
		my $chapter = false;
		my $para = false;
		my $start = -1;
		my $end = -1;
		for ( my $i=0 ; $i<=$#content ; ++$i ){
			my $line = $content[$i];
			if( !$chapter ){
				if( $line =~ m/^\s*## NPM peer dependencies\s*$/ ){
					$chapter = true;
				}
			} else {
				if( $line =~ m/^s*##[^#].*$/ ){
					$chapter = false;	# end of chapter
				} elsif( $line =~ m/^\s*Dependencies as of v/ ){
					$content[$i] = "Dependencies as of v $releasedVersion:".EOL;
					$para = true;
				}
			}
			if( $chapter && $para && ( $start < 0 || $end < 0 )){
				if( $line =~ m/^\s*```/ ){
					if( $start < 0 ){
						$start = $i;
					} else {
						$end = $i;
						last;	# end the loop when we have found the last line to update
					}
				}
			}
		}
		# must have here found the chapter, the paragraph, and the start and the end of the lines to be replaced
		if( $chapter && $para && $start >= 0 && $end >= 0 ){
			splice( @content, $start+1, $end-$start-1, @npms );
			msgVerbose( "$package->{'README.md'}: updating required NPMS with [".join( ',', @npms )."]" );
			if( $ep->runner()->dummy()){
				msgDummy( "writing into $package->{'README.md'}" );
			} else {
				path( $package->{'README.md'} )->spew_utf8( @content );
			}
		} else {
			msgWarn( "$package->{'README.md'}: unable to identify the NPM chapter, para, start or end" );
			$ok = false;
		}
	} else {
		msgVerbose( "$src: skipping NPMs requirements update as no checks are identified" );
	}
    return $ok;
}

# -------------------------------------------------------------------------------------------------
# back to vnext branch and rebase
# NB: git checkout prints to stderr 'Switched to branch 'vnext'', so ignore it here
# returns true|false

sub gitBackToVNext {
	my $stdout = execLocal( "git checkout vnext && git rebase master", { ignoreStderr => true });
	return defined $stdout;
}

# -------------------------------------------------------------------------------------------------
# commit the post-release minimal version bump
# returns true|false

sub gitCommitPostRelease {
	my $stdout = execLocal( "git commit -am 'Post-release minimal version bump'" );
	return defined $stdout;
}

# -------------------------------------------------------------------------------------------------
# commit changed files with a "Releasing" message
# returns true|false

sub gitCommitReleasing {
    my ( $releasedVersion ) = @_;
	my $stdout = execLocal( "git commit -am 'Releasing v $releasedVersion'" );
	return defined $stdout;
}

# -------------------------------------------------------------------------------------------------
# checkout to master branch, and merge vnext
# NB: git checkout prints to stderr 'Switched to branch 'master'', so ignore it here
# returns true|false

sub gitMerge {
	my $stdout = execLocal( "git checkout master && git merge vnext", { ignoreStderr => true });
	return defined $stdout;
}

# -------------------------------------------------------------------------------------------------
# publish to Github
# NB: git checkout prints to stderr 'Switched to branch 'master'', so ignore it here

sub publishGithub {
	my ( $releasedVersion ) = @_;
	msgOut( "publishing to Github..." );
	my $stdout = execLocal( "git tag -am 'Releasing v $releasedVersion' $releasedVersion" );
	return false if !$stdout;
	$stdout = execLocal( "git pull --rebase && git push && git push --tags", { ignoreStderr => true });
	return false if !$stdout;
	return true;
}

# -------------------------------------------------------------------------------------------------
# publish to Meteor
# returns true|false

sub publishMeteor {
	msgOut( "publishing to Meteor..." );
	# show existing versions of the package
	# given that we are executing the command from a local directory, the package has already been published if we get at least two lines
	my $stdout = execLocal( "meteor show $package->{name}" );
	return false if !$stdout;
	my $count = 0;
	my $started = false;
	my $ended = false;
	foreach my $line ( @{$stdout} ){
		if( !$started ){
			$started = true if $line eq 'Recent versions:';
		} elsif( !$ended ){
			if( $line =~ m/^  / ){
				#print "$line".EOL;
				$count += 1;
			} else {
				$ended = true;
				last;
			}
		}
	}
	my $create = $count == 1 ? '--create' : '';
	# publish, maybe creating a new package
	$stdout = execLocal( "meteor publish $create" );
	return false if !$stdout;
	return true;
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"					=> sub { $ep->runner()->help( @_ ); },
	"colored!"				=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"				=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"				=> sub { $ep->runner()->verbose( @_ ); },
	"package=s"				=> \$opt_package,
	"github!"				=> \$opt_github,
	"meteor!"				=> \$opt_meteor,
	"all!"					=> sub {
		my ( $name, $value ) = @_;
		$opt_all = $value;
		$opt_github = $value;
		$opt_meteor = $value;
	} )){

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
msgVerbose( "got package='$opt_package'" );
msgVerbose( "got github='".( $opt_github ? 'true':'false' )."'" );
msgVerbose( "got meteor='".( $opt_meteor ? 'true':'false' )."'" );
msgVerbose( "got all='".( $opt_all ? 'true':'false' )."'" );

# get package absolute path which must exist
$opt_package = path( $opt_package )->realpath;
if( -d $opt_package ){
	$package = TTP::Meteor::getPackage( $opt_package );
	if( $package ){
	} else {
		msgErr( "--package='$opt_package' doesn't address a Meteor package" );
	}
} else {
	msgErr( "--package='$opt_package': directory not found or not available" );
}

# do we have something to do ?
msgWarn( "neither '--github' nor '--meteor' options are specified, will not publish anything" ) if !$opt_github && !$opt_meteor;

if( !TTP::errs()){
	doPublish() if $opt_meteor || $opt_github;
}

TTP::exit();
