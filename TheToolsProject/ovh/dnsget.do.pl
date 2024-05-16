# @(#) display the definition of the specified DNS domain or record
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --name=<name>           the requested DNS name [${name}]
#
# @(@) This verb let us request either a DNS domain content as the list of records, or the definition of a particular record.
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
		msgErr( "NOT OK" );
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
	"name=s"			=> \$opt_name )){

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
msgVerbose( "found name='$opt_name'" );

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
