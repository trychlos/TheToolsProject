# @(#) execute the specified commands for a service
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --service=<name>        acts on the named service [${service}]
# @(-) --key=<name[,...]>      the key to be searched for in JSON configuration file, may be specified several times or as a comma-separated list [${key}]
#
# @(@) The specified keys must eventually address an array of the to-be-executed commands or a single command string.
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
# execute the commands registered for the service for the specified key(s)

my $count = 0;

sub executeCommands {
	msgOut( "executing '$opt_service [".join( ',', @opt_keys )."]' commands..." );
	my $cmdCount = 0;
	my $service = TTP::Service->new( $ep, { service => $opt_service });
	if( $service ){
		# addressed value can be a scalar or an array of scalars
		my $value = $service->var( \@opt_keys );
		if( $value && $value->{commands} ){
			_execute( $service, $value->{commands} );
		} else {
			msgErr( "unable to find the requested information" );
		}
	}
	if( TTP::errs()){
		msgErr( "NOT OK", { incErr => false });
	} else {
		msgOut( "$count executed command(s)" );
	}
}

# -------------------------------------------------------------------------------------------------
# execute the commands registered for the service for the specified key(s)

sub _execute {
	my ( $service, $value ) = @_;
	my $ref = ref( $value );
	if( $ref eq 'ARRAY' ){
		foreach my $it ( @{$value} ){
			_execute( $service, $it );
		}
	} elsif( !$ref ){
		if( $ep->runner()->dummy()){
			msgDummy( $value );
		} else {
			msgOut( " $value" );
			my $stdout = `$value`;
			my $rc = $?;
			msgLog( "stdout='$stdout'" );
			msgLog( "got rc=$rc" );
		}
		$count += 1;
	} else {
		msgErr( "unmanaged reference '$ref'" );
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
	"service=s"			=> \$opt_service,
	"key=s@"			=> \@opt_keys )){

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
msgVerbose( "got service='$opt_service'" );
@opt_keys = split( /,/, join( ',', @opt_keys ));
msgVerbose( "got keys='".join( ',', @opt_keys )."'" );

msgErr( "'--service' service name is required, but not found" ) if !$opt_service;
msgErr( "at least a key is required, but none found" ) if !scalar( @opt_keys );

if( !TTP::errs()){
	executeCommands() if $opt_service && scalar( @opt_keys );
}

TTP::exit();
