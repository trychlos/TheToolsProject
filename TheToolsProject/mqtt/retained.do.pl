# @(#) get the MQTT retained available messages
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]get               get the messages [${get}]
# @(-) --wait=<time>           timeout to wait for messages [${wait}]
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

use utf8;
use strict;
use warnings;

use Time::Piece;

use TTP::MQTT;
my $running = $ep->runner();

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
my $mqtt = undef;
my $loop = true;
my $last = 0;
my $count = 0;

# -------------------------------------------------------------------------------------------------
# get and output the retained messages

sub doGetRetained {
	msgOut( "getting the retained messages..." );

	$mqtt = TTP::MQTT::connect();
	if( $mqtt ){
		$mqtt->subscribe( '#' => \&doWork );
		while( $loop ){
			$mqtt->tick( 1 );
			my $now = localtime->epoch;
			if( $last && $now - $last > $opt_wait ){
				$loop = false;
			} else {
				sleep( 1 );
			}
		}
	}
	TTP::MQTT::disconnect( $mqtt );
	my $result = true;
	if( $result ){
		msgOut( "success: $count got messages" );
	} else {
		msgErr( "NOT OK" );
	}
}

# -------------------------------------------------------------------------------------------------
# triggered on the published message
#  wait 2sec after last received before disconnecting..
sub doWork {
	my ( $topic, $payload, $retain ) = @_;
	if( $retain ){
		print "$topic $payload".EOL;
		msgLog( "$topic $payload" );
		$last = localtime->epoch;
		$count += 1;
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$ep->{run}{help},
	"colored!"			=> \$ep->{run}{colored},
	"dummy!"			=> \$ep->{run}{dummy},
	"verbose!"			=> \$ep->{run}{verbose},
	"get!"				=> \$opt_get,
	"wait=i"			=> \$opt_wait )){

		msgOut( "try '".$running->command()." ".$running->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $running->help()){
	$running->verbHelp( $defaults );
	TTP::exit();
}

msgVerbose( "got colored='".( $running->colored() ? 'true':'false' )."'" );
msgVerbose( "got dummy='".( $running->dummy() ? 'true':'false' )."'" );
msgVerbose( "got verbose='".( $running->verbose() ? 'true':'false' )."'" );
msgVerbose( "got get='".( $opt_get ? 'true':'false' )."'" );
msgVerbose( "got wait='$opt_wait'" );

if( !TTP::errs()){
	doGetRetained() if $opt_get;
}

TTP::exit();
