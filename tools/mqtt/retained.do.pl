# @(#) get the MQTT retained available messages
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]get               get the messages [${get}]
# @(-) --wait=<time>           timeout to wait for messages [${wait}]
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

use Time::Moment;

use TTP::MQTT;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	get => 'no',
	wait => 5
};

my $opt_get = false;
my $opt_wait = $defaults->{wait};

# the MQTT connection
my $last = 0;
my $count = 0;

# -------------------------------------------------------------------------------------------------
# get and output the retained messages
#  default to wait 5 sec after last received message before disconnecting..

sub doGetRetained {
	msgOut( "getting the retained messages..." );

	my $mqtt = TTP::MQTT::connect();
	if( $mqtt ){
		my $loop = true;
		$mqtt->subscribe( '#' => \&doWork );
		msgVerbose( "subscribed to '#'" );
		while( $loop ){
			$mqtt->tick( 1 );
			msgVerbose( "after tick" );
			if( $last ){
				my $now = Time::Moment->now->epoch;
				if( $now - $last > $opt_wait ){
					$loop = false;
				}
			} else {
				$last = Time::Moment->now->epoch;
				sleep( 1 );
			}
		}
		TTP::MQTT::disconnect( $mqtt );
	}
	my $result = true;
	if( $result ){
		msgOut( "success: $count got messages" );
	} else {
		msgErr( "NOT OK" );
	}
}

# -------------------------------------------------------------------------------------------------
# triggered on the published message

sub doWork {
	my ( $topic, $payload, $retain ) = @_;
	if( $retain ){
		print "$topic $payload".EOL;
		msgLog( "$topic $payload" );
		$last = Time::Moment->now->epoch;
		$count += 1;
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
	"get!"				=> \$opt_get,
	"wait=i"			=> \$opt_wait )){

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
msgVerbose( "got get='".( $opt_get ? 'true':'false' )."'" );
msgVerbose( "got wait='$opt_wait'" );

if( !TTP::errs()){
	doGetRetained() if $opt_get;
}

TTP::exit();
