# @(#) setup the execution node environment
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]default           whether to setup the first available node [${default}]
# @(-) --node=<name>           the node to be set as current [${node}]
#
# @(@) This command is needed because TheToolsProject supports the 'logical machine' paradigm.
# @(@) It has the unique particularity of having to be executed 'in-process', i.e. with the dot notation: ". ttp.sh switch --node <name>".
# @(@) It is most often run from profile initialization as ". ttp.sh switch --default".
#
# The Tools Project: a Tools System and Paradigm for IT Production
# Copyright (©) 2003-2021 Pierre Wieser (see AUTHORS)
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
#
# Synopsis:
#
#   When the user logs in, the first available execution node is setup.
#   This verb let the user select another node in the same host.
#
# NB:
#   This verb is executed from sh/switch which expects the node to be printed on stdout.
#
# pwi 1998-10-21 new production architecture definition - creation
# pwi 1999- 2-17 set LD_LIBRARY_PATH is GEDAA is set
# pwi 2001-10-17 remove GEDTOOL variable
# pwi 2002- 2-28 tools are moved to physical box
# pwi 2002- 6-24 consider site.ini configuration file
# gma 2004- 4-30 use bspNodeEnum function
# fsl 2005- 3-11 fix bug when determining if a logical exists
# pwi 2006-10-27 the tools become The Tools Project, released under GPL
# pwi 2017- 6-21 publish the release at last
# pwi 2025- 2- 7 merge shell-based and Perl-based flavors to make TheToolsProject available both on shell-based and cmd-based OSes
# pwi 2025- 4- 3 starting with v4, VERBOSE environment variable is replaced with TTP_DEBUG
#                even if named 'switch.do.ksh', this script is ran from within a perl runtime environment embedded into a shell execution
#                this is so actually a *perl* code

use TTP::Constants qw( :all );
use TTP::Message qw( :all );
use TTP::Node;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	default => 'no',
	node => ''
};

my $opt_default = false;
my $opt_node = '';

# -------------------------------------------------------------------------------------------------
# receive here all found files in the searched directories
# According to https://perldoc.perl.org/File::Find
#   $File::Find::dir is the current directory name,
#   $_ is the current filename within that directory
#   $File::Find::name is the complete pathname to the file.

sub doFindNode {
	if( $opt_default ){
		$opt_node = TTP::Node->findCandidate();
		if( !$opt_node ){
			msgErr( "unable to find an available execution node on this host" );
		}
	} else {
		my $nodes = TTP::Node->enum();
		if( !grep( /$opt_node/, @{$nodes} )){
			msgErr( "'${opt_node}': execution node not found or not available on this host" );
			$opt_node = undef;
		}
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
	"default!"			=> \$opt_default,
	"node=s"			=> \$opt_node )){

		msgOut( "try '".$running->command()." ".$running->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $running->help()){
	$running->verbHelp( $defaults );
	TTP::exit();
}

msgVerbose( "found colored='".( $running->colored() ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $running->dummy() ? 'true':'false' )."'" );
msgVerbose( "found verbose='".( $running->verbose() ? 'true':'false' )."'" );
msgVerbose( "found default='".( $opt_default ? 'true':'false' )."'" );
msgVerbose( "found node='$opt_node'" );

# must have one of --default or --node
if( !$opt_default && !$opt_node ){
	msgErr( "one of '--default' and '--node=<node>' options must be specified" );
}
if( $opt_default && $opt_node ){
	msgErr( "only one of '--default' and '--node=<node>' options must be specified" );
}

if( !TTP::errs()){
	doFindNode();
}
if( !TTP::errs()){
	print "success: ${opt_node}".EOL;
}

TTP::exit();
