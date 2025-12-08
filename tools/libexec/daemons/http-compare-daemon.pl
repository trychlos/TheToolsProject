#!/usr/bin/perl
# @(#) Manage accesses to a website for the sake of 'http.pl compare' verb.
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --json=<filename>       the name of the JSON configuration file [${json}]
# @(-) --[no]ignoreInt         ignore the (Ctrl+C) INT signal [${ignoreInt}]
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
#
# This script is mostly written like a TTP verb but is not.
# This is an example of how to take advantage of TTP to write your own (rather pretty and efficient) daemon.
#
# For each instance of this daemon, we have a chromedriver browser connection and the corresponding log-in data.

use utf8;
use strict;
use warnings;

use Data::Dumper;
use File::Spec;
use Getopt::Long;
use JSON;
use MIME::Base64 qw( decode_base64 );
use Path::Tiny qw( path );
use Time::Moment;

use TTP;
use vars::global qw( $ep );

use TTP::Constants qw( :all );
use TTP::HTTP::Compare::Browser;
use TTP::HTTP::Compare::Facer;
use TTP::HTTP::Compare::Login;
use TTP::HTTP::Compare::QueueItem;
use TTP::JSONable;
use TTP::Message qw( :all );
use TTP::RunnerDaemon;

my $daemon = TTP::RunnerDaemon->bootstrap();

# have our own datas
$daemon->{this} = {};
$daemon->{this}{stats} = {};

use constant {
};

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	json => '',
	ignoreInt => 'no'
};

my $opt_json = $defaults->{json};
my $opt_ignoreInt = false;

# the commands this daemon answers to
$daemon->{this}{commands} = {
	click_and_capture => \&answerClickAndCapture,
	clickable_discover_targets_xpath => \&answerClickableDiscoverTargetsXpath,
	handle_form => \&answerHandleForm,
	internal_status => \&answerInternalStatus,
	navigate_and_capture => \&answerNavigateAndCapture,
	signature => \&answerSignature,
	stats => \&answerStats,
	status => \&answerStatus,
};

# some constants
my $Const = {
};

# the Facer object which handles the current run comparison data
# instanciated in getCompareConfig() function which must be the first one run
my $facer = undef;

# -------------------------------------------------------------------------------------------------
# (I):
# - a serialized queue item
# - an arguments hash

sub answerClickAndCapture {
	my ( $self, $req ) = @_;
	# start
	my $start = Time::Moment->now;
	# execute
	my $snap = decode_base64( decode_json( $req->{args}->[0] )->{queue_item} );
	my $args = decode_json( $req->{args}->[0] )->{args};
	my $ret = $daemon->{this}{browser}->click_and_capture( TTP::HTTP::Compare::QueueItem->new_by_snapshot( $ep, $snap ), $args );
	msgLog( "received answer='$ret'" );
	my $answer = encode_json({ answer => $ret });
	$req->{logAnswer} = false if $ret && !ref( $ret );
	# get stats
	$daemon->{this}{stats}{click_and_capture} //= [];
	push( @{$daemon->{this}{stats}{click_and_capture}}, { start => $start, end => Time::Moment->now, answer => $answer });
	# return
	return $answer;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing

sub answerClickableDiscoverTargetsXpath {
	my ( $self, $req ) = @_;
	# start
	my $start = Time::Moment->now;
	# execute
	my $answer = encode_json({ answer => $daemon->{this}{browser}->clickable_discover_targets_xpath() });
	$req->{logAnswer} = false;
	# get stats
	$daemon->{this}{stats}{clickable_discover_targets_xpath} //= [];
	push( @{$daemon->{this}{stats}{clickable_discover_targets_xpath}}, { start => $start, end => Time::Moment->now, answer => $answer });
	# return
	return $answer;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - selector
# - description

sub answerHandleForm {
	my ( $self, $req ) = @_;
	# start
	my $start = Time::Moment->now;
	# execute
	my $selector = decode_json( $req->{args}->[0] )->{selector};
	my $description = decode_json( $req->{args}->[0] )->{description};
	my $answer = encode_json({ answer => $daemon->{this}{browser}->handle_form( $selector, $description ) });
	#$req->{logAnswer} = false;
	# get stats
	$daemon->{this}{stats}{clickable_discover_targets_xpath} //= [];
	push( @{$daemon->{this}{stats}{clickable_discover_targets_xpath}}, { start => $start, end => Time::Moment->now, answer => $answer });
	# return
	return $answer;
}

# -------------------------------------------------------------------------------------------------
# "internal_status" command is used by the daemon interface to wait for ready

sub answerInternalStatus {
	my ( $self, $req ) = @_;
	my $answer = "";
	return $answer;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - the RunnerDaemon object
# - the request as a hash:
#   > command: the first word
#   > args: an array ref to other provided arguments
# Here, Browser::navigate_and_capture() expects a single argument as 'path'

sub answerNavigateAndCapture {
	my ( $self, $req ) = @_;
	# start
	my $start = Time::Moment->now;
	# execute
	my $path = decode_json( $req->{args}->[0] )->{path};
	my $answer = encode_json({ answer => $daemon->{this}{browser}->navigate_and_capture( $path ) });
	$req->{logAnswer} = false;
	# get stats
	$daemon->{this}{stats}{navigate_and_capture} //= [];
	push( @{$daemon->{this}{stats}{navigate_and_capture}}, { start => $start, end => Time::Moment->now, answer => $answer });
	# return
	return $answer;
}

# -------------------------------------------------------------------------------------------------
# no expected arg

sub answerSignature {
	my ( $self, $req ) = @_;
	# start
	my $start = Time::Moment->now;
	# execute
	my $answer = encode_json({ answer => $daemon->{this}{browser}->signature() });
	# get stats
	$daemon->{this}{stats}{signature} //= [];
	push( @{$daemon->{this}{stats}{signature}}, { start => $start, end => Time::Moment->now, answer => $answer });
	# return
	return $answer;
}

# -------------------------------------------------------------------------------------------------
sub answerStats {
	my ( $self, $req ) = @_;
	my $answer = "";
	foreach my $key ( sort keys %{$daemon->{this}{stats}} ){
	}
	return $answer;
}

# -------------------------------------------------------------------------------------------------
# add to the standard 'status' answer our own data

sub answerStatus {
	my ( $self, $req ) = @_;
	my $answer = TTP::RunnerDaemon->commonCommands()->{status}( $self, $req, $daemon->{this}{commands} );
	$answer .= "role: ".$facer->roleName().EOL;
	$answer .= "which: ".$facer->which().EOL;
	return $answer;
}

# -------------------------------------------------------------------------------------------------
# loads the serialized TTP::HTTP::Compare::Config and setup a new object instance
# instanciates a Facer instance which will handle this configuration

sub getCompareConfig {
	my $config = $daemon->config()->jsonData();
	my $role = $config->{compare}{roleName};
	my $which = $config->{compare}{which};
	my $bin = $config->{compare}{binConf};
	msgVerbose( "by '$role:$which' getCompareConfig() found binConf='$bin'" );
	open my $fh, '<:raw', $bin or msgErr( "$bin: $!" );
	local $/;
	my $blob = <$fh>;
	close $fh;
	my $conf = TTP::HTTP::Compare::Config->new_by_snapshot( $ep, $blob );
	$facer = TTP::HTTP::Compare::Facer->new( $ep, $conf, $daemon );
	msgVerbose( "by '$role:$which' getCompareConfig() built facer=$facer" );
}

# -------------------------------------------------------------------------------------------------
# log-in into the site if configured for

sub logIn {
	my $role = $facer->roleName();
	my $which = $facer->which();
	# do we must log-in the sites ?
	# yes if we have both a login, a password and a login object which provides the needed selectors
	my $loginObj = TTP::HTTP::Compare::Login->new( $ep, $facer );
	if( !TTP::errs() && $loginObj->isDefined() && wants_login()){
		my $login = $loginObj->logIn( $daemon->{this}{browser}, username(), password());
		if( $login ){
			$daemon->{this}{login} = $login;
			msgVerbose( "by '$role:$which' logIn() login successful" );
		} else {
			msgErr( "by '$role:$which' logIn() unable to login/authenticate on the site" );
		}
	}
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - the password of account

sub password {

	my $hash = $facer->conf()->var([ 'roles', $facer->roleName() ]);
	$hash->{credentials} //= {};

	return $hash->{credentials}{password};
}

# -------------------------------------------------------------------------------------------------
# instanciates the chromedriver browser and connect

sub startBrowser {
	my $role = $facer->roleName();
	my $which = $facer->which();
	my $browser = TTP::HTTP::Compare::Browser->new( $ep, $facer );
	if( $browser->isAlive()){
		$daemon->{this}{browser} = $browser;
		msgVerbose( "by '$role:$which' startBrowser() successful" );
	} else {
		msgErr( "by '$role:$which' startBrowser() unable to instanciate a browser driver" );
	}
}

# -------------------------------------------------------------------------------------------------
# (I):
# - nothing
# (O):
# - the name of account

sub username {
	my ( $self ) = @_;

	my $hash = $facer->conf()->var([ 'roles', $facer->roleName() ]);
	$hash->{credentials} //= {};

	return $hash->{credentials}{username};
}

# -------------------------------------------------------------------------------------------------
# Determines if this role can log-in to the sites.
# True if we have both a login and a password.
# (I):
# - nothing
# (O):
# - whether the role must log-in

sub wants_login {
	my $can = false;

	my $role = $facer->roleName();
	my $which = $facer->which();

	if( username()){
		if( password()){
			$can = true;
		} else {
			msgVerbose( "by '$role:$which' wants_login() password is not set" );
		}
	} else {
		msgVerbose( "by '$role:$which' wants_login() username is not set")
	}

	return $can;
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> sub { $ep->runner()->help( @_ ); },
	"colored!"			=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"			=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"			=> sub { $ep->runner()->verbose( @_ ); },
	"json=s"			=> \$opt_json,
	"ignoreInt!"		=> \$opt_ignoreInt )){

		msgOut( "try '".$daemon->command()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $daemon->help()){
	$daemon->displayHelp( $defaults );
	TTP::exit();
}

msgVerbose( "got colored='".( $daemon->colored() ? 'true':'false' )."'" );
msgVerbose( "got dummy='".( $daemon->dummy() ? 'true':'false' )."'" );
msgVerbose( "got verbose='".( $daemon->verbose() ? 'true':'false' )."'" );
msgVerbose( "got json='$opt_json'" );
msgVerbose( "got ignoreInt='".( $opt_ignoreInt ? 'true':'false' )."'" );

msgErr( "'--json' option is mandatory, not specified" ) if !$opt_json;

if( !TTP::errs()){
	$daemon->run({ jsonPath => $opt_json, ignoreInt => $opt_ignoreInt });
}

if( TTP::errs()){
	TTP::exit();
}

# we instanciate here the Facer object - this must be the first action
getCompareConfig();
if( TTP::errs()){
	$daemon->terminate();
	TTP::exit();
}

startBrowser();
if( TTP::errs()){
	$daemon->terminate();
	TTP::exit();
}

logIn();
if( TTP::errs()){
	$daemon->terminate();
	TTP::exit();
}

$daemon->declareSleepables( $daemon->{this}{commands} );
$daemon->sleepableStart();

$daemon->terminate();
