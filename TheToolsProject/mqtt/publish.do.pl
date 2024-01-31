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

	if( $running->dummy()){
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
	"help!"				=> \$ttp->{run}{help},
	"colored!"			=> \$ttp->{run}{colored},
	"dummy!"			=> \$ttp->{run}{dummy},
	"verbose!"			=> \$ttp->{run}{verbose},
	"topic=s"			=> \$opt_topic,
	"payload=s"			=> \$opt_payload,
	"retain!"			=> \$opt_retain	)){

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
msgVerbose( "found topic='$opt_topic'" );
msgVerbose( "found payload='$opt_payload'" );
msgVerbose( "found retain='".( $opt_retain ? 'true':'false' )."'" );

# topic is mandatory
msgErr( "topic is required, but is not specified" ) if !$opt_topic;
msgWarn( "payload is empty, but shouldn't" ) if !defined $opt_payload;

if( !TTP::errs()){
	doPublish();
}

TTP::exit();
