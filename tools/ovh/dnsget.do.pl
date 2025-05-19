# @(#) display the definition of the specified DNS domain or record
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --name=<name>           the requested DNS name [${name}]
#
# @(@) Note 1: this verb let us request either a DNS domain content as the list of records, or the definition of a particular record.
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

use TTP::Ovh;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	name => '[name.]example.com'
};

my $opt_name = $defaults->{name};

# -------------------------------------------------------------------------------------------------
# display the name DNS definition
# /domain returns an array of managed domain names: "[ 'blingua.eu', 'blingua.fr', 'blingua.net' ]"

sub doGetName {
	msgOut( "display '$opt_name' definition..." );
	my $res = false;
	my $count = 0;

	my $api = TTP::Ovh::connect();
	if( $api ){
		# get the domain (last two dot-separated words)
		my @w = split( /\./, $opt_name );
		my $domain = $w[scalar( @w )-2].'.'.$w[scalar( @w )-1];
		my $subdomain = $opt_name;
		$subdomain =~ s/$domain$//;
		$subdomain =~ s/\.$//;
		# get the array of records internal ids
		my $result = TTP::Ovh::getContentByPath( $api, "/domain/zone/$domain/record" );
		if( defined( $result )){
			my $records = [];
			foreach my $it ( @{$result} ){
				my $def = TTP::Ovh::getContentByPath( $api, "/domain/zone/$domain/record/$it" );
				push( @{$records}, $def ) if !$subdomain || $def->{subDomain} eq $subdomain;
			}
			if( scalar( @{$records} > 1 )){
				TTP::displayTabular( $records );
			} elsif( scalar( @{$records} ) == 1 ){
				foreach my $it ( sort keys %{$records->[0]} ){
					print " $it: $records->[0]->{$it}".EOL;
				}
			} else {
				msgWarn( "empty result set" );
			}
			$res = true;
			$count = scalar( @{$records} );
		} else {
			msgErr( "got undefined result, most probably '$opt_name' is not a managed domain name" );
		}
	}

	if( $res ){
		msgOut( "found $count record(s), success" );
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
	"name=s"			=> \$opt_name )){

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
msgVerbose( "got name='$opt_name'" );

# the requested DNS name is mandatory
# when set, make sure we have at least a domain
if( $opt_name ){
	my @w = split( /\./, $opt_name );
	if( scalar( @w ) < 2 ){
		msgErr( "must have at least a 'a.b' name, found '$opt_name'" );
	}
} else {
	msgErr( "'--name' option must be specified, none found" );
}

if( !TTP::errs()){
	doGetName();
}

TTP::exit();
