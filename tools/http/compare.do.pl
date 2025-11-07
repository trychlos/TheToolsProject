# @(#) deep compare between two HTTP/HTTPS endpoints
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --json=<filename>       the JSON configuration file [${jsonfile}]
# @(-) --[no]debug             whether the Selenium::Remote::Driver must be run in debug mode [${debug}]
# @(-) --maxvisited=<count>    maximum count of places to be visited, overriding configured value [${maxvisited}]
# @(-) --[no]click             whether by click crawl mode is requested, overriding configured value [${click}]
# @(-) --[no]link              whether by link crawl mode is requested, overriding configured value [${link}]
# @(-) --logsdir=<dir>         logs root directory of this TTP verb [${logsdir}]
# @(-) --workdir=<dir>         chromedriver working directory [${workdir}]
#
# @(@) Note 1: This verb requires a chromedriver server running locally. It is automatically started as long as it is available.
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

use Data::Dumper;
use File::Path qw( make_path );
use File::Spec;
use Test::More;

use TTP::HTTP::Compare::Config;
use TTP::HTTP::Compare::Role;
use TTP::HTTP::Compare::WebDriver;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	debug => 'no',
	jsonfile => '',
	maxvisited => TTP::HTTP::Compare::Config::DEFAULT_CRAWL_MAX_VISITED,
	click => TTP::HTTP::Compare::Config::DEFAULT_CRAWL_BY_CLICK_ENABLED ? 'yes' : 'no',
	link => TTP::HTTP::Compare::Config::DEFAULT_CRAWL_BY_LINK_ENABLED ? 'yes' : 'no',
	logsdir => File::Spec->catdir( TTP::Path::logsCommands(), $ep->runner->runnableBNameShort()."-".$ep->runner()->verb()),
	workdir => TTP::tempDir()
};

my $opt_debug = false;
my $opt_jsonfile = $defaults->{jsonfile};
my $opt_maxvisited = $defaults->{maxvisited};
my $opt_click = TTP::HTTP::Compare::Config::DEFAULT_CRAWL_BY_CLICK_ENABLED;
my $opt_link = TTP::HTTP::Compare::Config::DEFAULT_CRAWL_BY_LINK_ENABLED;
my $opt_logsdir = $defaults->{logsdir};
my $opt_workdir = $defaults->{workdir};

# the JSON compare configuration as a TTP::HTTP::Compare::Config object
my $conf = undef;

# the root directory of all the log files
my $rundir = undef;

# a global hashref which handles the results of the compare
my $hashref = {};

# the webdriver
my $driver = undef;

# whether we have set options
my $opt_maxvisited_set = false;
my $opt_click_set = false;
my $opt_link_set = false;
my $opt_workdir_set = false;

# some constants
my $Const = {
};

# -------------------------------------------------------------------------------------------------
# Compare two websites

sub doCompare {
	msgOut( "comparing '".$conf->confBasesNew()."' against ref '".$conf->confBasesRef()."' URLs..." );
	$hashref->{run} //= {};
	# iter on roles
	$hashref->{byRole} //= {};
	foreach my $role ( $conf->roles()){
		doCompareByRole( $role );
	}
	#print "hashref: ".Dumper( $hashref );
	done_testing();
	print_results_summary();
}

# -------------------------------------------------------------------------------------------------
# Compare two websites for the given role
# (I):
# - the name of the role to be run

sub doCompareByRole {
	my ( $role ) = @_;

	# instanciates a new role object
	my $roleObj = TTP::HTTP::Compare::Role->new( $ep, $role, $conf );
	if( !$roleObj->isDefined()){
		msgErr( "role='$role' is not defined, skipping" );
		return;
	}
	# make sure the role is enabled
	my $enabled = $roleObj->isEnabled();
	if( !$enabled ){
		msgVerbose( "role='$role' is disabled by configuration, skipping" );
		return;
	}
	# ask the role to do the actual comparison
	msgOut( "comparing for role '$role'..." );
	$hashref->{byRole}{$role} = $roleObj;
	my $result = $roleObj->doCompare( $rundir, { debug => $opt_debug });
	#print STDERR "result: ".Dumper( $result );
	# cleanup the object and all its dependencies *before* DESTRUCT phase
	$roleObj->destroy();
}

# -------------------------------------------------------------------------------------------------
# at end, print a results summary

sub print_results_summary {
	#print STDERR "byRole: ".Dumper( $hashref->{byRole} );
	#print STDERR "keys: ".Dumper( keys %{$hashref->{byRole}} );
	if( scalar( keys %{$hashref->{byRole}} )){
		msgOut( "results summary by role:" );
		foreach my $role ( sort keys %{$hashref->{byRole}} ){
			msgOut( "- $role:" );
			$hashref->{byRole}{$role}->print_results_summary();
		}
	}
	msgOut( "logs root directory: '$rundir'" );
	msgOut( "done" );
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> sub { $ep->runner()->help( @_ ); },
	"colored!"			=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"			=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"			=> sub { $ep->runner()->verbose( @_ ); },
	"debug!"			=> \$opt_debug,
	"jsonfile=s"		=> \$opt_jsonfile,
	"maxvisited=i"		=> sub {
		my ( $name, $value ) = @_;
		$opt_maxvisited = $value;
		$opt_maxvisited_set = true;
	},
	"click!"			=> sub {
		my ( $name, $value ) = @_;
		$opt_click = $value;
		$opt_click_set = true;
	},
	"link!"				=> sub {
		my ( $name, $value ) = @_;
		$opt_link = $value;
		$opt_link_set = true;
	},
	"logsdir=s"			=> \$opt_logsdir,
	"workdir=s"			=> sub {
		my ( $name, $value ) = @_;
		$opt_workdir = $value;
		$opt_workdir_set = true;
	})){
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
msgVerbose( "got debug='".( $opt_debug ? 'true':'false' )."'" );
msgVerbose( "got jsonfile='$opt_jsonfile'" );
msgVerbose( "got maxvisited='$opt_maxvisited'" );
msgVerbose( "got click=".( $opt_click ? 'true':'false' )."'" );
msgVerbose( "got link=".( $opt_link ? 'true':'false' )."'" );
msgVerbose( "got logsdir='$opt_logsdir'" );
msgVerbose( "got workdir='$opt_workdir'" );

# if a maxvisited is provided, must be greater or equal to zero
if( $opt_maxvisited_set ){
	msgErr( "'--maxvisited' must be greater or equal to zero, got $opt_maxvisited" ) if $opt_maxvisited < 0;
}

# JSON configuration file is mandatory
if( $opt_jsonfile ){
	my $args = {};
	$args->{max_visited} = $opt_maxvisited if $opt_maxvisited_set && !TTP::errs();
	$args->{by_click} = $opt_click if $opt_click_set;
	$args->{by_link} = $opt_link if $opt_link_set;
	$args->{browser_workdir} = $opt_workdir if $opt_workdir_set;
	$conf = TTP::HTTP::Compare::Config->new( $ep, $opt_jsonfile, $args );
	if( !$conf->jsonLoaded()){
		msgErr( "JSON not loaded" );
	}
} else {
	msgErr( "'--jsonfile' is required, but is not specified" );
}

if( !TTP::errs()){
	$rundir = File::Spec->catdir( $opt_logsdir, Time::Moment->now->strftime( '%y%m%d-%H%M%S' ));
	make_path( $rundir );
	msgVerbose( "rundir='$rundir'" );
}

if( !TTP::errs()){
	#$driver = TTP::HTTP::Compare::WebDriver->new( $ep, $conf, $rundir );
}

if( !TTP::errs()){
	doCompare();
}

TTP::exit();
