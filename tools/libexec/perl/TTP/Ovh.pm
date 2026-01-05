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
#
# OVH API Access

package TTP::Ovh;
die __PACKAGE__ . " must be loaded as TTP::Ovh\n" unless __PACKAGE__ eq 'TTP::Ovh';

use strict;
use utf8;
use warnings;

use Data::Dumper;
use File::Spec;

use TTP;
use TTP::Constants qw( :all );
use TTP::Credentials;
use TTP::Message qw( :all );
use TTP::OvhApi;

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - an opaque handle on the OVH API connection

sub connect {
	my $credentials = TTP::Credentials::find( 'ovh.ini' );
	msgVerbose( "Ovh::connect() credentials='".( $credentials ? $credentials : '(undef)' )."'" );
	my $api = undef;
	if( $credentials ){
		$api = TTP::OvhApi->new(
			timeout => 10,
			credentials => $credentials
		);
	}
	return $api;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - the api opaque handle as returned from connect()
# - a path to request
# - an optional options hash with following keys:
#   > printAnswer, defaulting to false
# (O):
# - the request answer as a OvhAnswer instance

sub getAnswerByPath {
	my ( $api, $path, $opts ) = @_;
	$opts //= {};
	msgVerbose( "Ovh::getAnswerByPath() path='$path'" );

	my $answer = $api->get( path => $path );
	my $printAnswer = false;
	$printAnswer = $opts->{printAnswer} if defined $opts->{printAnswer};
	print Dumper( $answer ) if $printAnswer;

	msgVerbose( "Ovh::getAnswerByPath() status=".$answer->status()." isSuccess='".( $answer->isSuccess() ? 'true' : 'false' )."'");
	return $answer;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - the api opaque handle as returned from connect()
# - a path to request
# - an optional options hash with following keys:
#   > printAnswer, defaulting to false
# (O):
# - a ref to the answer content, or undef

sub getContentByPath {
	my ( $api, $path, $opts ) = @_;
	$opts //= {};
	my $res = undef;

	my $answer = getAnswerByPath( $api, $path, $opts );
	if( $answer->isSuccess()){
		$res = $answer->content();
	} else {
		msgLog( Dumper( $answer ));
	}

	return $res;
}

# ------------------------------------------------------------------------------------------------
# returns the list of subscribed services
# Makes use of '/service' API
# As of 2024-03-05, '/services' API is in beta mode and returns some garbage
# (I):
# - the api opaque handle as returned from connect()
# (O):
# - a ref to an array of hashes which contains subscribed services, sorted by ascending ID's
#   may be empty
#   suitable to TTP::displayTabular()

sub getServices {
	my ( $api ) = @_;
	my $res = [];

	my $url = '/service';
	my $list = getContentByPath( $api, $url );
	if( scalar @{$list} ){
		foreach my $it ( sort { $a <=> $b } @{$list} ){
			my $hash = getContentByPath( $api, "$url/$it" );
			$hash->{id} = $it;
			push( @{$res}, $hash );
		}
	}

	return $res;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - the api opaque handle as returned from connect()
# - a path to request
# - the POST parameters as a hash
# (O):
# - the request answer as a OvhAnswer instance

sub postByPath {
	my ( $api, $path, $params ) = @_;
	msgVerbose( "Ovh::postByPath() path='$path'" );

	my $answer = $api->post( path => $path, body => $params );
	print Dumper( $answer ) if $answer->isFailure();

	msgVerbose( "Ovh::postByPath() status=".$answer->status()." isSuccess='".( $answer->isSuccess() ? 'true' : 'false' )."'");
	return $answer;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - the api opaque handle as returned from connect()
# - a path to request
# - the PUT parameters as a hash
# (O):
# - the request answer as a OvhAnswer instance

sub putByPath {
	my ( $api, $path, $params ) = @_;
	msgVerbose( "Ovh::putByPath() path='$path'" );

	my $answer = $api->put( path => $path, body => $params );
	print Dumper( $answer ) if $answer->isFailure();

	msgVerbose( "Ovh::putByPath() status=".$answer->status()." isSuccess='".( $answer->isSuccess() ? 'true' : 'false' )."'");
	return $answer;
}

1;
