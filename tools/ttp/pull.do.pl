# @(#) pull code and configurations from a reference machine
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --fromhost=<name>       pull from this host [${fromhost}]
# @(-) --options=<options>     additional options to be passed to the command [${options}]
#
# @(@) When pulling from the default host, you should take care of specifying at least one of '--nohelp' or '--noverbose' (or '--verbose').
# @(@) Also be warned that this script deletes the destination before installing the refreshed version, and will not be able of that if
# @(@) a user is inside of the tree (either through a file explorer or a command prompt).
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

use Config;
use File::Copy::Recursive qw( dircopy );
use File::Spec;

use TTP::Node;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	fromhost => $ep->var([ 'deployments', 'reference' ]) || '',
	options => ''
};

my $opt_fromhost = $defaults->{fromhost};
my $opt_options = $defaults->{options};
my $fromNode = undef;

# -------------------------------------------------------------------------------------------------
# pull the reference tree from the specified machine
# doesn't try to exclude anything: we pull what has been pushed

sub doPull {
	my $result = false;
	msgOut( "pulling from '$opt_fromhost'..." );
	my $asked = 0;
	my $done = 0;
	# have pull share
	my $fromData = $fromNode->jsonData();
	my $pullShare = undef;
	$pullShare = $fromData->{remoteShare} if defined $fromData->{remoteShare};
	if( $pullShare ){
		my ( $pull_vol, $pull_dirs, $pull_file ) = File::Spec->splitpath( $pullShare );
		my $command = 'ttp.pl copydirs --sourcepath <SOURCE> --targetpath <TARGET> <OPTIONS>';
		# may have several source dirs: will iterate on each
		my $trees = $ep->var([ 'deployments', 'trees' ]);
		foreach my $tree ( @{$trees} ){
			my $res = doPull_byTree( $pull_vol, $tree, $command );
			$asked += $res->{asked};
			$done += $res->{done};
		}
	} else {
		msgErr( "remoteShare is not specified in '$opt_fromhost' host configuration" );
	}
	my $str = "$done/$asked copied subdir(s)";
	if( $done == $asked && !TTP::errs()){
		msgOut( "success ($str)" );
	} else {
		msgErr( "NOT OK ($str)" );
	}
}

# pull a directory from the reference
# returns an object { asked, done }

sub doPull_byTree {
	my ( $pullVol, $tree, $command ) = @_;
	my $result = {
		asked => 0,
		done => 0
	};
	my ( $dir_vol, $dir_dirs, $dir_file ) = File::Spec->splitpath( $tree->{target} );
	my $srcPath = File::Spec->catpath( $pullVol, $dir_dirs, $dir_file );
	$result->{asked} += 1;
	msgOut( "pulling from source='$srcPath' into target='$tree->{target}'" );
	my $cmdres = TTP::commandExec( $command, {
		macros => {
			SOURCE => $srcPath,
			TARGET => $tree->{target},
			OPTIONS => $opt_options
		}
	});
	$result->{done} += 1 if $cmdres->{success};
	return $result;
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> sub { $ep->runner()->help( @_ ); },
	"colored!"			=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"			=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"			=> sub { $ep->runner()->verbose( @_ ); },
	"fromhost=s"		=> \$opt_fromhost,
	"options=s"			=> \$opt_options )){

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
msgVerbose( "got fromhost='$opt_fromhost'" );
msgVerbose( "got options='$opt_options'" );

# a pull host must be defined in command-line and have a json configuration file
# must not be the reference host
if( $opt_fromhost ){
	my $host = $ep->node()->name();
	if( $opt_fromhost eq $host ){
		msgErr( "cowardly refuse to pull from this same host ($host)" );
	} else {
		$fromNode = TTP::Node->new( $ep, { node => $opt_fromhost });
		msgErr( "unable to get the '$opt_fromhost' node configuration" ) if !$fromNode;
	}
} else {
	msgErr( "'--fromhost' value is required, but not specified" );
}

if( !TTP::errs()){
	doPull();
}

TTP::exit();
