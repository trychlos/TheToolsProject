# @(#) execute a SQL command or a script on a DBMS instance
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --service=<name>        acts on the named service [${service}]
# @(-) --target=<name>         target node [${target}]
# @(-) --[no]stdin             whether the sql command has to be read from stdin [${stdin}]
# @(-) --script=<filename>     the sql script filename [${script}]
# @(-) --command=<command>     the sql command as a string [${command}]
# @(-) --[no]tabular           format the output as tabular data [${tabular}]
# @(-) --[no]multiple          whether we expect several result sets [${multiple}]
# @(-) --json=<json>           the json output file [${json}]
# @(-) --columns=<columns>     an output file which will get the columns named [${columns}]
#
# @(@) Note 1: The provided SQL script may or may not have a displayable result. Nonetheless, this verb will always display all the script output.
# @(@) Note 2: In a Windows command prompt, use Ctrl+Z to terminate the stdin stream (or use a HERE document).
# @(@)         Use Ctrl+D in a Unix terminal.
# @(@) Note 3: '--dummy' option is ignored when SQL command is a SELECT sentence.
#
# TheToolsProject - Tools System and Working Paradigm for IT Production
# Copyright (©) 1998-2023 Pierre Wieser (see AUTHORS)
# Copyright (©) 2023-2026 PWI Consulting
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

use Path::Tiny;

use TTP::Node;
use TTP::Service;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	service => '',
	target => '',
	stdin => 'no',
	script => '',
	command => '',
	tabular => 'no',
	multiple => 'no',
	json => '',
	columns => ''
};

my $opt_service = $defaults->{service};
my $opt_target = $defaults->{target};
my $opt_stdin = false;
my $opt_script = $defaults->{script};
my $opt_command = $defaults->{command};
my $opt_tabular = false;
my $opt_multiple = false;
my $opt_json = $defaults->{json};
my $opt_columns = $defaults->{columns};

# the node which hosts the requested service
my $objNode = undef;
# the service object
my $objService = undef;
# the DBMS object
my $objDbms = undef;

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
	_result( $objDbms->execSqlCommand( $command, { tabular => $opt_tabular, json => $opt_json, columns => $opt_columns, multiple => $opt_multiple }));
}

# -------------------------------------------------------------------------------------------------
# execute the sql script

sub execSqlScript {
	msgVerbose( "executing from '$opt_script'" );
	my $sql = path( $opt_script )->slurp_utf8;
	#msgVerbose( "sql='$sql'" );
	_result( $objDbms->execSqlCommand( $sql, { tabular => $opt_tabular, json => $opt_json, columns => $opt_columns, multiple => $opt_multiple }));
}

# -------------------------------------------------------------------------------------------------
# execute the sql command passed in the command-line

sub execSqlCommand {
	msgVerbose( "executing command='$opt_command'" );
	_result( $objDbms->execSqlCommand( $opt_command, { tabular => $opt_tabular, json => $opt_json, columns => $opt_columns, multiple => $opt_multiple }));
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> sub { $ep->runner()->help( @_ ); },
	"colored!"			=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"			=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"			=> sub { $ep->runner()->verbose( @_ ); },
	"service=s"			=> \$opt_service,
	"target=s"			=> \$opt_target,
	"stdin!"			=> \$opt_stdin,
	"script=s"			=> \$opt_script,
	"command=s"			=> \$opt_command,
	"tabular!"			=> \$opt_tabular,
	"multiple!"			=> \$opt_multiple,
	"json=s"			=> \$opt_json,
	"columns=s"			=> \$opt_columns )){

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
msgVerbose( "got service='$opt_service'" );
msgVerbose( "got target='$opt_target'" );
msgVerbose( "got stdin='".( $opt_stdin ? 'true':'false' )."'" );
msgVerbose( "got script='$opt_script'" );
msgVerbose( "got command='$opt_command'" );
msgVerbose( "got tabular='".( $opt_tabular ? 'true':'false' )."'" );
msgVerbose( "got multiple='".( $opt_multiple ? 'true':'false' )."'" );
msgVerbose( "got json='$opt_json'" );
msgVerbose( "got columns='$opt_columns'" );

# must have --service option
# find the node which hosts this service in this same environment (should be at most one)
# and check that the service is DBMS-aware
if( $opt_service ){
	$objNode = TTP::Node->findByService( $ep->node()->environment(), $opt_service, { target => $opt_target });
	if( $objNode ){
		msgVerbose( "got hosting node='".$objNode->name()."'" );
		$objService = TTP::Service->new( $ep, { service => $opt_service });
		if( $objService->wantsLocal() && $objNode->name() ne $ep->node()->name()){
			TTP::execRemote( $objNode->name());
			TTP::exit();
		}
		$objDbms = $objService->newDbms({ node => $objNode });
	}
} else {
	msgErr( "'--service' option is mandatory, but is not specified" );
}

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
