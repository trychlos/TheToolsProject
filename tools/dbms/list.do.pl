# @(#) list various DBMS objects
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --service=<name>        acts on the named service [${service}]
# @(-) --target=<name>         target node [${target}]
# @(-) --[no]properties        display specific properties of the named service [${properties}]
# @(-) --[no]list-db           list the available databases on the named service [${listdb}]
# @(-) --database=<name>       acts on the named database [${database}]
# @(-) --[no]list-tables       list the available tables of the named database [${listtables}]
#
# @(@) with:
# @(@)   'dbms.pl list -service <service> -properties' displays specific properties for this service
# @(@)   'dbms.pl list -service <service> -listdb' displays the available databases for this service
# @(@)   'dbms.pl list -service <service> -database <database> -listtables' displays the list of tables in the named database for this service
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

use TTP::Node;
use TTP::Service;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	service => '',
	target => '',
	properties => 'no',
	listdb => 'no',
	database => '',
	listtables => 'no'
};

my $opt_service = $defaults->{service};
my $opt_target = $defaults->{target};
my $opt_properties = false;
my $opt_listdb = false;
my $opt_database = $defaults->{database};
my $opt_listtables = false;

# the node which hosts the requested service
my $objNode = undef;
# the service object
my $objService = undef;
# the DBMS object
my $objDbms = undef;

# -------------------------------------------------------------------------------------------------
# list the databases in the service

sub listDatabases {
	my $databases = [];
	msgOut( "displaying databases attached to '$opt_service' service..." );
	$databases = $objDbms->getDatabases() || [];
	foreach my $db ( @{$databases} ){
		print " $db".EOL;
	}
	msgOut( scalar @{$databases}." found database(s)" );
}

# -------------------------------------------------------------------------------------------------
# list the properties of the service

sub listProperties {
	my $props = [];
	msgOut( "displaying properties of '$opt_service' DBMS service..." );
	$props = $objDbms->getProperties() || [];
	foreach my $it ( @{$props} ){
		print " ".$it->{name}.": ".$it->{value}.EOL;
	}
	msgOut( scalar @{$props}." found properties(s)" );
}

# -------------------------------------------------------------------------------------------------
# list the tables in the database

sub listTables {
	msgOut( "displaying tables in '$opt_service\\$opt_database'..." );
	my $list = $objDbms->getDatabaseTables( $opt_database );
	foreach my $it ( @{$list} ){
		print " $it".EOL;
	}
	msgOut( scalar @{$list}." found table(s)" );
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
	"target=s"			=> \$opt_target,
	"properties!"		=> \$opt_properties,
	"list-db!"			=> \$opt_listdb,
	"database=s"		=> \$opt_database,
	"list-tables!"		=> \$opt_listtables )){

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
msgVerbose( "got target='$opt_target'" );
msgVerbose( "got properties='".( $opt_properties ? 'true':'false' )."'" );
msgVerbose( "got listdb='".( $opt_listdb ? 'true':'false' )."'" );
msgVerbose( "got database='$opt_database'" );
msgVerbose( "got listtables='".( $opt_listtables ? 'true':'false' )."'" );

# must have --service option
# find the node which hosts this service in this same environment (should be at most one)
# and check that the service is DBMS-aware
if( $opt_service ){
	$objNode = TTP::Node->findByService( $ep->node()->environment(), $opt_service, { target => $opt_target });
	if( $objNode ){
		msgVerbose( "got hosting node='".$objNode->name()."'" );
		$objService = TTP::Service->new( $ep, { service => $opt_service });
		if( $objService->wantsLocal() && $objNode->name() ne $ep->node()->name()){
			TTP::execRemote( $objNode->name());
			TTP::exit();
		}
		$objDbms = $objService->newDbms({ node => $objNode });
	}
} else {
	msgErr( "'--service' option is mandatory, but is not specified" );
}

# --database and --listtables work together
if( $opt_database && !$opt_listtables ){
	msgErr( "'--database' option has been specified, but nothing has been asked to be done with. Did you miss '--listtables' option ?" );
}
if( !$opt_database && $opt_listtables ){
	msgErr( "'--listtables' option has been specified, but '--database' is missing" );
}

# if a database is specified must exists in the service
if( $opt_database && $objDbms && !$objDbms->databaseExists( $opt_database )){
	msgErr( "database '$opt_database' doesn't exist in '$opt_service' instance" );
}

# should have something to do
if( !$opt_properties && !$opt_listdb && ( !$opt_database || !$opt_listtables )){
	msgWarn( "neither '--properties', or '--listdb' or '--listtables' options have been specified, nothing to do" );
}

if( !TTP::errs()){
	listDatabases() if $opt_listdb;
	listProperties() if $opt_properties;
	listTables() if $opt_database && $opt_listtables;
}

TTP::exit();
