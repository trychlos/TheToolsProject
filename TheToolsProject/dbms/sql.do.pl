# @(#) execute a SQL command or a script on a DBMS instance
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --service=<name>        acts on the named service [${service}]
# @(-) --instance=<name>       acts on the named instance [${instance}]
# @(-) --[no]stdin             whether the sql command has to be read from stdin [${stdin}]
# @(-) --script=<filename>     the sql script filename [${script}]
# @(-) --command=<command>     the sql command as a string [${command}]
# @(-) --[no]tabular           format the output as tabular data [${tabular}]
# @(-) --[no]multiple          whether we expect several result sets [${multiple}]
# @(-) --json=<json>           the json output file [${json}]
# @(-) --columns=<columns>     an output file which will get the columns named [${columns}]
#
# @(@) The provided SQL script may or may not have a displayable result. Nonetheless, this verb will always display all the script output.
# @(@) In a Windows command prompt, use Ctrl+Z to terminate the stdin stream (or use a HERE document).
# @(@) Use Ctrl+D in a Unix terminal.
# @(@) '--dummy' option is ignored when SQL command is a SELECT sentence.
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

use Path::Tiny;

use TTP::DBMS;
use TTP::Service;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	service => '',
	instance => 'MSSQLSERVER',
	stdin => 'no',
	script => '',
	command => '',
	tabular => 'no',
	multiple => 'no',
	json => '',
	columns => ''
};

my $opt_service = $defaults->{service};
my $opt_instance = $defaults->{instance};
my $opt_instance_set = false;
my $opt_stdin = false;
my $opt_script = $defaults->{script};
my $opt_command = $defaults->{command};
my $opt_tabular = false;
my $opt_multiple = false;
my $opt_json = $defaults->{json};
my $opt_columns = $defaults->{columns};

# may be overriden by the service if specified
my $jsonable = $ep->node();
my $dbms = undef;

# -------------------------------------------------------------------------------------------------
# DBMS::execSqlCommand returns a hash with:
# - ok: true|false
# - result: the result set as an array ref
#   an array of hashes for a single set, or an array of arrays of hashes in case of a multiple result sets
# - stdout: an array of what has been printed (which are often error messages)

sub _result {
	my ( $res ) = @_;
	if( $res->{ok} && scalar @{$res->{result}} && !$opt_tabular && !$opt_json ){
		my $isHash = false;
		foreach my $it ( @{$res->{result}} ){
			$isHash = true if ref( $it ) eq 'HASH';
			print $it if !ref( $it );
		}
		if( $isHash ){
			msgWarn( "result contains data, should have been displayed with '--tabular' or saved with '--json' options" );
		}
	}
	if( $res->{ok} ){
		msgOut( "success" );
	} else {
		msgErr( "NOT OK" );
	}
}

# -------------------------------------------------------------------------------------------------
# execute the sql command to be read from stdin

sub execSqlStdin {
	my $command = '';
	while( <> ){
		$command .= $_;
	}
	chomp $command;
	msgVerbose( "executing '$command' from stdin" );
	_result( $dbms->execSqlCommand( $command, { tabular => $opt_tabular, json => $opt_json, columns => $opt_columns, multiple => $opt_multiple }));
}

# -------------------------------------------------------------------------------------------------
# execute the sql script

sub execSqlScript {
	msgVerbose( "executing from '$opt_script'" );
	my $sql = path( $opt_script )->slurp_utf8;
	msgVerbose( "sql='$sql'" );
	_result( $dbms->execSqlCommand( $sql, { tabular => $opt_tabular, json => $opt_json, columns => $opt_columns, multiple => $opt_multiple }));
}

# -------------------------------------------------------------------------------------------------
# execute the sql command passed in the command-line

sub execSqlCommand {
	msgVerbose( "executing command='$opt_command'" );
	_result( $dbms->execSqlCommand( $opt_command, { tabular => $opt_tabular, json => $opt_json, columns => $opt_columns, multiple => $opt_multiple }));
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$ep->{run}{help},
	"colored!"			=> \$ep->{run}{colored},
	"dummy!"			=> \$ep->{run}{dummy},
	"verbose!"			=> \$ep->{run}{verbose},
	"service=s"			=> \$opt_service,
	"instance=s"		=> sub {
		my( $opt_name, $opt_value ) = @_;
		$opt_instance = $opt_value;
		$opt_instance_set = true;
	},
	"stdin!"			=> \$opt_stdin,
	"script=s"			=> \$opt_script,
	"command=s"			=> \$opt_command,
	"tabular!"			=> \$opt_tabular,
	"multiple!"			=> \$opt_multiple,
	"json=s"			=> \$opt_json,
	"columns=s"			=> \$opt_columns )){

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
msgVerbose( "found service='$opt_service'" );
msgVerbose( "found instance='$opt_instance'" );
msgVerbose( "found instance_set='".( $opt_instance_set ? 'true':'false' )."'" );
msgVerbose( "found stdin='".( $opt_stdin ? 'true':'false' )."'" );
msgVerbose( "found script='$opt_script'" );
msgVerbose( "found command='$opt_command'" );
msgVerbose( "found tabular='".( $opt_tabular ? 'true':'false' )."'" );
msgVerbose( "found multiple='".( $opt_multiple ? 'true':'false' )."'" );
msgVerbose( "found json='$opt_json'" );
msgVerbose( "found columns='$opt_columns'" );

# must have either -service or -instance options
# compute instance from service
my $count = 0;
$count += 1 if $opt_service;
$count += 1 if $opt_instance_set;
if( $count == 0 ){
	msgErr( "must have one of '--service' or '--instance' option, none found" );
} elsif( $count > 1 ){
	msgErr( "must have one of '--service' or '--instance' option, both found" );
} elsif( $opt_service ){
	if( $jsonable->hasService( $opt_service )){
		$jsonable = TTP::Service->new( $ep, { service => $opt_service });
		$opt_instance = $jsonable->var([ 'DBMS', 'instance' ]);
	} else {
		msgErr( "service '$opt_service' if not defined on current execution node" ) ;
	}
}

# instanciates the DBMS class
$dbms = TTP::DBMS->new( $ep, { instance => $opt_instance }) if !TTP::errs();

# either -stdin or -script or -command options must be specified and only one
my $count = 0;
$count += 1 if $opt_stdin;
$count += 1 if $opt_script;
$count += 1 if $opt_command;
if( $count != 1 ){
	msgErr( "either '--stdint' or '--script' or '--command' option must be specified" );
} elsif( $opt_script ){
	if( ! -f $opt_script ){
		msgErr( "$opt_script: file is not found or not readable" );
	}
}

if( !TTP::errs()){
	execSqlStdin() if $opt_stdin;
	execSqlScript() if $opt_script;
	execSqlCommand() if $opt_command;
}

TTP::exit();
