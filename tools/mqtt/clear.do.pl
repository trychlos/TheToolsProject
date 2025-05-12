# @(#) clear a hierarchy of (retained) MQTT topics
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --topic=<name>          the topic to publish in [${topic}]
# @(-) --[no]check             check that the topics have been successfully cleared
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
	my $result = false;
	my $total_count = 0;
	my $cleared_count = 0;
	my $success_count = 0;
	my $checked_count = -1;

	if( $ep->runner()->dummy()){
		msgDummy( "considering clear successful" );
		$result = true;
	} else {
		# get all the retained topics
		my $retained = TTP::filter( "mqtt.pl retained -get -nocolored" );
		my $cleared = [];
		# filter the to-be-cleared topics
		foreach my $it ( @{${retained}} ){
			$total_count += 1;
			if( $it =~ /^$opt_topic/ ){
				push( @{$cleared}, $it );
				$cleared_count += 1;
			}
		}
		# clear the to-be-cleared topics
		foreach my $it ( @{$cleared} ){
			my $res = TTP::commandExec( "mqtt.pl publish -topic $it -payload \"\" -retain -nocolored" );
			if( $res->{success} ){
				$success_count += 1;
			}
		}
		# check if asked for
		if( $opt_check ){
			$checked_count = 0;
			$retained = TTP::filter( "mqtt.pl retained -get -nocolored" );
			foreach my $it ( @{${retained}} ){
				if( $it =~ /^$opt_topic/ ){
					push( @{$cleared}, $it );
					$checked_count += 1;
				}
			}
		}
	}
	msgOut( "got $cleared_count of $total_count total retained topics, among them $success_count have been successfully cleared" );
	if( $opt_check ){
		if( $checked_count == 0 ){
			msgOut( "check fully successful" );
		} else {
			msgErr( "got $checked_count remaining (not cleared) topics" );
		}
	}
	if( $result ){
		msgOut( "done" );
	} else {
		msgErr( "NOT OK" );
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
