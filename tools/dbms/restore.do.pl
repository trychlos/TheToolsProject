# @(#) restore a database
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --instance=<name>       Sql Server instance name [${instance}]
# @(-) --database=<name>       target database name [${database}]
# @(-) --full=<filename>       restore from this full backup [${full}]
# @(-) --diff=<filename>       restore with this differential backup [${diff}]
# @(-) --[no]verifyonly        only check the backup restorability [${verifyonly}]
#
# @(@) Note 1: you must at least provide a full backup to restore, and may also provide an additional differential backup file.
# @(@) Note 2: target database is mandatory unless you only want a backup restorability check, in which case '--dummy' option is not honored.
# @(@) Note 3: "dbms.pl restore" provides an execution report according to the configured options.
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

use strict;
use utf8;
use warnings;

use TTP::DBMS;
my $running = $ep->runner();

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	instance => 'MSSQLSERVER',
	database => '',
	full => '',
	diff => '',
	verifyonly => 'no'
};

my $opt_instance = $defaults->{instance};
my $opt_instance_set = false;
my $opt_database = $defaults->{database};
my $opt_full = $defaults->{full};
my $opt_diff = $defaults->{diff};
my $opt_verifyonly = false;

my $dbms = undef;

# -------------------------------------------------------------------------------------------------
# restore the provided backup file

sub doRestore {
	if( $opt_verifyonly ){
		msgOut( "verifying the restorability of '$opt_full'".( $opt_diff ? ", with additional diff" : "" )."..." );
	} else {
		msgOut( "restoring database '$opt_instance\\$opt_database' from '$opt_full'".( $opt_diff ? ", with additional diff" : "" )."..." );
	}
	my $res = $dbms->restoreDatabase({
		database => $opt_database,
		full => $opt_full,
		diff => $opt_diff,
		verifyonly => $opt_verifyonly
	});
	if( !$opt_verifyonly ){
		# if we have restore something (not just verified the backup files), then we create an execution report
		#  with the same properties and options than dbms.pl backup
		my $mode = $opt_diff ? 'diff' : 'full';
		my $data = {
			instance => $opt_instance,
			database => $opt_database,
			full => $opt_full,
			mode => $mode
		};
		if( $opt_diff ){
			$data->{diff} = $opt_diff;
		} else {
			msgVerbose( "emptying '/diff' MQTT message as restored from a full backup" );
			my $cmd = 'mqtt.pl publish -topic '.$ep->node()->name().'/executionReport/'.$running->command().'/'.$running->verb()."/$opt_instance/$opt_database/diff -payload \"\" -retain -nocolored";
			msgOut( "executing '$cmd'" );
			`$cmd`;
		}
		TTP::executionReport({
			file => {
				data => $data
			},
			mqtt => {
				data => $data,
				topic => $ep->node()->name().'/executionReport/'.$running->command().'/'.$running->verb()."/$opt_instance/$opt_database",
				options => "-retain",
				excludes => [
					'instance',
					'database',
					'cmdline',
					'command',
					'verb',
					'host'
				]
			}
		});
	}
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
	"instance=s"		=> sub {
		my( $opt_name, $opt_value ) = @_;
		$opt_instance = $opt_value;
		$opt_instance_set = true;
	},
	"database=s"		=> \$opt_database,
	"full=s"			=> \$opt_full,
	"diff=s"			=> \$opt_diff,
	"verifyonly!"		=> \$opt_verifyonly )){

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
msgVerbose( "got instance='$opt_instance'" );
msgVerbose( "got instance_set='".( $opt_instance_set ? 'true':'false' )."'" );
msgVerbose( "got database='$opt_database'" );
msgVerbose( "got full='$opt_full'" );
msgVerbose( "got diff='$opt_diff'" );
msgVerbose( "got verifyonly='".( $opt_verifyonly ? 'true':'false' )."'" );

msgErr( "'--instance' option is mandatory, but is not specified" ) if !$opt_instance;
msgErr( "'--database' option is mandatory, but is not specified" ) if !$opt_database && !$opt_verifyonly;
msgErr( "'--full' option is mandatory, but is not specified" ) if !$opt_full;
msgErr( "$opt_diff: file not found or not readable" ) if $opt_diff && ! -f $opt_diff;

# instanciates the DBMS class
$dbms = TTP::DBMS->new( $ep, { instance => $opt_instance }) if !TTP::errs();

if( !TTP::errs()){
	doRestore();
}

TTP::exit();
