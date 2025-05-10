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
# A package dedicated to MongoDB

package TTP::MongoDB;
die __PACKAGE__ . " must be loaded as TTP::MongoDB\n" unless __PACKAGE__ eq 'TTP::MongoDB';

use base qw( TTP::DBMS );
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Config;
use Capture::Tiny qw( :all );
use Data::Dumper;
use File::Spec;
use File::Temp qw( tempdir );
use MongoDB;
use Path::Tiny;
use Time::Moment;

use TTP;
use TTP::Constants qw( :all );
use TTP::Credentials;
use TTP::Message qw( :all );

my $Const = {
	# the list of system databases to be excluded
	systemDatabases => [
		'admin',
		'config',
		'local'
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
# get a connection to the MongoDB server instance
# (I):
# - none
# (O):
# - an opaque handle on the connection, or undef

sub _connect {
	my ( $self ) = @_;

	my $handle = $self->{_dbms}{connect};
	if( $handle ){
		msgVerbose( __PACKAGE__."::_connect() already connected" );

	} else {
		my( $account, $passwd ) = $self->_getCredentials();
		if( length $account && length $passwd ){
			my $server = $self->service()->var([ 'DBMS', 'host' ], $self->node()) || 'localhost:27017';
			$handle = MongoDB::MongoClient->new( host => $server, username => $account, password => $passwd );
			$self->{_dbms}{connect} = $handle;
			if( $handle ){
				#print STDERR Dumper( $handle );
				msgVerbose( __PACKAGE__."::_connect() successfully connected" );
			} else {
				msgErr( __PACKAGE__."::_connect() unable to connect to '$server' host" );
			}
		} else {
			msgErr( __PACKAGE__."::_connect() unable to get account/password couple" );
		}
	}

	return $handle;
}

# ------------------------------------------------------------------------------------------------
# execute a command on the server
# (I):
# - the DBMS instance
# - the command
# - an optional options hash
# (O):
# - the result as a hash ref with following keys:
#   > ok: true|false

sub _noSql {
	my ( $self, $command, $opts ) = @_;
	$opts //= {};
	msgErr( __PACKAGE__."::_noSql() command is mandatory, but is not specified" ) if !$command;
	my $res = {
		ok => false,
		result => [],
		stdout => [],
		stderr => []
	};
	if( !TTP::errs()){
		my $handle = $self->_connect();
		#if( $handle ){
		#	my $hdb = $handle->db( 'admin' );
		#	if( $hdb ){
		#		my $result = $hdb->run_command( $command );
		#		print Dumper( $result );
		#	}
		#}
	}
	return $res;
}

### Public methods

# -------------------------------------------------------------------------------------------------
# Backup a database
# There is no backup/restore primitive in MongoDB Perl driver, we so must stuck to
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
	msgErr( __PACKAGE__."::backupDatabase() differential mode is not managed here" ) if $parms->{mode} eq 'diff';

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
		# mongodump dumps to a directory (piping to stdout in only possible for a single collection)
		# so have to create a temp dir, and then tar.gzip it and remove the temp dir at end
		my $tmpdir = tempdir( CLEANUP => 1 );
		my $cmd = "mongodump";
		$cmd .= " --host ".$self->server();
		$cmd .= " --username $account";
		$cmd .= " --password $passwd";
		$cmd .= " --authenticationDatabase admin";
		$cmd .= " --db $parms->{database}";
		$cmd .= " --out $tmpdir";
		my $opt = "";
		$opt = "-z" if $parms->{compress};
		$cmd .= " && (cd $tmpdir; tar -c $opt -f - $parms->{database} > $output)";
		my $res = TTP::commandExec( $cmd );
		# mongodump provides its output on stderr, while stdout is empty
		$result->{ok} = $res->{success};
		$result->{stdout} = $res->{stderr};
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
	my $handle = $self->_connect();
	if( $handle ){
		my $dbh = $handle->get_database( $database );
		if( $dbh ){
			my $stats = $dbh->run_command([ dbStats => 1 ]);
			$result->{dataSize} = $stats->{dataSize};
			$result->{indexSize} = $stats->{indexSize};
			$result->{storageSize} = $stats->{storageSize};
			$result->{totalSize} = $stats->{totalSize};
		} else {
			msgErr( __PACKAGE__."::databaseSize() unable to get a handle on '$database' database" );
		}
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
	my $handle = $self->_connect();
	if( $handle ){
		my $dbh = $handle->get_database( $database );
		if( $dbh ){
			my $stats = $dbh->run_command([ dbStats => 1 ]);
			$result->{state} = $stats->{ok};
			$result->{state_desc} = $Const->{dbStates}{$stats->{ok}};
		} else {
			msgErr( __PACKAGE__."::databaseState() unable to get a handle on '$database' database" );
		}
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
# not managed by MongoDB driver as of v4.11
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
	my $result = { ok => false };
	msgErr( __PACKAGE__."::execSqlCommand() doesn't manage SQL commands as MongoDB is a NoSQL database" );
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
		my $handle = $self->_connect();
		if( $handle ){
			my @dbs = $handle->list_databases;
			$databases = [];
			foreach my $it ( @dbs ){
				my $dbname = $it->{name};
				if( !$self->dbFilteredBySystem( $dbname, $Const->{systemDatabases} ) && !$self->dbFilteredbyLimit( $dbname )){
					push( @{$databases}, $dbname );
				}
			}
			msgVerbose( __PACKAGE__."::getDatabases() got databases [ ". join( ', ', @{$databases} )." ]" );
			$self->{_dbms}{databases} = $databases;
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

	my @collections = ();
	my $handle = $self->_connect();
	if( $handle ){
		my $db = $handle->get_database( $database );
		@collections = $db->collection_names;
		msgVerbose( __PACKAGE__."::getDatabasesTables() got ".scalar( @collections )." collection(s)" );
	}

	return \@collections;
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

	return $props;
}

# ------------------------------------------------------------------------------------------------
# returns the count of documents in the collection of the database
# (I):
# - database
# - table
# (O):
# - the count of rows

sub getTableRowsCount {
	my ( $self, $database, $table ) = @_;

	my $count = 0;
	my $handle = $self->_connect();
	if( $handle ){
		my $dbh = $handle->get_database( $database );
		if( $dbh ){
			my $coll = $dbh->get_collection( $table );
			if( $coll ){
				$count = $coll->count_documents({});
			} else {
				msgErr( __PACKAGE__."::getTableRowscount() unable to get a handle on '$table' collection" );
			}
		} else {
			msgErr( __PACKAGE__."::getTableRowscount() unable to get a handle on '$database' database" );
		}
	}

	msgVerbose( __PACKAGE__."::getTableRowscount() database='$database' collection='$table' count=$count" );
	return $count;
}

# -------------------------------------------------------------------------------------------------
# Restore a file into a database
# As backups are managed with mongodump, restores are to be managed with mongorestore
# (I):
# - parms is a hash ref with keys:
#   > full: mandatory, the full backup file
# (O):
# - returns a hash with following keys:
#   > ok: true|false

sub restoreDatabase {
	my ( $self, $parms ) = @_;

	my $result = { ok => false };
	msgErr( __PACKAGE__."::restoreDatabase() full is mandatory, not specified" ) if !$parms->{full};
	msgErr( __PACKAGE__."::restoreDatabase() --verifyonly option is not supported here" ) if $parms->{verifyonly};
	msgErr( __PACKAGE__."::restoreDatabase() --diff option is not supported here" ) if $parms->{diff};

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
		my $tmpdir = tempdir( CLEANUP => 1 );
		# do we have a compressed archive file ?
		my $cmd = "file $parms->{full}";
		my $res = `$cmd`;
		my @res = split( /[\r\n]/, $res );
		my $gziped = false;
		if( grep( /gzip/, @res )){
			$gziped = true;
		}
		my $opt = "";
		$opt = "-z" if $gziped;
		msgVerbose( __PACKAGE__."::restoreDatabase() find provided dump file is ".( $gziped ? '' : 'NOT ' )."gziped" );
		# find the source database name in the dump file
		# this should be the first element of the paths
		$cmd = "tar -t $opt -f $parms->{full}";
		$res = `$cmd`;
		@res = split( /[\r\n]/, $res );
		my $sourcedb = $res[0];
		$sourcedb =~ s/\/$//;
		msgVerbose( __PACKAGE__."::restoreDatabase() find source database='$sourcedb'" );
		# and restore
		# if source and target database don't have the same name, then rename
		$cmd = "tar -x $opt -f $parms->{full} --directory $tmpdir";
		$cmd .= " && mongorestore";
		$cmd .= " --host ".$self->server();
		$cmd .= " --username $account";
		$cmd .= " --password $passwd";
		$cmd .= " --authenticationDatabase admin";
		$cmd .= " --drop";
		if( $sourcedb ne $parms->{database} ){
			$cmd .= " --nsFrom '$sourcedb.*'";
			$cmd .= " --nsTo '$parms->{database}.*'";
		}
		$cmd .= " $tmpdir";
		$res = TTP::commandExec( $cmd );
		# mongodump provides its output on stderr, while stdout is empty
		$result->{ok} = $res->{success};
		#$result->{stdout} = $res->{stderr};
		#msgLog( __PACKAGE__."::backupDatabase() stdout='".TTP::chompDumper( $result->{stdout} )."'" );
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
		msgVerbose( __PACKAGE__."::new()" );
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
