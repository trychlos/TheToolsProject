# @(#) check objects
#
# @(-) --[no]help                   print this message, and exit [${help}]
# @(-) --[no]colored                color the output depending of the message level [${colored}]
# @(-) --[no]dummy                  dummy run [${dummy}]
# @(-) --[no]verbose                run verbosely [${verbose}]
# @(-) --[no]recurse                whether act recursively on a directory [${recurse}]
# @(-) --[no]timeline               whether check also for video timeline issues [${timeline}]
# @(-) --[no]bitstream              whether check also for divx bitstream issues [${bitstream}]
# @(-) --duration=<seconds>         whether check also for a minimum video duration [${duration}]
# @(-) --[no]specials               whether check for special characters in the filename [${specials}]
# @(-) --[no]repair                 whether try to repair the REPAIRABLE media [${repair}]
# @(-) --[no]keep-orig              whether keep the original file when repairing [${keepOrig}]
# @(-) --[no]verify                 whether verify the repaired media [${verify}]
#
# @(@) Note 1: The verb accepts one or more files or directories as positional arguments.
# @(@) Note 2: In dummy mode, candidate files are only displayed and no media check is performed.
# @(@) Note 3: You should be conscious that both Special characters and Timeline pathology repairs will change
#              the pathname of the media. If this is important for you, or your media is referenced elsewhere
#              (say in Kodi for example), you should not omit to update your libraries (remove, repair re-add).
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

use Data::Dumper;

use TTP::Media;
use TTP::Media::Video;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	recurse => 'yes',
	timeline => 'yes',
	bitstream => 'yes',
	duration => -1,
	specials => 'yes',
	repair => 'no',
	keepOrig => 'yes',
	verify => 'no'
};

my $opt_recurse = true;
my $opt_timeline = true;
my $opt_bitstream = true;
my $opt_duration = $defaults->{duration};
my $opt_specials = true;
my $opt_repair = false;
my $opt_keepOrig = true;
my $opt_verify = false;

my $stats = {
	walked => 0,
	filtered => 0,
	checked => 0,
	repaired => 0,
	verified => 0,

	# check counters set in fileCheck()
	# byLevel counters are intentionally initialized here to be always fully displayed
	# byFindings counters will only be displayed if the corresponding check option is truethy
	checkings => {
		byLevel => {
			OK => 0,
			ERROR => 0,
			FINDINGS => 0
		},
		byFindings => {
			BITSTREAM => {
				OK => 0,
				SUSPICIOUS => 0,
				REPAIRABLE => 0
			},
			DURATION => {
				OK => 0,
				FAILED => 0
			},
			SPECIALS => {
				OK => 0,
				REPAIRABLE => 0
			},
			TIMELINE => {
				OK => 0,
				SUSPICIOUS => 0,
				REPAIRABLE => 0
			}
		}
	},

	# repair counters set in fileRepair()
	repairings => {
		byLevel => {
			OK => 0,
			ERROR => 0
		},
		byFindings => {
			BITSTREAM => {
				TODO => 0,
				OK => 0,
				ERROR => 0
			},
			SPECIALS => {
				TODO => 0,
				OK => 0,
				ERROR => 0
			},
			TIMELINE => {
				TODO => 0,
				OK => 0,
				ERROR => 0
			}
		}
	},

	# verify counters set in fileVerify()
	verifyings => {
		byLevel => {
			OK => 0,
			ERROR => 0
		},
		byFindings => {
			BITSTREAM => {
				OK => 0,
				ERROR => 0
			},
			SPECIALS => {
				OK => 0,
				ERROR => 0
			},
			TIMELINE => {
				OK => 0,
				ERROR => 0
			}
		}
	}
};

my $opt_duration_set = false;

# -------------------------------------------------------------------------------------------------
# Orchestrates the full operations of a candidate file
#
# The full workflow is:
#	check ->
#	  maybe check for known bitstream pathology
#	  maybe check for (non-repairable) duration
#	  maybe check for special characters pathology
#	  maybe check for known timeline pathology
#     -> maybe repair
#        maybe repair known bitstream pathology
#        maybe repair special characters pathology
#        maybe repair known timeline pathology
#        -> maybe verify
#	        maybe verify known bitstream pathology
#	        maybe verify special characters pathology
#	        maybe verify known timeline pathology
#
# As we want to display messages as soon as they are available, and to wait for the end of a walked
# file to send the result, we may have have several lines for each file, only the last being meaningful.

sub checkOrchestration {
	my ( $fname ) = @_;

	# all files are counted in 'walked'
	msgLog( "checkOrchestration() fname='$fname'" );
	$stats->{walked} += 1;

	# only supported video extensions are counted in 'filtered'
	if( !TTP::Media::Video::isCapable( $fname )){
		msgLog( "checkOrchestration() not video-capable" );
		return;
	}

	$stats->{filtered} += 1;

	# check unless dummy mode
	if( $ep->runner()->dummy()){
		msgDummy( "would check: $fname" );
		return;
	}

	# if this file terminates with a file-level error, make sure the runnable errors count is incremented
	my $prevErrors = $ep->runner()->runnableErrs();

	# initial check of the file
	# file-level status can be OK, FINDINGS or ERROR
	$stats->{checked} += 1;
	my $checkResult = fileCheck( $fname );
	my $error = ( $checkResult->{status} eq TTP::Media::Video::ERROR );

	# if repair is asked ?
	# only try to repair if some REPAIRABLE have been found
	if( !$error && $opt_repair && $checkResult->{status} eq TTP::Media::Video::FINDINGS ){

		my $haveRepairable = false;
		foreach my $check ( sort keys %{$checkResult->{findings}} ){
			# duration failures cannot be repaired
			next if $check eq TTP::Media::Video::DURATION;
			next if $checkResult->{findings}{$check}{status} ne TTP::Media::Video::REPAIRABLE;
			$stats->{repairings}{byFindings}{$check}{TODO} //= 0;
			$stats->{repairings}{byFindings}{$check}{TODO} += 1;
			$haveRepairable = true;
		}

		if( $haveRepairable ){
			$stats->{repaired} += 1;
			my $repairResult = fileRepair( $checkResult );
			$error = true if $repairResult->{status} eq TTP::Media::Video::ERROR;

			if( !$error && $opt_verify ){
				$stats->{verified} += 1;
				my $verifyResult = fileVerify( $repairResult );
				$error = true if $verifyResult->{status} eq TTP::Media::Video::ERROR;
			}
		}
	}

	# display an error message if a hard error has been detected but msgErr() has not been called
	msgErr( "hard error detected in '$fname'" ) if $error && $prevErrors == $ep->runner()->runnableErrs();
}

# -------------------------------------------------------------------------------------------------
# Check a candidate file
# Video-supported extensions which do not embed any video stream as checked as OK.
# (I):
# - the filename
# (O):
# - the check results as a hash ref which following keys:
#   > fname: the input filename
#   > status: OK, ERROR or FINDINGS
#   > reasons: the ERROR reasons (if any)
#   > info: the JSON informations returned by ffprobe, should only be used on non-ERROR
#   > findings: a hash ref, keyed by check qualifier, with check-level keys as:
#     - status: the check-level status
#     - reasons: the reasons (if any)

sub fileCheck {
	my ( $fname ) = @_;

	msgVerbose( "checking '$fname'..." );

	my $result = TTP::Media::videoCheck( $fname, {
		timeline => $opt_timeline,
		bitstream => $opt_bitstream,
		duration => $opt_duration,
		specials => $opt_specials
	});

	# counters per level
	$stats->{checkings}{byLevel}{$result->{status}} //= 0;
	$stats->{checkings}{byLevel}{$result->{status}} += 1;

	# counters per check and final status
	if( $result->{status} ne TTP::Media::Video::ERROR ){
		foreach my $check ( sort keys( %{$result->{findings}} )){
			$stats->{checkings}{byFindings}{$check}{$result->{findings}{$check}{status}} //= 0;
			$stats->{checkings}{byFindings}{$check}{$result->{findings}{$check}{status}} += 1;
		}
	}

	return $result;
}

# -------------------------------------------------------------------------------------------------
# Try to repair a file which has exhibited one of the known-to-be-repairable pathologies
# (I):
# - the check results
# (O):
# - the repair results as a hash ref with following keys:
#   > fname: the output filename (may be the same than on input or has changed)
#   > status: OK or ERROR
#   > reasons: the ERROR reasons (if any)
#   > info: the JSON informations returned by ffprobe, should only be used on non-ERROR
#   > findings: a hash ref, keyed by check qualifier, with check-level keys as:
#     - status: OK or ERROR

sub fileRepair {
	my ( $checkResult ) = @_;
	my $result = undef;

	if(( $opt_bitstream &&
			$checkResult->{findings}{TTP::Media::Video::BITSTREAM}{status} eq TTP::Media::Video::REPAIRABLE ) ||
		( $opt_specials &&
				$checkResult->{findings}{TTP::Media::Video::SPECIALS}{status} eq TTP::Media::Video::REPAIRABLE ) ||
		( $opt_timeline &&
				$checkResult->{findings}{TTP::Media::Video::TIMELINE}{status} eq TTP::Media::Video::REPAIRABLE )){

		$result = TTP::Media::videoRepair( $checkResult, {
			timeline => $opt_timeline,
			bitstream => $opt_bitstream,
			specials => $opt_specials,
			keepOrig => $opt_keepOrig
		});

		# counters per level
		$stats->{repairings}{byLevel}{$result->{status}} //= 0;
		$stats->{repairings}{byLevel}{$result->{status}} += 1;

		# counters per check and final status
		foreach my $check ( sort keys( %{$result->{findings}} )){
			$stats->{repairings}{byFindings}{$check}{$result->{findings}{$check}{status}} //= 0;
			$stats->{repairings}{byFindings}{$check}{$result->{findings}{$check}{status}} += 1;
		}
	}

	return $result;
}

# -------------------------------------------------------------------------------------------------
# When a file has been repaired, verify the result
# (I):
# - the repair results as a hash ref
# (O):
# - the verification results as a hash ref with following keys:

sub fileVerify {
	my ( $repairResult ) = @_;

	my $result = TTP::Media::videoVerify( $repairResult, {
		timeline => $opt_timeline,
		bitstream => $opt_bitstream,
		duration => $opt_duration
	});

	# counters per level
	$stats->{verifyings}{byLevel}{$result->{status}} //= 0;
	$stats->{verifyings}{byLevel}{$result->{status}} += 1;

	# counters per check and final status
	foreach my $check ( sort keys( %{$result->{findings}} )){
		$stats->{verifyings}{byFindings}{$check}{$result->{findings}{$check}{status}} //= 0;
		$stats->{verifyings}{byFindings}{$check}{$result->{findings}{$check}{status}} += 1;
	}

	return $result;
}

# -------------------------------------------------------------------------------------------------
# each path can be either a single filename or a directory
# whether the directory is recursively treated is managed by opt_recurse option

sub doCheckPath {
	msgLog( "doCheckpath() ARGV=[".join( ",", @ARGV )."]" );

	foreach my $path ( @ARGV ){
		TTP::Media::walkTree( $path, {
			recurse => $opt_recurse,
			sub => sub {
				my ( $fname ) = @_;
				checkOrchestration( $fname );
			}
		});
	}

	printSummary();
}

# -------------------------------------------------------------------------------------------------
# Output the execution summary

sub printSummary {

	msgOut( "Summary:" );
	msgOut( "  walked files:    ".sprintf( "%6d", $stats->{walked} ));
	msgOut( "  filtered files:  ".sprintf( "%6d", $stats->{filtered} ));
	msgOut( "  checked files:   ".sprintf( "%6d", $stats->{checked} ));
	msgOut( "  repair attempts: ".sprintf( "%6d", $stats->{repaired} )) if $opt_repair;
	msgOut( "  verified files:  ".sprintf( "%6d", $stats->{verified} )) if $opt_verify;

	printCheckSummary();
	printRepairSummary() if $stats->{repaired} && $stats->{repaired} > 0;
	printVerifySummary() if $stats->{verified} && $stats->{verified} > 0;
}

# -------------------------------------------------------------------------------------------------
# Output the check summary

sub printCheckSummary {

	# when checking, by level
	#                 1         2         3         4         5         6         7         8
	#        12345678901234567890123456789012345678901234567890123456789012345678901234567890
	msgOut( "Checkings:" );
	msgOut( "  By level: " );
	msgOut( "      ".sprintf( "%12s  %12s  %12s", "ERROR", "FINDINGS", "OK" ));
	msgOut( "      ".sprintf( "%12d  %12d  %12d",
		$stats->{checkings}{byLevel}{TTP::Media::Video::ERROR},
		$stats->{checkings}{byLevel}{TTP::Media::Video::FINDINGS},
		$stats->{checkings}{byLevel}{TTP::Media::Video::OK} ));

	# when checking, by check qualifier
	msgOut( "  By check qualifier:" );
	if( $opt_bitstream ){
		msgOut( "    Bitstream:" );
		msgOut( "      ".sprintf( "%12s  %12s  %12s", "SUSPICIOUS", "REPAIRABLE", "OK" ));
		msgOut( "      ".sprintf( "%12d  %12d  %12d",
			$stats->{checkings}{byFindings}{TTP::Media::Video::BITSTREAM}{TTP::Media::Video::SUSPICIOUS},
			$stats->{checkings}{byFindings}{TTP::Media::Video::BITSTREAM}{TTP::Media::Video::REPAIRABLE},
			$stats->{checkings}{byFindings}{TTP::Media::Video::BITSTREAM}{TTP::Media::Video::OK}
		));
	}
	if( $opt_duration > 0 ){
		msgOut( "    Duration:" );
		msgOut( "      ".sprintf( "%12s  %12s  %12s", "", "FAILED", "OK" ));
		msgOut( "      ".sprintf( "%12s  %12d  %12d", "",
			$stats->{checkings}{byFindings}{TTP::Media::Video::DURATION}{TTP::Media::Video::FAILED},
			$stats->{checkings}{byFindings}{TTP::Media::Video::DURATION}{TTP::Media::Video::OK}
		));
	}
	if( $opt_specials ){
		msgOut( "    Special characters:" );
		msgOut( "      ".sprintf( "%12s  %12s  %12s", "", "REPAIRABLE", "OK" ));
		msgOut( "      ".sprintf( "%12s  %12d  %12d", "",
			$stats->{checkings}{byFindings}{TTP::Media::Video::SPECIALS}{TTP::Media::Video::REPAIRABLE},
			$stats->{checkings}{byFindings}{TTP::Media::Video::SPECIALS}{TTP::Media::Video::OK}
		));
	}
	if( $opt_timeline ){
		msgOut( "     Timeline:" );
		msgOut( "      ".sprintf( "%12s  %12s  %12s", "SUSPICIOUS", "REPAIRABLE", "OK" ));
		msgOut( "      ".sprintf( "%12d  %12d  %12d",
			$stats->{checkings}{byFindings}{TTP::Media::Video::TIMELINE}{TTP::Media::Video::SUSPICIOUS},
			$stats->{checkings}{byFindings}{TTP::Media::Video::TIMELINE}{TTP::Media::Video::REPAIRABLE},
			$stats->{checkings}{byFindings}{TTP::Media::Video::TIMELINE}{TTP::Media::Video::OK}
		));
	}
}

# -------------------------------------------------------------------------------------------------
# Output the repair summary summary

sub printRepairSummary {

	# when repairing, by level
	msgOut( "Repairing attempts:" );
	msgOut( "  By level: " );
	msgOut( "      ".sprintf( "%12s  %12s  %12s", "", "ERROR", "OK" ));
	msgOut( "      ".sprintf( "%12s  %12d  %12d", "",
		$stats->{repairings}{byLevel}{TTP::Media::Video::ERROR},
		$stats->{repairings}{byLevel}{TTP::Media::Video::OK} ));

	# when repairing, by check qualifier
	msgOut( "  By check qualifier:" );
	if( $opt_bitstream ){
		msgOut( "    Bitstream:" );
		msgOut( "      ".sprintf( "%12s  %12s  %12s", "TODO", "ERROR", "OK" ));
		msgOut( "      ".sprintf( "%12d  %12d  %12d",
			$stats->{repairings}{byFindings}{TTP::Media::Video::BITSTREAM}{TODO},
			$stats->{repairings}{byFindings}{TTP::Media::Video::BITSTREAM}{TTP::Media::Video::ERROR},
			$stats->{repairings}{byFindings}{TTP::Media::Video::BITSTREAM}{TTP::Media::Video::OK}
		));
	}
	if( $opt_specials ){
		msgOut( "     Specials characters:" );
		msgOut( "      ".sprintf( "%12s  %12s  %12s", "TODO", "ERROR", "OK" ));
		msgOut( "      ".sprintf( "%12d  %12d  %12d",
			$stats->{repairings}{byFindings}{TTP::Media::Video::SPECIALS}{TODO},
			$stats->{repairings}{byFindings}{TTP::Media::Video::SPECIALS}{TTP::Media::Video::ERROR},
			$stats->{repairings}{byFindings}{TTP::Media::Video::SPECIALS}{TTP::Media::Video::OK}
		));
	}
	if( $opt_timeline ){
		msgOut( "     Timeline:" );
		msgOut( "      ".sprintf( "%12s  %12s  %12s", "TODO", "ERROR", "OK" ));
		msgOut( "      ".sprintf( "%12d  %12d  %12d",
			$stats->{repairings}{byFindings}{TTP::Media::Video::TIMELINE}{TODO},
			$stats->{repairings}{byFindings}{TTP::Media::Video::TIMELINE}{TTP::Media::Video::ERROR},
			$stats->{repairings}{byFindings}{TTP::Media::Video::TIMELINE}{TTP::Media::Video::OK}
		));
	}
}

# -------------------------------------------------------------------------------------------------
# Output the verification summary (only for repairable/repaired checks)

sub printVerifySummary {

	# when verifying, by level
	msgOut( "Verifyings:" );
	msgOut( "  By level: " );
	msgOut( "      ".sprintf( "%12s  %12s  %12s", "", "ERROR", "OK" ));
	msgOut( "      ".sprintf( "%12s  %12d  %12d", "",
		$stats->{verifyings}{byLevel}{TTP::Media::Video::ERROR},
		$stats->{verifyings}{byLevel}{TTP::Media::Video::OK} ));

	# when verifying, by check qualifier
	msgOut( "  By check qualifier:" );
	if( $opt_bitstream ){
		msgOut( "    Bitstream:" );
		msgOut( "      ".sprintf( "%12s  %12s  %12s", "", "ERROR", "OK" ));
		msgOut( "      ".sprintf( "%12s  %12d  %12d", "",
			$stats->{verifyings}{byFindings}{TTP::Media::Video::BITSTREAM}{TTP::Media::Video::ERROR},
			$stats->{verifyings}{byFindings}{TTP::Media::Video::BITSTREAM}{TTP::Media::Video::OK}
		));
	}
	if( $opt_specials ){
		msgOut( "     Special characters:" );
		msgOut( "      ".sprintf( "%12s  %12s  %12s", "", "ERROR", "OK" ));
		msgOut( "      ".sprintf( "%12s  %12d  %12d", "",
			$stats->{verifyings}{byFindings}{TTP::Media::Video::SPECIALS}{TTP::Media::Video::ERROR},
			$stats->{verifyings}{byFindings}{TTP::Media::Video::SPECIALS}{TTP::Media::Video::OK}
		));
	}
	if( $opt_timeline ){
		msgOut( "     Timeline:" );
		msgOut( "      ".sprintf( "%12s  %12s  %12s", "", "ERROR", "OK" ));
		msgOut( "      ".sprintf( "%12s  %12d  %12d", "",
			$stats->{verifyings}{byFindings}{TTP::Media::Video::TIMELINE}{TTP::Media::Video::ERROR},
			$stats->{verifyings}{byFindings}{TTP::Media::Video::TIMELINE}{TTP::Media::Video::OK}
		));
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"					=> sub { $ep->runner()->help( @_ ); },
	"colored!"				=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"				=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"				=> sub { $ep->runner()->verbose( @_ ); },
	"recurse!"				=> \$opt_recurse,
	"timeline!"				=> \$opt_timeline,
	"bitstream!"			=> \$opt_bitstream,
	"duration=i"			=> sub {
		my ( $name, $value ) = @_;
		$opt_duration = $value;
		$opt_duration_set = true;
	},
	"specials!"				=> \$opt_specials,
	"repair!"				=> \$opt_repair,
	"keep-orig!"			=> \$opt_keepOrig,
	"verify!"				=> \$opt_verify )){

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
msgVerbose( "got recurse='".( $opt_recurse ? 'true':'false' )."'" );
msgVerbose( "got timeline='".( $opt_timeline ? 'true':'false' )."'" );
msgVerbose( "got bitstream='".( $opt_bitstream ? 'true':'false' )."'" );
msgVerbose( "got duration='$opt_duration'" );
msgVerbose( "got specials='".( $opt_specials ? 'true':'false' )."'" );
msgVerbose( "got repair='".( $opt_repair ? 'true':'false' )."'" );
msgVerbose( "got keep-orig='".( $opt_keepOrig ? 'true':'false' )."'" );
msgVerbose( "got verify='".( $opt_verify ? 'true':'false' )."'" );

if( scalar( @ARGV )){
	msgVerbose( "got sources=[".join( ',', @ARGV )."]" );
} else {
	msgErr( "at least one file or directory is expected as (a) positional argument(s)" );
}

if( $opt_duration_set ){
	if( $opt_duration <= 0 ){
		msgVerbose( "duration='$opt_duration' less or equal to zero, disabling the duration check" );
	}
}

# verify is only valid with repair
if( $opt_verify && !$opt_repair ){
	msgWarn( "'--verify' option is only relevant when '--repair' is requested" );
}

TTP::Media::checkFFmpeg() if $opt_bitstream;
TTP::Media::checkFFprobe() if $opt_bitstream || $opt_duration > 0 || $opt_timeline;
TTP::Media::checkGstDiscoverer() if $opt_timeline;
TTP::Media::checkGstLaunch() if $opt_timeline && $opt_repair;

if( !TTP::errs()){
	if( $opt_bitstream || $opt_duration > 0 || $opt_timeline || $opt_specials ){
		doCheckPath();
	} else {
		msgWarn( "cowardly refuse to not do something" );
	}
}

TTP::exit();
