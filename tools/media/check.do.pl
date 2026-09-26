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
# @(-) --[no]repair                 whether try to repair the REPAIRABLE media [${repair}]
# @(-) --[no]verify                 whether verify the repaired media [${verify}]
#
# @(@) Note 1: The verb accepts one or more files or directories as positional arguments.
# @(@) Note 2: In dummy mode, candidate files are only displayed and no media check is performed.
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

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	recurse => 'yes',
	timeline => 'yes',
	bitstream => 'yes',
	duration => -1,
	repair => 'no',
	verify => 'no'
};

my $opt_recurse = true;
my $opt_timeline = true;
my $opt_bitstream = true;
my $opt_duration = $defaults->{duration};
my $opt_repair = false;
my $opt_verify = false;

my $stats = {
	walked => 0,
	filtered => 0,
	checked => 0,
	repaired_count => 0,
	verified_count => 0,
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
		TIMELINE => {
			OK => 0,
			SUSPICIOUS => 0,
			REPAIRABLE => 0
		}
	},
	repaired => {
		BITSTREAM => {
			OK => 0,
			ERROR => 0
		},
		TIMELINE => {
			OK => 0,
			ERROR => 0
		}
	},
	verified => {
		BITSTREAM => {
			OK => 0,
			ERROR => 0
		},
		TIMELINE => {
			OK => 0,
			ERROR => 0
		}
	}
};

my $opt_duration_set = false;

# -------------------------------------------------------------------------------------------------
# Process a candidate file

sub checkFile {
	my ( $fname ) = @_;

	# all files are counted in 'walked'
	$stats->{walked} += 1;

	# only videos are counted in 'filtered'
	return if !TTP::Media::isVideoCapable( $fname );
	$stats->{filtered} += 1;

	# check unless dummy mode
	if( $ep->runner()->dummy()){
		msgDummy( "would check: $fname" );
		return;
	}

	$stats->{checked} += 1;
	msgVerbose( "checking '$fname'..." );

	my $result = TTP::Media::checkVideo( $fname, {
		timeline => $opt_timeline,
		bitstream => $opt_bitstream,
		duration => $opt_duration
	});

	# file-level summary
	msgOut( sprintf( "%-8s %s", $result->{status}, $fname ));
	if( $result->{status} ne TTP::Media::OK ){
		# if error
		foreach my $reason ( @{$result->{reasons}} ){
			msgOut( sprintf( "%-8s %s", " ", sprintf( $reason->{format}, @{$reason->{args} // [] })));
		}
		# for findings
		foreach my $key ( sort keys( %{$result->{findings}} )){
			foreach my $reason ( @{$result->{findings}{$key}{reasons}} ){
				msgOut( sprintf( "%-8s %s", " ", sprintf( $reason->{format}, @{$reason->{args} // [] })));
			}
		}
	}

	# counters per level
	$stats->{byLevel}{$result->{status}} //= 0;
	$stats->{byLevel}{$result->{status}} += 1;

	# counters per check and final status
	foreach my $check ( sort keys( %{$result->{findings}} )){
		$stats->{byFindings}{$check}{$result->{findings}{$check}{status}} //= 0;
		$stats->{byFindings}{$check}{$result->{findings}{$check}{status}} += 1;
	}

	# if repair is asked ?
	if( $opt_repair ){
		if(( $opt_bitstream && $result->{findings}{TTP::Media::BITSTREAM}{status} eq TTP::Media::REPAIRABLE ) ||
			( $opt_timeline && $result->{findings}{TTP::Media::TIMELINE}{status} eq TTP::Media::REPAIRABLE )){

			$stats->{repaired_count} += 1;
			my $repaired = TTP::Media::repairVideo( $fname, $result );

			# repair counters
			foreach my $check ( sort keys( %{$repaired->{findings}} )){
				$stats->{repaired}{$check}{$repaired->{findings}{$check}{status}} //= 0;
				$stats->{repaired}{$check}{$repaired->{findings}{$check}{status}} += 1;
			}

			if( $repaired->{status} ne TTP::Media::ERROR && $opt_verify ){
				$stats->{verified_count} += 1;
				my $verified = TTP::Media::checkVideo( $repaired->{fname}, {
					timeline => $opt_timeline,
					bitstream => $opt_bitstream,
					duration => $opt_duration
				});
			}
		}
	}
}

# -------------------------------------------------------------------------------------------------
# each path can be either a single filename or a directory
# whether the directory is recursively treated is managed by opt_recurse option

sub checkPath {
	foreach my $path ( @ARGV ){
		TTP::Media::walkTree( $path, {
			recurse => $opt_recurse,
			sub => sub {
				my ( $fname ) = @_;
				checkFile( $fname );
			}
		});
	}
	# print a summary
	msgOut( "Summary:" );
	msgOut( "  walked files:    ".sprintf( "%6d", $stats->{walked} ));
	msgOut( "  filtered files:  ".sprintf( "%6d", $stats->{filtered} ));
	msgOut( "  checked files:   ".sprintf( "%6d", $stats->{checked} ));
	msgOut( "  repair attempts: ".sprintf( "%6d", $stats->{repaired_count} )) if $opt_repair;
	msgOut( "  verified files:  ".sprintf( "%6d", $stats->{verified_count} )) if $opt_verify;
	# by level
	msgOut( "By level:          ERROR    FINDINGS          OK" );
	msgOut( "  ".sprintf( "%-10s      %6d      %6d      %6d", " ",
		$stats->{byLevel}{TTP::Media::ERROR},
		$stats->{byLevel}{TTP::Media::FINDINGS},
		$stats->{byLevel}{TTP::Media::OK} ));
	# by check
	msgOut( "By check:" );
	if( $opt_bitstream ){
		msgOut( "  BITSTREAM   SUSPICIOUS  REPAIRABLE          OK" );
		msgOut( "  ".sprintf( "%-10s      %6d      %6d      %6d", " ",
			$stats->{byFindings}{TTP::Media::BITSTREAM}{TTP::Media::SUSPICIOUS},
			$stats->{byFindings}{TTP::Media::BITSTREAM}{TTP::Media::REPAIRABLE},
			$stats->{byFindings}{TTP::Media::BITSTREAM}{TTP::Media::OK}
		));
	}
	if( $opt_duration > 0 ){
		msgOut( "  DURATION                    FAILED          OK" );
		msgOut( "  ".sprintf( "%-10s                  %6d      %6d", " ",
			$stats->{byFindings}{TTP::Media::DURATION}{TTP::Media::FAILED},
			$stats->{byFindings}{TTP::Media::DURATION}{TTP::Media::OK}
		));
	}
	if( $opt_timeline ){
		msgOut( "  TIMELINE    SUSPICIOUS  REPAIRABLE          OK" );
		msgOut( "  ".sprintf( "%-10s      %6d      %6d      %6d", " ",
			$stats->{byFindings}{TTP::Media::TIMELINE}{TTP::Media::SUSPICIOUS},
			$stats->{byFindings}{TTP::Media::TIMELINE}{TTP::Media::REPAIRABLE},
			$stats->{byFindings}{TTP::Media::TIMELINE}{TTP::Media::OK}
		));
	}
	# when repairing
	if( $opt_repair ){
		msgOut( "Repaired:           TODO       ERROR          OK" );
		foreach my $check ( sort keys( %{$stats->{repaired}} )){
			if(( $check eq 'BITSTREAM' && $opt_bitstream ) || ( $check eq 'TIMELINE' && $opt_timeline )){
				msgOut( "  ".
					sprintf( "%-10s      %6d      %6d      %6d",
						$check,
						$stats->{byFindings}{$check}{TTP::Media::REPAIRABLE},
						$stats->{repaired}{$check}{TTP::Media::ERROR},
						$stats->{repaired}{$check}{TTP::Media::OK} ));
			}
		}
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
	"repair!"				=> \$opt_repair,
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
msgVerbose( "got repair='".( $opt_repair ? 'true':'false' )."'" );
msgVerbose( "got verify='".( $opt_verify ? 'true':'false' )."'" );

if( scalar( @ARGV )){
	msgVerbose( "got sources=[".join( ',', @ARGV )."]" );
} else {
	msgErr( "at least one file or directory is expected as (a) positional argument(s)" );
}

if( $opt_duration_set ){
	if( $opt_duration <= 0 ){
		msgErr( "invalid duration '$opt_duration': must be greater than zero" );
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
	if( $opt_bitstream || $opt_duration > 0 || $opt_timeline ){
		checkPath();
	} else {
		msgWarn( "cowardly refuse to not do something" );
	}
}

TTP::exit();
