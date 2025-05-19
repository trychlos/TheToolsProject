# @(#) display TTP version
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]greatest          display the greatest inline version [${greatest}]
# @(-) --[no]all               display all inline versions [${all}]
# @(-) --target=<name>         target node [${target}]
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

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	greatest => 'no',
	all => 'no',
	target => ''
};

my $opt_greatest = false;
my $opt_all = false;
my $opt_target = $defaults->{target};

# -------------------------------------------------------------------------------------------------
# Display all inline versions

sub listAll {
	my $str = "all: [ ".( join( ', ', @{TTP::versions()} ))." ]";
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# Display greatest inline version

sub listGreatest {
	my $str = "greatest: ".TTP::version();
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> sub { $ep->runner()->help( @_ ); },
	"colored!"			=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"			=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"			=> sub { $ep->runner()->verbose( @_ ); },
	"greatest!"			=> \$opt_greatest,
	"all!"				=> \$opt_all,
	"target=s"			=> \$opt_target )){

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
msgVerbose( "got greatest='".( $opt_greatest ? 'true':'false' )."'" );
msgVerbose( "got all='".( $opt_all ? 'true':'false' )."'" );
msgVerbose( "got target='$opt_target'" );

# if a target is specified, then exec remote
if( $opt_target ){
	TTP::execRemote( $opt_target );
	TTP::exit();
}

# warn if no option has been requested
msgWarn( "neither '--greatest' nor '--all' options have been provided, nothing to do" ) if !$opt_greatest && !$opt_all;

if( !TTP::errs()){
	listGreatest() if $opt_greatest;
	listAll() if $opt_all;
}

TTP::exit();
