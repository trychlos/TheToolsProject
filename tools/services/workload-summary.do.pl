# @(#) print a workload summary
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) either:
# @(-) --workload=<name>       the workload name [${workload}]
# @(-) --commands=<name>       the name of the environment variable which holds the commands [${commands}]
# @(-) --start=<name>          the name of the environment variable which holds the starting timestamp [${start}]
# @(-) --end=<name>            the name of the environment variable which holds the ending timestamp [${end}]
# @(-) --rc=<name>             the name of the environment variable which holds the return codes [${rc}]
# @(-) --count=<count>         the count of commands to deal with [${count}]
# @(-) or:
# @(-) --since=<since>         since when getting the summary [${since}]
# @(-) --until=<until>         until when getting the summary [${until}]
#
# @(@) Note 1: When the '--workload' argument is specified, then we have a run from workload.cmd (resp. workload.sh) and the option
# @(@)         either publish a summary per workload or per command (or both), depending of the TTP site configuration.
# @(@)         When the '--since' argument is specified, then we build and publish a summary per period.
# @(@) Note 2: '--since' and '--until' arguments can be specified as '<n>d' for <n> days, or '<n>h' for <n> hours, or as a mix of these units.
#
# Copyright (©) 2023-2026 PWI Consulting for Inlingua
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

use utf8;
use strict;
use warnings;

use Data::Dumper;
use JSON;
use Path::Tiny;
use Time::Duration::Parse;
use Time::Moment;

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
	count => 0,
	since => '',
	until => ''
};

my $opt_workload = $defaults->{workload};
my $opt_commands = $defaults->{commands};
my $opt_start = $defaults->{start};
my $opt_end = $defaults->{end};
my $opt_rc = $defaults->{rc};
my $opt_count = $defaults->{count};
my $opt_since = $defaults->{since};
my $opt_until = $defaults->{until};

# whether we use the first form of a per-workload summary, or the second form of a per-period summary
my $per_workload = false;
my $per_period = false;
my $since_date = undef;
my $until_date = undef;

# -------------------------------------------------------------------------------------------------
# build printable output from a temporary JSON file
# (I):
# - the JSON temp filename
#   contains an array of the commands to be printed, in the right order when printing a per-workload summary
#   contains a single item to be printed for a per-command result
# - an optional options args with following keys:
#   > per_command: whether we are just printing a single command, defaulting to false
#   > environment: the running environment identifier, used by the per-period output
#   > bottomSummary: whether to print a summary at the bottom, defaulting to true
#   > topSummary: whether to print a summary at the top, defaulting to true
# (O):
# - the output temp filename

sub printable_from {
	my ( $jsonfname, $opts ) = @_;
	$opts //= {};
	my $per_command = $opts->{per_command} // false;
	msgVerbose( "found per_command='".( $per_command ? 'true' : 'false' )."'" );
	my $environment = $opts->{environment} // '';
	my $bottomSummary = $opts->{bottomSummary} // true;
	my $topSummary = $opts->{topSummary} // true;
	msgVerbose( "found environment='$environment'" );

	my $json = decode_json( path( $jsonfname )->slurp_utf8 );
	$json = [ $json ] if ref( $json ) eq 'HASH';
	my $results = {};
	my $stamps = {};
	my $maxLength = 62;
	my $count = 0;
	my $rc = 0;
	# build a results hash workload->node->[commands]
	# build a stamps hash workload->started to have an ordering when there are several workloads
	# compute total count of commands
	# compute maxLength of the commands
	# compute count of commands with rc > 0
	foreach my $it ( @{$json} ){
		#print Dumper( $it );
		$count += 1;
		$results->{$it->{WORKLOAD}} //= {};
		$results->{$it->{WORKLOAD}}{$it->{NODE}} //= [];
		push( @{$results->{$it->{WORKLOAD}}{$it->{NODE}}}, $it );
		$stamps->{$it->{WORKLOAD}} = $it->{STARTED} if !$stamps->{$it->{WORKLOAD}};
		$maxLength = length( $it->{COMMAND} ) if length( $it->{COMMAND} ) > $maxLength;
		$rc += 1 if $it->{RC} > 0;
	}
	# sort stamps to get the workloads in ascending order of execution
	# ordered is an array of "started|workload" strings
	my $ordered = [];
	foreach my $it ( keys %{$stamps} ){
		push( @{$ordered}, "$stamps->{$it}|$it" );
	}
	my @ordered = sort( @{$ordered} );
	# we now have the right order if several workloads
	# build the summary to be published / sent by email / logged
	$maxLength += 6 if $per_period;
	my $totLength = $maxLength + 64;
	my $stdout = EOL;
	$stdout .= TTP::pad( "+", $totLength-1, '=' )."+".EOL;
	# header differs depending of the type of publication
	my $prefix = '';
	my $sep = '-';
	if( $per_workload ){
		my $node = $ep->node()->name();
		if( $per_command ){
			$stdout .= TTP::pad( "| <$opt_workload\@$node> Command result ", $totLength-57, ' ' );
		} else {
			$stdout .= TTP::pad( "| <$opt_workload\@$node> Workload summary ", $totLength-57, ' ' );
		}
	} elsif( $per_period ){
		$prefix = '     ';
		$sep = '=';
		$stdout .= TTP::pad( "| Workloads summary since $since_date in '$environment' environment", $totLength-57, ' ' );
		if( !$per_command && $topSummary ){
			$stdout .= TTP::pad( "| ".sprintf( "%3d", $count )." total command(s)", $totLength-1, ' ' )."|".EOL;
			$stdout .= TTP::pad( "| ".sprintf( "%3d", $rc )." with an exit code greater than zero", $totLength-1, ' ' )."|".EOL;
		}
	} else {
		msgErr( "unhandled publication type" );
	}
	$stdout .= TTP::pad( "Started at", 26, ' ' ).TTP::pad( "Ended at", 26, ' ' )." Rc |".EOL;
	$stdout .= TTP::pad( "+", $maxLength+5, $sep ).TTP::pad( "+", 26, $sep ).TTP::pad( "+", 26, $sep ).TTP::pad( "+", 6, $sep )."+".EOL;
	if( $count ){
		my $first = true;
		foreach my $it ( @ordered ){
			my @w = split( /\|/, $it );
			my $workload = $w[1];
			$stdout .= TTP::pad( "+", $maxLength+5, '-' ).TTP::pad( "+", 26, '-' ).TTP::pad( "+", 26, '-' ).TTP::pad( "+", 6, '-' )."+".EOL if !$first;
			$first = false;
			$stdout .= TTP::pad( "| <$workload> workload results", $totLength-1, ' ' )."|".EOL if $per_period;
			foreach my $node ( sort keys %{$results->{$workload}} ){
				$stdout .= TTP::pad( "|    $node", $totLength-1, ' ' )."|".EOL if $per_period;
				my @commands = sort { $a->{STARTED} cmp $b->{STARTED} } @{$results->{$workload}{$node}};
				foreach my $it ( @commands ){
					my $started = $it->{STARTED};
					$started .= "000000";
					$started = substr( $started, 0, 23 );
					my $ended = $it->{ENDED};
					$ended .= "000000";
					$ended = substr( $ended, 0, 23 );
					$stdout .= TTP::pad( "|$prefix $it->{COMMAND}", $maxLength+5, ' ' ).TTP::pad( "| $started", 26, ' ' ).TTP::pad( "| $ended", 26, ' ' ).sprintf( "| %3d |", $it->{RC} ).EOL;
				}
			}
		}
		if( !$per_command && $bottomSummary ){
			$stdout .= TTP::pad( "+", $maxLength+5, $sep ).TTP::pad( "+", 26, $sep ).TTP::pad( "+", 26, $sep ).TTP::pad( "+", 6, $sep )."+".EOL;
			$stdout .= TTP::pad( "| ".sprintf( "%3d", $count )." total command(s)", $totLength-1, ' ' )."|".EOL;
			$stdout .= TTP::pad( "| ".sprintf( "%3d", $rc )." with an exit code greater than zero", $totLength-1, ' ' )."|".EOL;
		}
	} else {
		$stdout .= TTP::pad( "|", $totLength-1, ' ' )."|".EOL;
		$stdout .= TTP::pad( "|", ( $totLength-14 )/2, ' ' ).TTP::pad( "EMPTY OUTPUT", ( $totLength/2 ) +6, ' ' )."|".EOL;
		$stdout .= TTP::pad( "|", $totLength-1, ' ' )."|".EOL;
	}
	$stdout .= TTP::pad( "+", $totLength-1, '=' )."+".EOL;
	# and to stdout (at last) which sends the summary to the daily log
	msgOut( $stdout );
	my $textfname = TTP::getTempFileName();
	my $fh = path( $textfname );
	$fh->spew( $stdout );
	return $textfname;
}

# -------------------------------------------------------------------------------------------------
# print a funny per-period workload summary
# this is almost same that per-workload summary, adding a top-summary for all workloads of the period
# we order that by workload/node

=pod
+================================================================================================================================+
|                                                                          started at               ended at                  RC |
+------------------------------------------------------------------------+------------------------+------------------------+-----+
| daily.morning workload summary                                                                                                 |
|    WS12DEV1                                                                                                                    |
|       dbms.pl backup -service MSSQLSERVER -database inlingua17a -diff  | 2024-02-07 22:00:02.26 | 2024-02-07 22:00:02.98 |   0 |
|       dbms.pl backup -service MSSQLSERVER -database inlingua17a -diff  | 2024-02-07 22:00:02.26 | 2024-02-07 22:00:02.98 |   0 |
|       dbms.pl backup -service MSSQLSERVER -database inlingua21 -diff   | 2024-02-07 22:00:02.98 | 2024-02-07 22:00:03.58 |   0 |
|       dbms.pl backup -service MSSQLSERVER -database TOM59331 -diff     | 2024-02-07 22:00:03.58 | 2024-02-07 22:00:04.59 |   0 |
|    WS12DEV1                                                                                                                    |
|       dbms.pl backup -service MSSQLSERVER -database inlingua17a -diff  | 2024-02-07 22:00:02.26 | 2024-02-07 22:00:02.98 |   0 |
+------------------------------------------------------------------------+------------------------+------------------------+-----+
| daily.evening workload summary                                                                                                 |
|    WS12DEV1                                                                                                                    |
|       dbms.pl backup -service MSSQLSERVER -database inlingua17a -diff  | 2024-02-07 22:00:02.26 | 2024-02-07 22:00:02.98 |   0 |
+================================================================================================================================+
|                                                                                                                                |
|                                                       EMPTY OUTPUT                                                             |
|                                                                                                                                |
+================================================================================================================================+
=cut

sub doPerPeriod {
	# get a JSON content from pre-stored results
	my $commands = TTP::commandByOS([ 'workloadSummary', 'perPeriod', 'get' ]);
	if( $commands && scalar( @{$commands} )){
		if( !$until_date ){
			$until_date = Time::Moment->now->strftime( "%Y-%m-%d %H:%M:%S" );
			msgVerbose( "computed until_date='$until_date'" );
		}
		my $jsonfname = TTP::getTempFileName();
		my $res = TTP::commandExec( $commands, {
			macros => {
				JSONFNAME => $jsonfname,
				SINCE => $since_date,
				UNTIL => $until_date
			}
		});
		if( $res->{success} ){
			$commands = TTP::commandByOS([ 'workloadSummary', 'perPeriod', 'publish' ]);
			if( $commands && scalar( @{$commands} )){
				# get the running environment
				$res = TTP::filter( "services.pl list -environment" );
				my $environment = $res->[0];
				my $bottom = TTP::var( 'workloadSummary', 'perPeriod', 'publish', 'bottomSummary' ) // true;
				my $top = TTP::var( 'workloadSummary', 'perPeriod', 'publish', 'topSummary' ) // true;
				my $textfname = printable_from( $jsonfname, { environment => $environment, bottomSummary => $bottom, topSummary => $top });
				$res = TTP::commandExec( $commands, {
					macros => {
						JSONFNAME => $jsonfname,
						TEXTFNAME => $textfname,
						ENVIRONMENT => $environment,
						SINCE => $since_date,
						UNTIL => $until_date
					}
				});
			} else {
				msgWarn( "per-period summary detected, and no per-period 'publish' command found" );
			}
		}
	} else {
		msgWarn( "per-period summary detected, and no per-period 'get' command found" );
	}
}

# -------------------------------------------------------------------------------------------------
# print a funny workload summary
# may also produce a per-command output

=pod
+=============================================================================================================================+
|  WORKLOAD SUMMARY for <daily>                                                                                               |
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

sub doPerWorkload {
	# get the results from the environment, building an array of per-command hashes
	my @results = ();
	for( my $i=0 ; $i<$opt_count ; ++$i ){
		my $command = $ENV{$opt_commands."_".$i};
		msgVerbose( "pushing i=$i command='$command'" );
		push( @results, {
			NODE => $ep->node()->name(),
			WORKLOAD => $opt_workload,
			COMMAND => $command,
			STARTED => $ENV{$opt_start."_".$i},
			ENDED => $ENV{$opt_end."_".$i},
			RC => $ENV{$opt_rc."_".$i}
		});
	}
	my $have_workload = false;
	my $have_command = false;
	# which applyable commands ?
	# for the per-workload, have to build a printable output
	my $commands = TTP::commandByOS([ 'workloadSummary', 'perWorkload', 'publish' ]);
	if( $commands && scalar( @{$commands} )){
		$have_workload = true;
		# write all the content as a temp JSON file
		my $jsonfname = TTP::getTempFileName();
		path( $jsonfname )->spew_utf8( encode_json( \@results ));
		# produce the expected outputs
		my $textfname = printable_from( $jsonfname );
		my $res = TTP::commandExec( $commands, {
			macros => {
				WORKLOAD => $opt_workload,
				TEXTFNAME => $textfname
			}
		});
	} else {
		msgVerbose( "per-workload summary detected, and no per-workload command found" );
	}
	# for the per-command, have to build a printable output too
	# the per-command has also access to each and every workload item
	$commands = TTP::commandByOS([ 'workloadSummary', 'perWorkload', 'perCommand', 'publish' ]);
	if( $commands && scalar( @{$commands} )){
		$have_command = true;
		# convert to SQL ?
		my $convertSql = TTP::var([ 'workloadSummary', 'perWorkload', 'perCommand', 'convertToSql' ]) // false;
		# iter on each workload command
		if( $opt_count ){
			foreach my $it ( @results ){
				# write each item as a temp JSON file
				my $jsonfname = TTP::getTempFileName();
				path( $jsonfname )->spew_utf8( encode_json( $it ));
				my $textfname = printable_from( $jsonfname, { per_command => true });
				my $it_command = $it->{COMMAND};
				if( $convertSql ){
					$it_command =~ s/"/\\"/g;
				}
				my $res = TTP::commandExec( $commands, {
					macros => {
						WORKLOAD => $opt_workload,
						TEXTFNAME => $textfname,
						COMMAND => $it_command,
						STARTED => $it->{STARTED},
						ENDED => $it->{ENDED},
						RC => $it->{RC}
					}
				});
			}
		} else {
			msgVerbose( "found per-command command, but no item to produce a result" );
		}
	} else {
		msgVerbose( "per-workload summary detected, and no per-command command found" );
	}
	if( !$have_workload && !$have_command ){
		msgWarn( "per-workload summary detected, but no per-workload nor per-command command found" );
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
	"workload=s"		=> \$opt_workload,
	"commands=s"		=> \$opt_commands,
	"start=s"			=> \$opt_start,
	"end=s"				=> \$opt_end,
	"rc=s"				=> \$opt_rc,
	"count=i"			=> \$opt_count,
	"since=s"			=> \$opt_since,
	"until=s"			=> \$opt_until )){

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
msgVerbose( "got since='$opt_since'" );
msgVerbose( "got until='$opt_until'" );

# do wde have either a per-workload (first form) or per-period (second form) run, and only one of them ?
if( $opt_workload ){
	$per_workload = true;
	if( !$opt_commands || !$opt_start || !$opt_end || !$opt_rc ){
		msgErr( "all '--workload', '--commands', '--start', '--end', '--rc' and '--count' arguments are mandatory when asking for a per-workload summary" );
	}
}
if( $opt_since ){
	$per_period = true;
}
if( $per_workload && $per_period ){
	msgErr( "asking for both a per-workload and a per-period summary is not supported" );
}
if( !$per_workload && !$per_period ){
	msgErr( "a per-workload or a per-period summary is expected, no valid request found" );
}

# check that the since argument is right
if( $per_period ){
	my $seconds = parse_duration( $opt_since );
	if( $seconds ){
		my $tm = Time::Moment->now;
		my $since_tm = $tm->minus_seconds( $seconds );
		$since_date = $since_tm->strftime( "%Y-%m-%d %H:%M:%S" );
		msgVerbose( "since_date='$since_date'" );
	} else {
		msgErr( "unable to parse since='$opt_since' argument" );
	}
}

# check that the until argument is right when set
if( $per_period && $opt_until ){
	my $seconds = parse_duration( $opt_until );
	if( $seconds ){
		my $tm = Time::Moment->now;
		my $until_tm = $tm->minus_seconds( $seconds );
		$until_date = $until_tm->strftime( "%Y-%m-%d %H:%M:%S" );
		msgVerbose( "until_date='$until_date'" );
	} else {
		msgErr( "unable to parse until='$opt_until' argument" );
	}
}

if( !TTP::errs()){
	msgVerbose( "per_workload='".( $per_workload ? 'true' : 'false' )."'" );
	doPerWorkload() if $per_workload;
	msgVerbose( "per_period='".( $per_period ? 'true' : 'false' )."'" );
	doPerPeriod() if $per_period;
}

TTP::exit();
