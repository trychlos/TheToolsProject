# @(#) manage scheduled tasks
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]list              list the scheduled tasks [${list}]
# @(-) --task=<name>           acts on the named task [${task}]
# @(-) --[no]status            display the status of the named task [${status}]
# @(-) --[no]enabled           whether the named task is enabled [${enabled}]
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
	list => 'no',
	task => '',
	status => 'no',
	enabled => 'no'
};

my $opt_list = false;
my $opt_task = $defaults->{task};
my $opt_status = false;
my $opt_enabled = false;

# -------------------------------------------------------------------------------------------------
# list the scheduled tasks (once for each)

sub doListTasks {
	if( $opt_task ){
		msgOut( "listing tasks filtered on '$opt_task' name..." );
	} else {
		msgOut( "listing all tasks..." );
	}
	my $count = 0;
	my $res = TTP::commandExec( "schtasks /Query /fo list" );
	my @tasks = grep( /TaskName:/, @{$res->{stdouts}} );
	if( $opt_task ){
		@tasks = grep( /$opt_task/i, @tasks );
	}
	my $uniqs = {};
	foreach my $it ( @tasks ){
		my @words = split( /\s+/, $it );
		if( !defined( $uniqs->{$words[1]} )){
			$count += 1;
			$uniqs->{$words[1]} = true;
			print "  $words[1]".EOL;
		}
	}
	if( $res->{success} ){
		msgOut( "found $count tasks" );
	} else {
		msgErr( "NOT OK" );
	}
}

# -------------------------------------------------------------------------------------------------
# display the status of a task

sub doTaskStatus {
	msgOut( "displaying the '$opt_task' task status..." );
	my $res = TTP::commandExec( "schtasks /Query /fo table /TN $opt_task" );
	my @words = split( /\\/, $opt_task );
	my $name = $words[scalar( @words )-1];
	my @props = grep( /$name/, @{$res->{stdouts}} );
	if( $props[0] ){
		@words = split( /\s+/, $props[0] );
		print "  $name: $words[scalar(@words)-1]".EOL;
	}
	if( $res->{success} ){
		msgOut( "success" );
	} else {
		msgErr( "NOT OK" );
	}
}

# -------------------------------------------------------------------------------------------------
# returns 0 if the named task is enabled

sub doTaskEnabled {
	msgOut( "check the 'enabled' property of the '$opt_task' task..." );
	my $res = TTP::commandExec( "schtasks /Query /fo table /TN $opt_task" );
	if( $res->{success} ){
		my @words = split( /\\/, $opt_task );
		my $name = $words[scalar( @words )-1];
		my @props = grep( /$name/, @{$res->{stdouts}} );
		if( $props[0] ){
			@words = split( /\s+/, $props[0] );
			my @ready = grep( /Ready/, @words );
			$res->{success} = scalar( @ready ) > 0;
		}
	}
	if( !$res->{success} ){
		$ep->runner()->runnableErrInc();
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> sub { $ep->runner()->help( @_ ); },
	"colored!"			=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"			=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"			=> sub { $ep->runner()->verbose( @_ ); },
	"list!"				=> \$opt_list,
	"task=s"			=> \$opt_task,
	"status!"			=> \$opt_status,
	"enabled!"			=> \$opt_enabled )){

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
msgVerbose( "got list='".( $opt_list ? 'true':'false' )."'" );
msgVerbose( "got task='$opt_task'" );
msgVerbose( "got status='".( $opt_status ? 'true':'false' )."'" );
msgVerbose( "got enabled='".( $opt_enabled ? 'true':'false' )."'" );

# a task name is mandatory when asking for the status
msgErr( "a task name is mandatory when asking for a status" ) if ( $opt_status or $opt_enabled ) and !$opt_task;

if( !TTP::errs()){
	doListTasks() if $opt_list;
	doTaskStatus() if $opt_status && $opt_task;
	doTaskEnabled() if $opt_enabled && $opt_task;
}

TTP::exit();
