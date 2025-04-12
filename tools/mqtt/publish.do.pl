# @(#) publish a message on a MQTT topic
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --topic=<name>          the topic to publish in [${topic}]
# @(-) --payload=<name>        the message to be published [${payload}]
# @(-) --[no]retain            with the 'retain' flag (ignored here) [${retain}]
#
# @(@) The topic should be formatted as HOST/subject/subject/content
#
# The Tools Project - Tools System and Working Paradigm for IT Production
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
	payload => '',
	retain => 'no'
};

my $opt_topic = $defaults->{topic};
my $opt_payload = undef;
my $opt_retain = false;

# -------------------------------------------------------------------------------------------------
# publish the message

sub doPublish {
	msgOut( "publishing '$opt_topic [$opt_payload]'..." );
	my $result = false;

	if( $ep->runner()->dummy()){
		msgDummy( "considering publication successful" );
		$result = true;
	} else {
		my $mqtt = TTP::MQTT::connect();
		if( $mqtt ){
			$opt_payload //= "";
			if( $opt_retain ){
				$mqtt->retain( $opt_topic, $opt_payload );
			} else {
				$mqtt->publish( $opt_topic, $opt_payload );
			}
			TTP::MQTT::disconnect( $mqtt );
			$result = true;
		}
	}
	if( $result ){
		msgOut( "success" );
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
	"payload=s"			=> \$opt_payload,
	"retain!"			=> \$opt_retain	)){

		msgOut( "try '".$ep->runner()->command()." ".$ep->runner()->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $ep->runner()->help()){
	$ep->runner()->verbHelp( $defaults );
	TTP::exit();
}

msgVerbose( "got colored='".( $ep->runner()->colored() ? 'true':'false' )."'" );
msgVerbose( "got dummy='".( $ep->runner()->dummy() ? 'true':'false' )."'" );
msgVerbose( "got verbose='".( $ep->runner()->verbose() ? 'true':'false' )."'" );
msgVerbose( "got topic='$opt_topic'" );
msgVerbose( "got payload='$opt_payload'" );
msgVerbose( "got retain='".( $opt_retain ? 'true':'false' )."'" );

# topic is mandatory
msgErr( "topic is required, but is not specified" ) if !$opt_topic;
msgWarn( "payload is empty, but shouldn't" ) if !defined $opt_payload;

if( !TTP::errs()){
	doPublish();
}

TTP::exit();
