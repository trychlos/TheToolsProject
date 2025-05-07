# @(#) publish a Meteor package
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]github            publish to Github [${github}]
# @(-) --[no]meteor            publish to Meteor repository [${meteor}]
# @(-) --[no]create            whether this is a new package creation [${create}]
# @(-) --[no]update            or whether this is an existing package update [${update}]
#
# @(@) The topic should be formatted as HOST/subject/subject/content
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
	github => 'no',
	meteor => 'no',
	create => 'no',
	update => 'no'
};

my $opt_github = false;
my $opt_meteor = false;
my $opt_create = false;
my $opt_update = false;

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
	"github!"			=> \$opt_github,
	"meteor!"			=> \$opt_meteor,
	"create!"			=> \$opt_create,
	"update!"			=> \$opt_update )){

		msgOut( "try '".$ep->runner()->command()." ".$ep->runner()->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $ep->runner()->help()){
	$ep->runner()->displayHelp( $defaults );
	TTP::exit();
}

msgVerbose( "found colored='".( $ep->runner()->colored() ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $ep->runner()->dummy() ? 'true':'false' )."'" );
msgVerbose( "found verbose='".( $ep->runner()->verbose() ? 'true':'false' )."'" );
msgVerbose( "found github='".( $opt_github ? 'true':'false' )."'" );
msgVerbose( "found meteor='".( $opt_meteor ? 'true':'false' )."'" );
msgVerbose( "found create='".( $opt_create ? 'true':'false' )."'" );
msgVerbose( "found update='".( $opt_update ? 'true':'false' )."'" );

# should publish to at least one target
msgWarn( "will do not publish anything as both '--meteor' and 'github' are false" ) if !$opt_meteor && !$opt_github;
# must specify either a creation or an update
my $count = 0;
$count += 1 if $opt_create;
$count += 1 if $opt_update;
msgErr( "must specify either '--create' or '--update' option" ) if $count != 1;

if( !TTP::errs()){
	doPublish();
}

TTP::exit();
