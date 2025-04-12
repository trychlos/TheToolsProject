# @(#) list various TTP objects
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]commands          list the available commands [${commands}]
# @(-) --[no]nodes             list the known (defined) nodes [${nodes}]
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

use TTP::Command;
use TTP::Node;
use TTP::Service;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	commands => 'no',
	nodes => 'no'
};

my $opt_commands = false;
my $opt_nodes = false;

# -------------------------------------------------------------------------------------------------
# list the available commands

sub listCommands {
	msgOut( "displaying available commands..." );
	my $count = 0;
	# list all commands in all TTP_ROOTS trees
	my $finder = TTP::Command->finder();
	my $findable = {
		dirs => [ $finder->{dirs} ],
		glob => '*'.$finder->{sufix}
	};
	my $commands = $ep->runner()->find( $findable );
	# get only unique commands
	my $uniqs = {};
	foreach my $it ( @{$commands} ){
		my ( $vol, $dirs, $file ) = File::Spec->splitpath( $it );
		$uniqs->{$file} = $it if !exists( $uniqs->{$file} );
	}
	# and display them in ascii order
	foreach my $it ( sort keys %{$uniqs} ){
		TTP::Command->helpOneline( $uniqs->{$it}, { prefix => ' ' });
		$count += 1;
	}
	msgOut( "$count found command(s)" );
}

# -------------------------------------------------------------------------------------------------
# list the available (defined) nodes

sub listNodes {
	msgOut( "displaying available nodes..." );
	my $count = 0;
	# list all nodes in all TTP_ROOTS trees
	my $findable = {
		dirs => [ TTP::Node->dirs() ],
		glob => '*'.TTP::Node->finder()->{sufix}
	};
	my $nodes = $ep->runner()->find( $findable );
	# get only unique available nodes
	my $uniqs = {};
	foreach my $it ( @{$nodes} ){
		my ( $vol, $dirs, $file ) = File::Spec->splitpath( $it );
		my $name = $file;
		$name =~ s/\.[^\.]+$//;
		my $node = TTP::Node->new( $ep, { node => $name, abortOnError => false });
		$uniqs->{$name} = $it if $node && !exists( $uniqs->{$name} );
	}
	# and display them in ascii order
	foreach my $it ( sort keys %{$uniqs} ){
		print " $it".EOL;
		$count += 1;
	}
	msgOut( "$count found node(s)" );
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> sub { $ep->runner()->help( @_ ); },
	"colored!"			=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"			=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"			=> sub { $ep->runner()->verbose( @_ ); },
	"commands!"			=> \$opt_commands,
	"nodes!"			=> \$opt_nodes )){

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
msgVerbose( "got commands='".( $opt_commands ? 'true':'false' )."'" );
msgVerbose( "got nodes='".( $opt_nodes ? 'true':'false' )."'" );

if( !TTP::errs()){
	listCommands() if $opt_commands;
	listNodes() if $opt_nodes;
}

TTP::exit();
