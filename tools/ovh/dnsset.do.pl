# @(#) update the DNS record definition
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --record=<record>       the requested DNS record to update [${record}]
# @(-) --target=<target>       the new target of the record [${target}]
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

use TTP::Ovh;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	record => 'name.example.com',
	target => ''
};

my $opt_record = $defaults->{record};
my $opt_target = $defaults->{target};

# -------------------------------------------------------------------------------------------------
# update the record DNS definition

sub doSetRecord {
	msgOut( "update '$opt_record' record definition..." );
	my $res = false;

	my $api = TTP::Ovh::connect();
	if( $api ){
		# get the domain (last two dot-separated words)
		my @w = split( /\./, $opt_record );
		my $domain = $w[scalar( @w )-2].'.'.$w[scalar( @w )-1];
		my $subdomain = $opt_record;
		$subdomain =~ s/$domain$//;
		$subdomain =~ s/\.$//;
		# get the array of records internal ids
		my $result = TTP::Ovh::getContentByPath( $api, "/domain/zone/$domain/record" );
		if( defined( $result )){
			my $record = undef;
			foreach my $it ( @{$result} ){
				my $def = TTP::Ovh::getContentByPath( $api, "/domain/zone/$domain/record/$it" );
				if( $def->{subDomain} eq $subdomain ){
					$record = $def;
					last;
				}
			}
			if( defined $record ){
				msgVerbose( "updating $domain" );
				my $answer = TTP::Ovh::putByPath( $api, "/domain/zone/$domain/record/$record->{id}", { target => $opt_target });
				if( $answer->isSuccess()){
					msgVerbose( "refreshing $domain" );
					$answer = TTP::Ovh::postByPath( $api, "/domain/zone/$domain/refresh" );
					$res = $answer->isSuccess();
				}
			} else {
				msgErr( "'$opt_record' record is not found in the domain" );
			}
		} else {
			msgErr( "got undefined result, most probably '$opt_record' doesn't belong to a managed domain" );
		}
	}

	if( $res ){
		msgOut( "success" );
	} else {
		msgErr( "NOT OK", { incErr => false });
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
	"record=s"			=> \$opt_record,
	"target=s"			=> \$opt_target	)){

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
msgVerbose( "got record='$opt_record'" );
msgVerbose( "got target='$opt_target'" );

# the to-be-updated reoord is mandatory, must have at least a subdomain
if( $opt_record ){
	my @w = split( /\./, $opt_record );
	if( scalar( @w ) < 3 ){
		msgErr( "must have at least a 'a.b.c' record name, found '$opt_record'" );
	}
} else {
	msgErr( "'--record' option must be specified, none found" );
}
# the target must either be an IPv4 address or a dot-terminated name
if( $opt_target ){
	if( $opt_target =~ m/[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/ ){
		msgVerbose( "target matches an IPv4 address, fine" );
	} else {
		my @w = split( /\./, $opt_target );
		if( scalar( @w ) < 3 ){
			msgErr( "must have at least a 'a.b.c.' record name, found '$opt_target'" );
		} elsif( $opt_target =~ m/\.$/ ){
			msgVerbose( "target is dot-terminated, fine" );
		} else {
			msgErr( "target must be a valid, dot-terminated, domain name, found '$opt_target'" );
		}
	}
} else {
	msgErr( "'--target' option must be specified, none found" );
}

if( !TTP::errs()){
	doSetRecord();
}

TTP::exit();
