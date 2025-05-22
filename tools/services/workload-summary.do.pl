# @(#) print a workload summary
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --workload=<name>       the workload name [${workload}]
# @(-) --commands=<name>       the name of the environment variable which holds the commands [${commands}]
# @(-) --start=<name>          the name of the environment variable which holds the starting timestamp [${start}]
# @(-) --end=<name>            the name of the environment variable which holds the ending timestamp [${end}]
# @(-) --rc=<name>             the name of the environment variable which holds the return codes [${rc}]
# @(-) --count=<count>         the count of commands to deal with [${count}]
#
# Copyright (©) 2023-2025 PWI Consulting for Inlingua
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

use utf8;
use strict;
use warnings;

use Data::Dumper;
use Path::Tiny;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	workload => '',
	commands => 'command',
	start => 'start',
	end => 'end',
	rc => 'rc',
	count => 0
};

my $opt_workload = $defaults->{workload};
my $opt_commands = $defaults->{commands};
my $opt_start = $defaults->{start};
my $opt_end = $defaults->{end};
my $opt_rc = $defaults->{rc};
my $opt_count = $defaults->{count};

=pod
+=============================================================================================================================+
|  WORKLOAD SUMMARY                                                                                                           |
|                                                                       started at               ended at                  RC |
+---------------------------------------------------------------------+------------------------+------------------------+-----+
| dbms.pl backup -service MSSQLSERVER -database inlingua17a -diff     | 2024-02-07 22:00:02,26 | 2024-02-07 22:00:02,98 |   0 |
| dbms.pl backup -service MSSQLSERVER -database inlingua21 -diff      | 2024-02-07 22:00:02,98 | 2024-02-07 22:00:03,58 |   0 |
| dbms.pl backup -service MSSQLSERVER -database TOM59331 -diff        | 2024-02-07 22:00:03,58 | 2024-02-07 22:00:04,59 |   0 |
+=============================================================================================================================+
|                                                                                                                             |
|                                                        EMPTY OUTPUT                                                         |
|                                                                                                                             |
+=============================================================================================================================+
=cut

# -------------------------------------------------------------------------------------------------
# print a funny workload summary

sub printSummary {
	# get the results from the environment
	my @results = ();
	my $maxLength = 0;
	for( my $i=0 ; $i<$opt_count ; ++$i ){
		my $command = $ENV{$opt_commands."_".$i};
		msgVerbose( "pushing i=$i command='$command'" );
		push( @results, {
			command => $command,
			start => $ENV{$opt_start."_".$i},
			end => $ENV{$opt_end."_".$i},
			rc => $ENV{$opt_rc."_".$i}
		});
		if( length $command > $maxLength ){
			$maxLength = length $command;
		}
	}
	if( $opt_count == 0 ){
		$maxLength = 65; # arbitrary value long enough to get a pretty display (and the totLength be even)
	}
	# display the summary
	my $totLength = $maxLength + 63;
	my $stdout = "";
	$stdout .= TTP::pad( "+", $totLength-1, '=' )."+".EOL;
	$stdout .= TTP::pad( "| WORKLOAD SUMMARY for <$opt_workload>", $totLength-1, ' ' )."|".EOL;
	$stdout .= TTP::pad( "|", $maxLength+8, ' ' ).TTP::pad( "started at", 25, ' ' ).TTP::pad( "ended at", 25, ' ' )." RC |".EOL;
	$stdout .= TTP::pad( "+", $maxLength+6, '-' ).TTP::pad( "+", 25, '-' ).TTP::pad( "+", 25, '-' )."+-----+".EOL;
	# display the result or an empty output
	if( $opt_count > 0 ){
		my $i = 0;
		foreach my $it ( @results ){
			$i += 1;
			msgVerbose( "printing i=$i execution report" );
			$stdout .= TTP::pad( "| $it->{command}", $maxLength+6, ' ' ).TTP::pad( "| $it->{start}", 25, ' ' ).TTP::pad( "| $it->{end}", 25, ' ' ).sprintf( "| %3d |", $it->{rc} ).EOL;
		}
	} else {
		#print TTP::pad( "|", $totLength-1, ' ' )."|".EOL;
		$stdout .= TTP::pad( "|", $totLength/2 - 6, ' ' ).TTP::pad( "EMPTY OUTPUT", $totLength/2 + 5, ' ' )."|".EOL;
		#print TTP::pad( "|", $totLength-1, ' ' )."|".EOL;
	}
	$stdout .= "+".TTP::pad( "", $totLength-2, '=' )."+".EOL;
	# both send the summary to the log (here to stdout) and execute the provided command
	# must manage SUBJECT and OPTIONS macros
	my $command = $ep->var([ 'site', 'workloadSummary', 'command' ]);
	if( $command ){
		my $host = $ep->node()->name();
		my $textfname = TTP::getTempFileName();
		my $fh = path( $textfname );
		$fh->spew( $stdout );
		my $subject = sprintf( "[%s\@%s] workload summary", $opt_workload, $host );
		msgOut( "subject='$subject'" );
		my $dummy = $ep->runner()->dummy() ? "-dummy" : "";
		my $verbose = $ep->runner()->verbose() ? "-verbose" : "";
		# this script is not interactive but written to be executed as part of a batch - there is so no reason to log stdout of the command because all msgXxxx() of the command are already logged
		TTP::commandExec( "$command -nocolored $dummy $verbose", {
			macros => {
				SUBJECT => $subject,
				OPTIONS => "-textfname $textfname"
			}
		});
	}
	# and to stdout (at last)
	print $stdout;
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> sub { $ep->runner()->help( @_ ); },
	"colored!"			=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"			=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"			=> sub { $ep->runner()->verbose( @_ ); },
	"workload=s"		=> \$opt_workload,
	"commands=s"		=> \$opt_commands,
	"start=s"			=> \$opt_start,
	"end=s"				=> \$opt_end,
	"rc=s"				=> \$opt_rc,
	"count=i"			=> \$opt_count	)){

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
msgVerbose( "got workload='$opt_workload'" );
msgVerbose( "got commands='$opt_commands'" );
msgVerbose( "got start='$opt_start'" );
msgVerbose( "got end='$opt_end'" );
msgVerbose( "got rc='$opt_rc'" );
msgVerbose( "got count='$opt_count'" );

if( !TTP::errs()){
	printSummary();
}

TTP::exit();
