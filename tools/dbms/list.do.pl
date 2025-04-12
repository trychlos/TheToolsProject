# @(#) list various DBMS objects
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --service=<name>        acts on the named service [${service}]
# @(-) --[no]listinstance      display the instance which manages the named service [${listinstance}]
# @(-) --instance=<name>       acts on the named instance [${instance}]
# @(-) --[no]listdb            list the databases of the named instance [${listdb}]
# @(-) --database=<name>       acts on the named database [${database}]
# @(-) --[no]listtables        list the tables of the named database [${listtables}]
#
# @(@) with:
# @(@)   dbms.pl list -service <service> -listinstance displays the instance name for the named service on this node
# @(@)   dbms.pl list -instance <instance> -listdb displays the list of databases in the named instance on this node
# @(@)   dbms.pl list -instance <instance> -database <database> -listtables displays the list of tables in the named database in the named instance on this node
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

use TTP::DBMS;
use TTP::Service;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	service => '',
	listinstance => 'no',
	instance => 'MSSQLSERVER',
	listdb => 'no',
	database => '',
	listtables => 'no'
};

my $opt_service = $defaults->{service};
my $opt_listinstance = false;
my $opt_instance = $defaults->{instance};
my $opt_instance_set = false;
my $opt_listdb = false;
my $opt_database = $defaults->{database};
my $opt_listtables = false;

# may be overriden by the service if specified
my $jsonable = $ep->node();
my $dbms = undef;

# -------------------------------------------------------------------------------------------------
# list the databases in the instance or the service

sub listDatabases {
	my $databases = [];
	if( $opt_service ){
		msgOut( "displaying databases attached to '$opt_service' service..." );
		$databases = $jsonable->var([ 'DBMS', 'databases' ]);
	} else {
		msgOut( "displaying databases in '$opt_instance' instance..." );
		$databases = $dbms->getDatabases();
	}
	foreach my $db ( @{$databases} ){
		print " $db".EOL;
	}
	msgOut( scalar @{$databases}." found database(s)" );
}

# -------------------------------------------------------------------------------------------------
# list the instance attached to this service in this node

sub listInstance {
	msgOut( "displaying instance for '$opt_service' service..." );
	print " $opt_instance".EOL;
	msgOut( "1 found instance" );
}

# -------------------------------------------------------------------------------------------------
# list the tables in the database

sub listTables {
	msgOut( "displaying tables in '$opt_instance\\$opt_database'..." );
	my $list = $dbms->getDatabaseTables( $opt_database );
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
	"listinstance!"		=> \$opt_listinstance,
	"instance=s"		=> sub {
		my( $opt_name, $opt_value ) = @_;
		$opt_instance = $opt_value;
		$opt_instance_set = true;
	},
	"listdb!"			=> \$opt_listdb,
	"database=s"		=> \$opt_database,
	"listtables!"		=> \$opt_listtables )){

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
msgVerbose( "got listinstance='".( $opt_listinstance ? 'true':'false' )."'" );
msgVerbose( "got instance='$opt_instance'" );
msgVerbose( "got instance_set='".( $opt_instance_set ? 'true':'false' )."'" );
msgVerbose( "got listdb='".( $opt_listdb ? 'true':'false' )."'" );
msgVerbose( "got database='$opt_database'" );
msgVerbose( "got listtables='".( $opt_listtables ? 'true':'false' )."'" );

# must have either -service or -instance options
# compute instance from service
my $count = 0;
$count += 1 if $opt_service;
$count += 1 if $opt_instance_set;
if( $count == 0 ){
	msgErr( "must have one of '--service' or '--instance' option, none found" );
} elsif( $count > 1 ){
	msgErr( "must have one of '--service' or '--instance' option, both found" );
} elsif( $opt_service ){
	if( $jsonable->hasService( $opt_service )){
		$jsonable = TTP::Service->new( $ep, { service => $opt_service });
		$opt_instance = $jsonable->var([ 'DBMS', 'instance' ]);
	} else {
		msgErr( "service '$opt_service' if not defined on current execution node" ) ;
	}
}

# instanciates the DBMS class
$dbms = TTP::DBMS->new( $ep, { instance => $opt_instance }) if !TTP::errs();

# if a database is specified must exists in the service or in the instance
if( !TTP::errs() && $opt_database ){
	if( $opt_service ){
		my @databases = $jsonable->var([ 'DBMS', 'databases' ]);
		if( !grep( /$opt_database/, @databases )){
			msgErr( "database '$opt_database' in not defined in '$opt_service' service" );
		}
	} elsif( !$dbms->databaseExists( $opt_database )){
		msgErr( "database '$opt_database' doesn't exist in '$opt_instance' instance" );
	}
}

if( !TTP::errs()){
	listDatabases() if $opt_instance && $opt_listdb;
	listInstance() if $opt_service && $opt_listinstance;
	listTables() if $opt_instance && $opt_database && $opt_listtables;
}

TTP::exit();
