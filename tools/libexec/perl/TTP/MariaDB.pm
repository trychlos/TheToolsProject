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
#
# A package dedicated to MariaDB

package TTP::MariaDB;
die __PACKAGE__ . " must be loaded as TTP::MariaDB\n" unless __PACKAGE__ eq 'TTP::MariaDB';

use base qw( TTP::DBMS );
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Capture::Tiny qw( :all );
use Data::Dumper;
use DBD::MariaDB;	# this is dynamically loaded by DBI; we mention it here to be checked in test suite
use DBI;
use DBI::Const::GetInfoType;
use File::Spec;
use Path::Tiny;
use Time::Moment;

use TTP;
use TTP::Constants qw( :all );
use TTP::Credentials;
use TTP::Message qw( :all );

my $Const = {
	# the list of system databases to be excluded
	systemDatabases => [
		'information_schema',
		'mysql',
		'performance_schema',
		'sys'
	],
	# the list of system tables to be excluded
	systemTables => [
	],
	# just inferred from returned database statistics (dbStats command)
	dbStates => {
		'0' => 'down',
		'1' => 'online'
	}
};

### Private methods

# ------------------------------------------------------------------------------------------------
# get a connection to the MariaDB server instance
# keep here one handle per database
#
# https://metacpan.org/dist/DBD-MariaDB/view/lib/DBD/MariaDB.pod
# The database is not a required attribute, but please note that MariaDB and MySQL has no such thing
# as a default database. If you don't specify the database at connection time your active database
# will be null and you'd need to prefix your tables with the database name; i.e. SELECT * FROM mydb.mytable.
#
# (I):
# - an optional database name (as DBI likes databases)
# (O):
# - an opaque handle on the connection, or undef

sub _connect {
	my ( $self, $database ) = @_;

	my $key = $database || 'DEFAULT';
	my $handle = $self->{_dbms}{connect}{$key};
	if( $handle ){
		msgVerbose( __PACKAGE__."::_connect() already connected" );

	} else {
		my( $account, $passwd ) = $self->_getCredentials();
		if( length $account && length $passwd ){
			my $server = $self->connectionString() || 'localhost';
			my @words = split( /:/, $server );
			my $dsn = "DBI:MariaDB:";
			$dsn .= $database if $database;
			$dsn .= ";host=$words[0]";
			$dsn .= ";port=$words[1]" if $words[1];
			$handle = DBI->connect( $dsn, $account, $passwd, { PrintError => 0 }) or msgErr( $DBI::errstr );
			$self->{_dbms}{connect}{$key} = $handle;
			if( $handle ){
				msgVerbose( __PACKAGE__."::_connect() successfully connected" );
			}
		} else {
			msgErr( __PACKAGE__."::_connect() unable to get account/password couple" );
		}
	}

	return $handle;
}

# ------------------------------------------------------------------------------------------------
# execute a command on the server
# this is to be used when we expect some rows to be returned (else call do())
# (I):
# - this instance
# - the sql
# - an optional options hash with following keys:
#   > dbh: the DBI database handle to be used, defaulting to the default 'DEFAULT' connection
# (O):
# - the result as a hash ref with following keys:
#   > ok: true|false
#   > result: a ref to an array of hash refs

sub _sqlExec {
	my ( $self, $command, $opts ) = @_;
	$opts //= {};
	msgErr( __PACKAGE__."::_sqlExec() command is mandatory, but is not specified" ) if !$command;
	if( TTP::errs()){
		TTP::stackTrace();
	}
	my $res = {
		ok => false,
		result => [],
		stdout => [],
		stderr => []
	};
	if( !TTP::errs()){
		my $dbh = $opts->{dbh} || $self->_connect();
		if( $dbh ){
			my $sth = $dbh->prepare( $command );
			my $rc = $sth->execute();
			$res->{ok} = defined $rc ? true : false;
			if ($res->{ok} ){
				while ( my $ref = $sth->fetchrow_hashref()){
					push( @{$res->{result}}, $ref );
				}
			} else {
				msgErr( $DBI::errstr );
				msgErr( "sql='$command'", { incErr => false });
			}
		}
	}
	#print "res ".Dumper( $res );
	return $res;
}

### Public methods

# -------------------------------------------------------------------------------------------------
# Backup a database
# There is no backup/restore primitive in MariaDB Perl driver, we so must stuck to
#  mongodump/mongorestore command-line utilities.
# As of 4.11.0-rc.0, we are only able to do full backups :(
# (I):
# - parms is a hash ref with following keys:
#   > database: mandatory
#   > output: optional
#   > mode: full|diff, defaulting to 'full'
#   > compress: true|false
# (O):
# - returns a hash with following keys:
#   > ok: true|false
#   > output: the (maybe computed here) output file
#   > stdout: a copy of lines outputed on stdout as an array ref

sub backupDatabase {
	my ( $self, $parms ) = @_;

	my $result = { ok => false };
	msgErr( __PACKAGE__."::backupDatabase() database is mandatory, but is not specified" ) if !$parms->{database};
	msgErr( __PACKAGE__."::backupDatabase() mode must be 'full' or 'diff', found '$parms->{mode}'" ) if $parms->{mode} ne 'full' && $parms->{mode} ne 'diff';
	msgErr( __PACKAGE__."::backupDatabase() differential mode is not supported" ) if $parms->{mode} eq 'diff';
	if( TTP::errs()){
		TTP::stackTrace();
	}

	my $account = undef;
	my $passwd = undef;
	if( !TTP::errs()){
		( $account, $passwd ) = $self->_getCredentials();
		if( !length $account || !length $passwd ){
			msgErr( __PACKAGE__."::backupDatabase() unable to get account/password couple" );
		}
	}

	if( !TTP::errs()){
		msgVerbose( __PACKAGE__."::backupDatabase() entering with service='".$self->service()->name()."' database='$parms->{database}' mode='$parms->{mode}'..." );
		my $output = $parms->{output} || $self->computeDefaultBackupFilename( $parms );
		# mysqldump dumps the database to stdout
		my $cmd = "mysqldump";
		$cmd .= " --host=".$self->server();
		$cmd .= " --user=$account";
		$cmd .= " --password=$passwd";
		$cmd .= " --compress";
		$cmd .= " $parms->{database}";
		if( $parms->{compress} ){
			$cmd .= " | gzip";
			$output .= ".gz";
		}
		$cmd .= " > $output";
		my $res = TTP::commandExec( $cmd );
		# mysqldump provides no output on stdout
		$result->{ok} = $res->{success};
		$result->{stderr} = $res->{stderr};
		#msgLog( __PACKAGE__."::backupDatabase() stdout='".TTP::chompDumper( $result->{stdout} )."'" );
		$result->{output} = $output;
	}

	msgVerbose( __PACKAGE__."::backupDatabase() returns '".( $result->{ok} ? 'true':'false' )."'" );
	return $result;
}

# -------------------------------------------------------------------------------------------------
# Get the different sizes of a database
# (I):
# - database name
# (O):
# - returns a hash with four items { key, value } describing the six different sizes to be considered

sub databaseSize {
	my ( $self, $database ) = @_;
	my $result = {};
	my $dbh = $self->_connect( $database );
	if( $dbh ){
		my $sql = "select sum(data_length) as data_length,sum(index_length) as index_length from information_schema.tables where table_schema='$database'";
		my $res = $self->_sqlExec( $sql, {
			dbh => $dbh
		});
		$result->{dataSize} = $res->{result}[0]{data_length};
		$result->{indexSize} = $res->{result}[0]{index_length};
	} else {
		msgErr( __PACKAGE__."::databaseSize() unable to get a handle on '$database' database" );
	}
	return $result;
}

# -------------------------------------------------------------------------------------------------
# Get the status of a database
# (I):
# - database name
# (O):
# - returns a hash with following keys:
#   > state: whether the database is up and running, with values 0 (down) or 1 (up)
#   > state_desc: a label which describes the state, e.g. 'online' or 'down'
#
# dbStats $VAR1 = {
#          'fsTotalSize' => '19165872128',
#          'db' => 'ronin',
#          'storageSize' => '180224',
#          'scaleFactor' => '1',
#          'ok' => '1',
#          'fsUsedSize' => '10445062144',
#          'objects' => 67,
#          'indexes' => 27,
#          'avgObjSize' => '174.805970149254',
#          'dataSize' => '11712',
#          'collections' => 11,
#          'totalSize' => '479232',
#          'views' => 0,
#          'indexSize' => '299008'
#        };

sub databaseState {
	my ( $self, $database ) = @_;
	my $result = {
		state => 0,
		state_desc => $Const->{dbStates}{'0'}
	};
	my $dbh = $self->_connect( $database );
	if( $dbh ){
		my $res = $dbh->ping();
		$result->{state} = $res ? '1' : '0';
		$result->{state_desc} = $Const->{dbStates}{$result->{state}};
	} else {
		msgErr( __PACKAGE__."::databaseState() unable to get a handle on '$database' database" );
	}
	return $result;
}

# -------------------------------------------------------------------------------------------------
# Get the possible statuses of a database
# (I):
# - none
# (O):
# - returns a hash with following items where:
#   > the key is the numerical 'state' as returned by databaseState() abode
#   > the value is the corresponding string 'state_desc'

sub dbStatuses {
	my ( $self ) = @_;

	return $Const->{dbStates};
}

# -------------------------------------------------------------------------------------------------
# execute a sql command
# (I):
# - the command string to be executed
# - an optional options hash which may contain following keys:
#   > tabular: whether to format data as tabular data, defaulting to true
#   > json: an output file where data is to be saved
#   > multiple: whether we expect several result sets, defaulting to false
# (O):
# returns a hash ref with following keys:
# - ok: true|false
# - result: an array ref to hash results

sub execSqlCommand {
	my ( $self, $command, $opts ) = @_;
	$opts //= {};
	my $result = { ok => false };
	msgErr( __PACKAGE__."::execSqlCommand() command is mandatory, but not specified" ) if !$command;
	if( TTP::errs()){
		TTP::stackTrace();
	}

	my $sqlres = $self->_sqlExec( $command );
	$result->{ok} = $sqlres->{ok};

	if( $result->{ok} ){
		$result->{result} = $sqlres->{result};
		# tabular output if asked for
		my $tabular = true;
		$tabular = $opts->{tabular} if defined $opts->{tabular};
		if( $tabular ){
			TTP::displayTabular( $sqlres->{result} );
		} else {
			msgVerbose( "do not display tabular result as opts->{tabular}='false'" );
		}
		# json output if asked for
		my $json = '';
		$json = $opts->{json} if defined $opts->{json};
		if( $json ){
			TTP::jsonOutput( $sqlres->{result}, $json );
		} else {
			msgVerbose( "do not save JSON result as opts->{json} is not set" );
		}
	}
	return $result;
}

# -------------------------------------------------------------------------------------------------
# returns the list of databases in this DBMS
# cache the result (the list of found databases) to request the DBMS only once
# (I):
# - none
# (O):
# - returns the list of databases in the instance as an array ref, may be empty

sub getDatabases {
	my ( $self ) = @_;

	my $databases = $self->TTP::DBMS::getDatabases();
	if( defined( $databases )){
		msgVerbose( __PACKAGE__."::getDatabases() got cached databases [ ". join( ', ', @{$databases} )." ]" );
	} else {
		my $res = $self->_sqlExec( 'show databases' );
		if( $res->{ok} ){
			my $dbs = [];
			foreach my $it ( @{$res->{result}} ){
				push( @{$dbs}, { name => $it->{Database}} );
			}
			$databases = $self->filterGotDatabases( $dbs, $Const->{systemDatabases} );
		}
	}

	return $databases || [];
}

# -------------------------------------------------------------------------------------------------
# returns the list of collections in the database
# (I):
# - the database to list the collections from
# (O):
# - the list of collections, which may be empty

sub getDatabaseTables {
	my ( $self, $database ) = @_;

	my $tables = [];
	my $dbh = $self->_connect( $database );
	if ($dbh ){
		my $res = $self->_sqlExec( "show tables", { dbh => $dbh });
		if( $res->{ok} ){
			my $key = 'Tables_in_'.$database;
			foreach my $it ( @{$res->{result}} ){
				push( @{$tables}, $it->{$key} );
			}
		}
	}

	msgVerbose( __PACKAGE__."::getDatabasesTables() got ".scalar( @{$tables} )." tables(s)" );
	return $tables;
}

# ------------------------------------------------------------------------------------------------
# returns the list of properties of this DBMS server
# (I):
# - none
# (O):
# - the list of properties as a { name, value } array ref

sub getProperties {
	my ( $self ) = @_;

	# get common properties
	my $props = $self->TTP::DBMS::getProperties();

	my $dbh = $self->_connect();
	#print Dumper( %GetInfoType );
	if( $dbh ){
		my $res = $dbh->get_info( $GetInfoType{SQL_DBMS_VERSION} );
		push( @{$props}, { name => 'DbmsVersion', value => $res });
	}

	return $props;
}

# ------------------------------------------------------------------------------------------------
# returns the count of rows in the table of the database
# (I):
# - database
# - table
# (O):
# - the count of rows

sub getTableRowsCount {
	my ( $self, $database, $table ) = @_;

	my $count = 0;
	my $sql = "select count(*) as count from $database.$table";
	my $res = $self->_sqlExec( $sql );
	if( $res->{ok} ){
		$count = $res->{result}[0]{count};
	}

	msgVerbose( __PACKAGE__."::getTableRowscount() database='$database' table='$table' count=$count" );
	return $count;
}

# -------------------------------------------------------------------------------------------------
# Restore a file into a database
# (I):
# - parms is a hash ref with keys:
#   > database: mandatory
#   > full: mandatory, the full backup file
# (O):
# - returns a hash with following keys:
#   > ok: true|false

sub restoreDatabase {
	my ( $self, $parms ) = @_;

	my $result = { ok => false };
	msgErr( __PACKAGE__."::restoreDatabase() full is mandatory, not specified" ) if !$parms->{full};
	msgErr( __PACKAGE__."::restoreDatabase() --verifyonly option is not supported" ) if $parms->{verifyonly};
	msgErr( __PACKAGE__."::restoreDatabase() --diff option is not supported" ) if $parms->{diff};
	if( TTP::errs()){
		TTP::stackTrace();
	}

	my $account = undef;
	my $passwd = undef;
	if( !TTP::errs()){
		( $account, $passwd ) = $self->_getCredentials();
		if( !length $account || !length $passwd ){
			msgErr( __PACKAGE__."::restoreDatabase() unable to get account/password couple" );
		}
	}
	if( !TTP::errs()){
		msgVerbose( __PACKAGE__."::restoreDatabase() entering with service='".$self->service()->name()."' database='$parms->{database}'..." );
		# do we have a compressed archive file ?
		my $res = TTP::commandExec( "file $parms->{full}" );
		my $gziped = false;
		if( $res->{success} ){
			$gziped = true if grep( /gzip/, @{$res->{stdout}} );
			msgVerbose( __PACKAGE__."::restoreDatabase() found that provided dump file is ".( $gziped ? '' : 'NOT ' )."gzip'ed" );
			# and restore, making sure the database exists
			my $cmd = "(";
			$cmd .= " echo 'drop database if exists $parms->{database};';";
			$cmd .= " echo 'create database $parms->{database};';";
			$cmd .= " echo 'use $parms->{database};';";
			$cmd .= $gziped ? " gzip -cd" : " cat";
			$cmd .= " $parms->{full} )";
			$cmd .= " | mysql";
			$cmd .= " --host=".$self->server();
			$cmd .= " --user=$account";
			$cmd .= " --password=$passwd";
			$res = TTP::commandExec( $cmd );
			$result->{ok} = $res->{success};
			#$result->{stdout} = $res->{stderr};
			#msgLog( __PACKAGE__."::backupDatabase() stdout='".TTP::chompDumper( $result->{stdout} )."'" );
		}
	}

	msgVerbose( __PACKAGE__."::restoreDatabase() result='".( $result->{ok} ? 'true' : 'false' )."'" );
	return $result;
}

### Class methods

# -------------------------------------------------------------------------------------------------
# Constructor
# (I):
# - the TTP EP entry point
# - an argument object with following keys:
#   > node: the TTP::Node object this DBMS runs on
#   > service: the TTP::Service object this DBMS belongs to
# (O):
# - this object, or undef in case of an error

sub new {
	my ( $class, $ep, $args ) = @_;
	$class = ref( $class ) || $class;
	$args //= {};
	my $self = $class->SUPER::new( $ep, $args );

	if( $self ){
		bless $self, $class;
		$self->{_dmbs}{connect} = {};
		msgVerbose( __PACKAGE__."::new() node='".$args->{node}->name()."' service='".$args->{service}->name()."'" );
	}

	return $self;
}

# -------------------------------------------------------------------------------------------------
# Destructor
# (I):
# - instance
# (O):

sub DESTROY {
	my $self = shift;
	$self->SUPER::DESTROY();
	return;
}

### Global functions
### Note for the developer: while a global function doesn't take any argument, it can be called both
### as a class method 'TTP::Package->method()' or as a global function 'TTP::Package::method()',
### the former being preferred (hence the writing inside of the 'Class methods' block).

1;

__END__
