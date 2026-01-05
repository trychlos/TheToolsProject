# @(#) clear a hierarchy of (retained) MQTT topics
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --topic=<name>          the topic to publish in [${topic}]
# @(-) --[no]check             check that the topics have been successfully cleared [${check}]
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

use TTP::MQTT;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	topic => '',
	check => 'yes'
};

my $opt_topic = $defaults->{topic};
my $opt_check = true;

# -------------------------------------------------------------------------------------------------
# clear the existing topics

sub doClear {
	msgOut( "clearing '$opt_topic' hierarchy..." );

	my $total_count = 0;
	my $cleared_count = 0;
	my $success_count = 0;

	if( $ep->runner()->dummy()){
		msgDummy( "considering clear successful" );

	} else {
		# get all the retained topics
		msgOut( "getting retained messages..." );
		my ( $retained, $cleared ) = _filter_retained();
		$total_count = scalar( @{$retained} );
		$cleared_count = scalar( @{$cleared} );
		msgOut( "got $total_count total retained message(s)" );
		msgOut( "filtered $cleared_count to be cleared message(s)" );
		if( $cleared_count ){
			# clear the to-be-cleared topics
			foreach my $it ( @{$cleared} ){
				msgVerbose( "clearing '$it' message" );
				my $res = TTP::commandExec( "mqtt.pl publish -topic $it -payload \"\" -retain -nocolored" );
				if( $res->{success} ){
					$success_count += 1;
				}
			}
			msgOut( "successfully cleared $success_count message(s)" );
			if( $cleared_count == $success_count ){
				# check if asked for
				if( $opt_check ){
					msgOut( "checking among still retained messages..." );
					my ( $retained, $cleared ) = _filter_retained();
					my $checked_count = scalar( @{$cleared} );
					if( $checked_count == 0 ){
						msgOut( "found $checked_count remaining (not cleared) messages: fine" );
					} else {
						msgErr( "got $checked_count remaining (not cleared) messages" );
					}
				}
			} else {
				msgErr( "remaining messages:" );
				my ( $retained, $cleared ) = _filter_retained();
				foreach my $it ( @{$cleared} ){
					msgErr( " $it" );
				}
			}
		}
	}
	if( TTP::errs()){
		msgErr( "NOT OK" );
	} else {
		msgOut( $cleared_count ? "done" : "nothing to do" );
	}
}

# get the retained messages, filtering them out
# returns the lists of all retained and to-be-cleared messages

sub _filter_retained {
	my $retained = TTP::filter( "mqtt.pl retained -get -nocolored" );
	my $cleared = [];
	# filter the to-be-cleared topics with an insensitive case match
	foreach my $it ( @{${retained}} ){
		if( $it =~ /^$opt_topic/i ){
			my @words = split( /\s+/, $it );
			push( @{$cleared}, $words[0] );
		}
	}
	return ( $retained, $cleared );
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> sub { $ep->runner()->help( @_ ); },
	"colored!"			=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"			=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"			=> sub { $ep->runner()->verbose( @_ ); },
	"topic=s"			=> \$opt_topic,
	"check!"			=> \$opt_check )){

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
msgVerbose( "got topic='$opt_topic'" );
msgVerbose( "got check='".( $opt_check ? 'true':'false' )."'" );

# topic is mandatory
msgErr( "topic is required, but is not specified" ) if !$opt_topic;

if( !TTP::errs()){
	doClear();
}

TTP::exit();
