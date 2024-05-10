# @(#) manage scheduled tasks
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]list              list the scheduled tasks [${list}]
# @(-) --task=<name>           acts on the named task [${task}]
# @(-) --[no]status            display the status of the named task [${status}]
#
# The Tools Project: a Tools System and Paradigm for IT Production
# Copyright (©) 1998-2023 Pierre Wieser (see AUTHORS)
# Copyright (©) 2023-2024 PWI Consulting
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

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	list => 'no',
	task => '',
	status => 'no'
};

my $opt_list = false;
my $opt_task = $defaults->{task};
my $opt_status = false;

# -------------------------------------------------------------------------------------------------
# list the scheduled tasks (once for each)

sub doListTasks {
	if( $opt_task ){
		msgOut( "listing tasks filtered on '$opt_task' name..." );
	} else {
		msgOut( "listing all tasks..." );
	}
	my $count = 0;
	my $stdout = `schtasks /Query /fo list`;
	my $res = $? == 0;
	my @lines = split( /[\r\n]/, $stdout );
	my @tasks = grep( /TaskName:/, @lines );
	if( $opt_task ){
		@tasks = grep( /$opt_task/i, @tasks );
	}
	my $uniqs = {};
	foreach my $it ( @tasks ){
		my @words = split( /\s+/, $it );
		if( !exists( $uniqs->{$words[1]} )){
			$count += 1;
			$uniqs->{$words[1]} = true;
			print "  $words[1]".EOL;
		}
	}
	if( $res ){
		msgOut( "found $count tasks" );
	} else {
		msgErr( "NOT OK" );
	}
}

# -------------------------------------------------------------------------------------------------
# display the status of a task

sub doTaskStatus {
	msgOut( "displaying the '$opt_task' task status..." );
	my $stdout = `schtasks /Query /fo table /TN $opt_task`;
	my $res = $? == 0;
	my @words = split( /\\/, $opt_task );
	my $name = $words[scalar( @words )-1];
	my @lines = split( /[\r\n]/, $stdout );
	my @props = grep( /$name/, @lines );
	@words = split( /\s+/, $props[0] );
	print "  $name: $words[2]".EOL;
	if( $res ){
		msgOut( "success" );
	} else {
		msgErr( "NOT OK" );
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
	"list!"				=> \$opt_list,
	"task=s"			=> \$opt_task,
	"status!"			=> \$opt_status	)){

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
msgVerbose( "found list='".( $opt_list ? 'true':'false' )."'" );
msgVerbose( "found task='$opt_task'" );
msgVerbose( "found status='".( $opt_status ? 'true':'false' )."'" );

# a task name is mandatory when asking for the status
msgErr( "a task name is mandatory when asking for a status" ) if $opt_status && !$opt_task;

if( !TTP::errs()){
	doListTasks() if $opt_list;
	doTaskStatus() if $opt_status && $opt_task;
}

TTP::exit();
