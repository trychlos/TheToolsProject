# @(#) display a configuration variable on stdout
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --service=<name>        display informations about the named service [${service}]
# @(-) --key=<name[,...]>      a comma-separated list of keys to reach the desired value, may be specified several times [${key}]
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

use TTP::Service;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	service => '',
	key => ''
};

my $opt_service = $defaults->{service};
my @opt_keys = ();

# -------------------------------------------------------------------------------------------------
# Display the value accessible through the route of the provided successive keys

sub listByKeys {
	my $service = undef;
	$service = TTP::Service->new( $ep, { service => $opt_service }) if $opt_service;
	my $value = TTP::Service::serviceVar( \@opt_keys, { service => $service });
	print "  [".join( ',', @opt_keys )."]: ".( defined( $value ) ? ( ref( $value ) ? Dumper( $value ) : $value.EOL ) : "(undef)".EOL );
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> sub { $ep->runner()->help( @_ ); },
	"colored!"			=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"			=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"			=> sub { $ep->runner()->verbose( @_ ); },
	"service=s"			=> \$opt_service,
	"key=s@"			=> \@opt_keys )){

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
msgVerbose( "got service='$opt_service'" );
@opt_keys = split( /,/, join( ',', @opt_keys ));
msgVerbose( "got keys='".join( ',', @opt_keys )."'" );

# warn if no option has been requested
msgWarn( "no '--key' option has been provided, nothing to do" ) if !scalar( @opt_keys );

if( !TTP::errs()){
	listByKeys() if scalar @opt_keys;
}

TTP::exit();
