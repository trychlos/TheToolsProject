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
# A package dedicated to MongoDB

package TTP::MongoDB;
die __PACKAGE__ . " must be loaded as TTP::MongoDB\n" unless __PACKAGE__ eq 'TTP::MongoDB';

use base qw( TTP::DBMS );
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Capture::Tiny qw( :all );
use Data::Dumper;
use File::Spec;
use File::Temp qw( tempdir );
use JSON::PP;
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
			my $server = $self->connectionString() || 'localhost:27017';
			#print STDERR "server $server\n";
			$handle = MongoDB::MongoClient->new( host => $server, username => $account, password => $passwd );
			if( $handle ){
				$handle->connected();
				#print STDERR "handle ".Dumper( $handle );
				my $status = $handle->topology_status();
				#print "status ".Dumper( $status );
				foreach my $it ( @{$status->{servers}} ){
					my $error = $it->{error};
					if( $error ){
						msgErr( $error );
						$handle = undef;
						last;
					}
				}
			} else {
				msgErr( __PACKAGE__."::_connect() unable to instanciate a client for '$server' host" );
			}
			if( $handle ){
				$self->{_dbms}{connect} = $handle;
				msgVerbose( __PACKAGE__."::_connect() successfully connected" );
			}
		} else {
			msgErr( __PACKAGE__."::_connect() unable to get account/password couple" );
		}
	}
				$self->{_dbms}{connect} = $handle;

	return $handle;
}

=pod
	# https://chatgpt.com/c/689b1e14-7078-8332-8895-1f18b4788800
sub parse_mongosh_call {
    my ($s) = @_;
    $s =~ s/^\s+|\s+$//g;

    # Ex: db.restores.deleteMany({ topic: '$topic' })
    my ($coll, $op, $args) = $s =~ /^db\.(\w+)\.(\w+)\s*\((.*)\)\s*$/s
        or die "Commande invalide: $s";

    # Retirer une éventuelle virgule finale et espaces
    $args =~ s/\s+\)\s*$// if $args =~ /\)\s*$/;
    $args =~ s/^\s+|\s+$//g;

    # Autoriser: quotes simples, clés non-quotées, trailing commas
    my $json = JSON::PP->new
        ->allow_singlequote
        ->relaxed
        ->loose
        ->allow_barekey
        ->allow_bignum
        ->convert_blessed;

    my $parsed;
    if ($args eq '' ) {
        $parsed = undef;
    } else {
        # Si plusieurs params "({..}, {..})", on renvoie arrayref
        if ($args =~ /^\s*\{.*\}\s*,/s) {
            $parsed = $json->decode("[$args]");
        } else {
            $parsed = $json->decode($args);
        }
    }

    return ($coll, $op, $parsed);
}

sub interpolate_vars {
    my ($node, $vars) = @_;

    if (!ref $node) {
        # Remplace une chaîne exactement de la forme '$name'
        if (defined $node && $node =~ /^\$(\w+)$/) {
            my $k = $1;
            die "Variable \$$k non fournie" unless exists $vars->{$k};
            return $vars->{$k};
        } else {
            return $node;
        }
    }
    my $t = reftype($node) || '';
    if ($t eq 'HASH') {
        my %h;
        for my $k (keys %$node) {
            $h{$k} = interpolate_vars($node->{$k}, $vars);
        }
        return \%h;
    } elsif ($t eq 'ARRAY') {
        return [ map { interpolate_vars($_, $vars) } @$node ];
    } else {
        return $node;
    }
}

# -------- Traduction vers run_command --------

sub to_run_command {
    my ($collection, $op, $args) = @_;

    if ($op eq 'deleteMany') {
        my $filter = $args // {};
        return [
            delete  => $collection,
            deletes => [ { q => $filter, limit => 0 } ],
        ];
    }
    if ($op eq 'insertOne') {
        my $doc = $args // {};
        return [
            insert    => $collection,
            documents => [ $doc ],
            ordered   => JSON::PP::true,   # optionnel
        ];
    }

    die "Opération non supportée: $op";
}

# -------- Exemple d’utilisation --------
# Variables applicatives (déjà renseignées de ton côté)
my %vars = (
    topic   => 'sensors/livingroom',
    payload => { temperature => 21.5, unit => 'C' },  # peut être une chaîne, un hashref, etc.
);

# Exemples de commandes côté "dbms.pl -command"
my $cmd1 = q{db.restores.deleteMany({ topic: '$topic' })};
my $cmd2 = q{db.restores.insertOne({ topic: '$topic', payload: '$payload' })};

# Parse
my ($coll1, $op1, $args1) = parse_mongosh_call($cmd1);
my ($coll2, $op2, $args2) = parse_mongosh_call($cmd2);

# Interpolation des variables
$args1 = interpolate_vars($args1, \%vars) if defined $args1;
$args2 = interpolate_vars($args2, \%vars) if defined $args2;

# Traduction vers run_command
my $rc1 = to_run_command($coll1, $op1, $args1);
my $rc2 = to_run_command($coll2, $op2, $args2);

# Exécution
my $client = MongoDB->connect('mongodb://localhost:27017');
my $db     = $client->get_database('ta_base');

my $res1 = $db->run_command($rc1);
my $res2 = $db->run_command($rc2);
=cut

# ------------------------------------------------------------------------------------------------
# parse a MongoSh command
# (I):
# - the DBMS instance
# - the command
# - an optional options hash
# (O):
# - the result as a list:
#   > ok: true|false
#   > collection
#   > op
#   > parsed parameters

sub _parseMongosh {
	my ( $self, $command, $opts ) = @_;

	# remove leading and trailing spaces
    $command =~ s/^\s+|\s+$//g;

    # Ex: db.restores.deleteMany({ topic: '$topic' })
    my ( $coll, $op, $args ) = $command =~ /^db\.(\w+)\.(\w+)\s*\((.*)\)\s*$/s or msgErr( __PACKAGE__."::_parseMongosh() invalid command: $command" );

	my $parsed = undef;
	my $ok = false;

	if( !TTP::errs()){
		$ok = true;
		# remove trailing commas and spaces
		$args =~ s/\s+\)\s*$// if $args =~ /\)\s*$/;
		$args =~ s/^\s+|\s+$//g;
		# allow simple quotes, non-quotes and trailing commas
		my $json = JSON::PP->new
			->allow_singlequote
			->relaxed
			->loose
			->allow_barekey
			->allow_bignum
			->convert_blessed;

		if( $args ){
			# if several params "({..}, {..})", then returns an arrayref
			if( $args =~ /^\s*\{.*\}\s*,/s ){
				$parsed = $json->decode( "[$args]" );
			} else {
				$parsed = $json->decode( $args );
			}
		}
	}

    return ( $ok, $coll, $op, $parsed );
}

# ------------------------------------------------------------------------------------------------
# execute a command on the server
# the command is expected to be a MongoSh command
# (I):
# - the DBMS instance
# - the command
# - an optional options hash
# (O):
# - the result as a hash ref with following keys:
#   > ok: true|false

sub _parseNoSql {
	my ( $self, $command, $opts ) = @_;
	$opts //= {};
	msgErr( __PACKAGE__."::_parseNoSql() command is mandatory, but is not specified" ) if !$command;
	my $res = {
		ok => false,
		result => [],
		stdout => [],
		stderr => []
	};
	if( !TTP::errs()){
		my ( $ok, $collection, $op, $args ) = $self->_parseMongosh( $command, $opts );
		$res->{ok} = $ok;
		if( $ok ){
			my $parms = $self->_parseToRun( $collection, $op, $args );
			#print STDERR "parms ".Dumper( $parms );
			if( $parms ){
				my $handle = $self->_connect();
				if( $handle ){
					my $db = $handle->get_database( $handle->{db_name } );
					$res->{command_rc} = $db->run_command( $parms );
				}
			}
		}
	}
	#print STDERR "res ".Dumper( $res );
	return $res;
}

# ------------------------------------------------------------------------------------------------
# execute a command on the server
# the command is expected to be a SQL command
# (I):
# - the DBMS instance
# - the command
# - an optional options hash
# (O):
# - the result as a hash ref with following keys:
#   > ok: true|false

sub _parseSql {
	my ( $self, $command, $opts ) = @_;
	$opts //= {};
	msgErr( __PACKAGE__."::_parseSql() command is mandatory, but is not specified" ) if !$command;
	my $res = {
		ok => false,
		result => [],
		stdout => [],
		stderr => []
	};
	if( !TTP::errs()){
		my $parms = $self->_parseSqlToRunCommand( $command, $opts );
		#print STDERR "parms ".Dumper( $parms );
		if( $parms ){
			my $handle = $self->_connect();
			if( $handle ){
				$res->{ok} = true;
				my $db = $handle->get_database( $handle->{db_name } );
				$res->{command_rc} = $db->run_command( $parms );
			}
		}
	}
	#print STDERR "res ".Dumper( $res );
	return $res;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - the DBMS instance
# - the command
# - an optional options hash
# (O):
# - the result as a hash ref with following keys:
#   > ok: true|false

sub _parseSqlToRunCommand {
    my ( $self, $sql, $opts ) = @_;

	# remove leading and trailing spaces
    $sql =~ s/^\s+|\s+$//g;

    # DELETE
    if( $sql =~ /^DELETE\s+FROM\s+(\w+)\s*(WHERE\s+(.+))?$/i ){
        my $table = $1;
        my $where = $3 // '';

        my %filter;
        if( $where ){
            # Simple parsing: assume "col = 'value'" and ANDs
            for my $cond ( split /\s+AND\s+/i, $where ){
                if( $cond =~ /^\s*(\w+)\s*=\s*'([^']*)'\s*$/ ){
                    $filter{$1} = $2;
                }
            }
        }

        return [
            delete  => $table,
            deletes => [ { q => \%filter, limit => 0 } ],
        ];
    }

    # INSERT
    if( $sql =~ /^INSERT\s+INTO\s+(\w+)\s*\(([^)]+)\)\s*VALUES\s*\(([^)]+)\)/i ){
        my $table = $1;
        my @cols = map { s/^\s+|\s+$//gr } split /,/, $2;
        my @vals = map { s/^\s+|\s+$//gr } split /,/, $3;

        my %doc;
        for my $i ( 0..$#cols ){
            my $val = $vals[$i];
            if( $val =~ /^'(.*)'$/ ){
                $val = $1;  # remove quotes
            }
            $doc{$cols[$i]} = $val;
        }

        return [
            insert    => $table,
            documents => [ \%doc ],
            ordered   => JSON::PP::true,
        ];
    }

	msgWarn( __PACKAGE__."::_parseSqlToRunCommand() unmanaged operation: $sql" );
	return undef;
}

# ------------------------------------------------------------------------------------------------
# execute a command on the server
# (I):
# - the DBMS instance
# - the collection
# - the op
# - the args
# (O):
# - the result as a hash ref with following keys:
#   > ok: true|false

sub _parseToRun {
	my ( $self, $collection, $op, $args ) = @_;

	if( $op eq 'deleteMany' ){
		my $filter = $args // {};
		return [
			delete  => $collection,
			deletes => [{ q => $filter, limit => 0 }]
		];
	}

	if( $op eq 'insertOne' ){
		my $doc = $args // {};
		return [
			insert    => $collection,
			documents => [ $doc ],
			ordered   => JSON::PP::true,   # optionnel
		];
	}

	msgWarn( __PACKAGE__."::_parseToRun() unmanaged operation: $op" );
	return undef;
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
		$result->{stdout} = $res->{stderrs};
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
# - returns a hash with four items { key, value } describing the four different sizes which may be considered

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
	#my $result = { ok => false };
	#msgErr( __PACKAGE__."::execSqlCommand() doesn't manage SQL commands as MongoDB is a NoSQL database" );
	#my $result = $self->_parseNoSql( $command, $opts );
	my $result = $self->_parseSql( $command, $opts );
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
			$databases = $self->filterGotDatabases( \@dbs, $Const->{systemDatabases} );
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
		my $tmpdir = tempdir( CLEANUP => 1 );
		# do we have a compressed archive file ?
		my $cmd = "file $parms->{full}";
		my $res = TTP::filter( $cmd );
		my $gziped = false;
		$gziped = true if grep( /gzip/, @{$res} );
		my $opt = "";
		$opt = "-z" if $gziped;
		msgVerbose( __PACKAGE__."::restoreDatabase() found that provided dump file is ".( $gziped ? '' : 'NOT ' )."gzip'ed" );
		# find the source database name in the dump file
		# this should be the first element of the paths
		$cmd = "tar -t $opt -f $parms->{full}";
		$res = TTP::filter( $cmd );
		my $sourcedb = $res->[0];
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
