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
# A package dedicated to PostgreSQL

package TTP::PostgreSQL;
die __PACKAGE__ . " must be loaded as TTP::PostgreSQL\n" unless __PACKAGE__ eq 'TTP::PostgreSQL';

use base qw( TTP::DBMS );
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Capture::Tiny qw( :all );
use Data::Dumper;
use DBD::Pg;	# this is dynamically loaded by DBI; we mention it here to be checked in test suite
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
		'postgres',
		'template0',
		'template1'
	],
	# the list of system tables to be excluded
	systemTables => [
		'sql_features',
		'sql_implementation_info',
		'sql_parts',
		'sql_sizing'
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
		msgVerbose( __PACKAGE__."::_connect() '$key' already connected" );

	} else {
		my( $account, $passwd ) = $self->_getCredentials();
		if( length $account && length $passwd ){
			my $server = $self->connectionString() || 'localhost';
			my @words = split( /:/, $server );
			my $dsn = "DBI:Pg:";
			$dsn .= "database=$database" if $database;
			$dsn .= ";host=$words[0]" if $words[0];
			$dsn .= ";port=$words[1]" if $words[1];
			msgVerbose( __PACKAGE__."::_connect() dsn='$dsn'" );
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
	my $res = {
		ok => false,
		result => [],
		stdout => [],
		stderr => []
	};
	if( $command ){
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
	} else {
		msgErr( __PACKAGE__."::_sqlExec() command is mandatory, but is not specified" );
		TTP::stackTrace();
	}
	#print "res ".Dumper( $res );
	return $res;
}

### Public methods

# ------------------------------------------------------------------------------------------------
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
		# pg_dump dumps the database to stdout
		my $server = $self->server();
		my @words = split( /:/, $server );
		my $cmd = "PGPASSWORD=$passwd";
		$cmd .= " pg_dump";
		$cmd .= " --host=$words[0]" if $words[0];
		$cmd .= " --port=$words[1]" if $words[1];
		$cmd .= " --username=$account";
		$cmd .= " --inserts";
		$cmd .= " --dbname=$parms->{database}";
		if( $parms->{compress} ){
			$cmd .= " | gzip";
			$output .= ".gz";
		}
		$cmd .= " > $output";
		my $res = TTP::commandExec( $cmd );
		# pg_dump provides no output on stdout
		$result->{ok} = $res->{success};
		$result->{stderr} = $res->{stderr};
		#msgLog( __PACKAGE__."::backupDatabase() stdout='".TTP::chompDumper( $result->{stdout} )."'" );
		$result->{output} = $output;
	}

	msgVerbose( __PACKAGE__."::backupDatabase() returns '".( $result->{ok} ? 'true':'false' )."'" );
	return $result;
}

# ------------------------------------------------------------------------------------------------
# Get the different sizes of a database
# As PostgreSQL dynamically allocates its space, there is only one size to be provided
# (I):
# - database name
# (O):
# - returns a hash with four items { key, value } describing the six different sizes to be considered

sub databaseSize {
	my ( $self, $database ) = @_;
	my $result = {};
	my $dbh = $self->_connect( $database );
	if( $dbh ){
		# 1. Total database size
		my ( $db_size ) = $dbh->selectrow_array( 'SELECT pg_database_size(current_database());' );
		# 2. Total size of all user tables (Table size + indexes + TOAST)
		my ( $tables_size ) = $dbh->selectrow_array( q{
		    SELECT SUM( pg_total_relation_size( relid )) FROM pg_catalog.pg_statio_user_tables;
		});
		# 3. just the tables (no indexes)
		my ( $tables_woindex_size ) = $dbh->selectrow_array( q{
		    SELECT SUM( pg_relation_size( relid )) FROM pg_catalog.pg_statio_user_tables;
		});
		# 4. the indexes size
		my ( $indexes_size ) = $dbh->selectrow_array( q{
		    SELECT SUM( pg_indexes_size( relid )) FROM pg_catalog.pg_statio_user_tables;
		});
		# 5. tables + TOAST without indexes
		my ( $with_toast_size ) = $dbh->selectrow_array( q{
		    SELECT SUM( pg_table_size( relid )) FROM pg_catalog.pg_statio_user_tables;
		});
		$result->{dataSize} = $db_size;
		$result->{tablesFullSize} = $tables_size;
		$result->{tablesOnlySize} = $tables_woindex_size;
		$result->{tablesIndexSize} = $indexes_size;
		$result->{tablesToastSize} = $with_toast_size;
	} else {
		msgErr( __PACKAGE__."::databaseSize() unable to get a handle on '$database' database" );
	}
	return $result;
}

# ------------------------------------------------------------------------------------------------
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

# ------------------------------------------------------------------------------------------------
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

# ------------------------------------------------------------------------------------------------
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

# ------------------------------------------------------------------------------------------------
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
		#my $res = $self->_sqlExec( "SELECT datname FROM pg_database WHERE datistemplate = false;" );
		my $res = $self->_sqlExec( "SELECT datname FROM pg_database;" );
		foreach my $it ( @{$res->{result}} ){
			push( @{$databases}, { name => $it->{datname} });
		}
		$databases = $self->filterGotDatabases( $databases, $Const->{systemDatabases} );
	}

	return $databases || [];
}

# ------------------------------------------------------------------------------------------------
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
		# Get list of tables (only 'BASE TABLE' from 'public' schema)
		my $sth = $dbh->table_info( undef, undef, undef, 'TABLE' );
		while ( my $row = $sth->fetchrow_hashref ){
			if( !grep( /^$row->{TABLE_NAME}$/, @{$Const->{systemTables}} )){
				push( @{$tables}, "$row->{TABLE_SCHEM}.$row->{TABLE_NAME}" );
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

		# All server settings:
		# allow_in_place_tablespaces = off
		# allow_system_table_mods = off
		# application_name = 
		# archive_cleanup_command = 
		# archive_command = (disabled)
		# archive_library = 
		# archive_mode = off
		# archive_timeout = 0
		# array_nulls = on
		# authentication_timeout = 60
		# autovacuum = on
		# autovacuum_analyze_scale_factor = 0.1
		# autovacuum_analyze_threshold = 50
		# autovacuum_freeze_max_age = 200000000
		# autovacuum_max_workers = 3
		# autovacuum_multixact_freeze_max_age = 400000000
		# autovacuum_naptime = 60
		# autovacuum_vacuum_cost_delay = 2
		# autovacuum_vacuum_cost_limit =		#1
		# autovacuum_vacuum_insert_scale_factor = 0.2
		# autovacuum_vacuum_insert_threshold = 1000
		# autovacuum_vacuum_scale_factor = 0.2
		# autovacuum_vacuum_threshold = 50
		# autovacuum_work_mem =		#1
		# backend_flush_after = 0
		# backslash_quote = safe_encoding
		# backtrace_functions = 
		# bgwriter_delay = 200
		# bgwriter_flush_after = 64
		# bgwriter_lru_maxpages = 100
		# bgwriter_lru_multiplier = 2
		# block_size = 8192
		# bonjour = off
		# bonjour_name = 
		# bytea_output = hex
		# check_function_bodies = on
		# checkpoint_completion_target = 0.9
		# checkpoint_flush_after = 32
		# checkpoint_timeout = 300
		# checkpoint_warning = 30
		# client_connection_check_interval = 0
		# client_encoding = UTF8
		# client_min_messages = notice
		# cluster_name = 
		# commit_delay = 0
		# commit_siblings = 5
		# compute_query_id = auto
		# config_file = /var/lib/pgsql/16/data/postgresql.conf
		# constraint_exclusion = partition
		# cpu_index_tuple_cost = 0.005
		# cpu_operator_cost = 0.0025
		# cpu_tuple_cost = 0.01
		# createrole_self_grant = 
		# cursor_tuple_fraction = 0.1
		# data_checksums = off
		# data_directory = /var/lib/pgsql/16/data
		# data_directory_mode = 0700
		# data_sync_retry = off
		# DateStyle = ISO, MDY
		# db_user_namespace = off
		# deadlock_timeout = 1000
		# debug_assertions = off
		# debug_discard_caches = 0
		# debug_io_direct = 
		# debug_logical_replication_streaming = buffered
		# debug_parallel_query = off
		# debug_pretty_print = on
		# debug_print_parse = off
		# debug_print_plan = off
		# debug_print_rewritten = off
		# default_statistics_target = 100
		# default_table_access_method = heap
		# default_tablespace = 
		# default_text_search_config = pg_catalog.english
		# default_toast_compression = pglz
		# default_transaction_deferrable = off
		# default_transaction_isolation = read committed
		# default_transaction_read_only = off
		# dynamic_library_path = $libdir
		# dynamic_shared_memory_type = posix
		# effective_cache_size = 524288
		# effective_io_concurrency = 1
		# enable_async_append = on
		# enable_bitmapscan = on
		# enable_gathermerge = on
		# enable_hashagg = on
		# enable_hashjoin = on
		# enable_incremental_sort = on
		# enable_indexonlyscan = on
		# enable_indexscan = on
		# enable_material = on
		# enable_memoize = on
		# enable_mergejoin = on
		# enable_nestloop = on
		# enable_parallel_append = on
		# enable_parallel_hash = on
		# enable_partition_pruning = on
		# enable_partitionwise_aggregate = off
		# enable_partitionwise_join = off
		# enable_presorted_aggregate = on
		# enable_seqscan = on
		# enable_sort = on
		# enable_tidscan = on
		# escape_string_warning = on
		# event_source = PostgreSQL
		# exit_on_error = off
		# external_pid_file = 
		# extra_float_digits = 1
		# from_collapse_limit = 8
		# fsync = on
		# full_page_writes = on
		# geqo = on
		# geqo_effort = 5
		# geqo_generations = 0
		# geqo_pool_size = 0
		# geqo_seed = 0
		# geqo_selection_bias = 2
		# geqo_threshold = 12
		# gin_fuzzy_search_limit = 0
		# gin_pending_list_limit = 4096
		# gss_accept_delegation = off
		# hash_mem_multiplier = 2
		# hba_file = /var/lib/pgsql/16/data/pg_hba.conf
		# hot_standby = on
		# hot_standby_feedback = off
		# huge_page_size = 0
		# huge_pages = try
		# icu_validation_level = warning
		# ident_file = /var/lib/pgsql/16/data/pg_ident.conf
		# idle_in_transaction_session_timeout = 0
		# idle_session_timeout = 0
		# ignore_checksum_failure = off
		# ignore_invalid_pages = off
		# ignore_system_indexes = off
		# in_hot_standby = off
		# integer_datetimes = on
		# IntervalStyle = postgres
		# jit = on
		# jit_above_cost = 100000
		# jit_debugging_support = off
		# jit_dump_bitcode = off
		# jit_expressions = on
		# jit_inline_above_cost = 500000
		# jit_optimize_above_cost = 500000
		# jit_profiling_support = off
		# jit_provider = llvmjit
		# jit_tuple_deforming = on
		# join_collapse_limit = 8
		# krb_caseins_users = off
		# krb_server_keyfile = FILE:/etc/sysconfig/pgsql/krb5.keytab
		# lc_messages = C.UTF-8
		# lc_monetary = C.UTF-8
		# lc_numeric = C.UTF-8
		# lc_time = C.UTF-8
		# listen_addresses = *
		# lo_compat_privileges = off
		# local_preload_libraries = 
		# lock_timeout = 0
		# log_autovacuum_min_duration = 600000
		# log_checkpoints = on
		# log_connections = off
		# log_destination = stderr
		# log_directory = log
		# log_disconnections = off
		# log_duration = off
		# log_error_verbosity = default
		# log_executor_stats = off
		# log_file_mode = 0600
		# log_filename = postgresql-%a.log
		# log_hostname = off
		# log_line_prefix = %m [%p] 
		# log_lock_waits = off
		# log_min_duration_sample =		#1
		# log_min_duration_statement =		#1
		# log_min_error_statement = error
		# log_min_messages = warning
		# log_parameter_max_length =		#1
		# log_parameter_max_length_on_error = 0
		# log_parser_stats = off
		# log_planner_stats = off
		# log_recovery_conflict_waits = off
		# log_replication_commands = off
		# log_rotation_age = 1440
		# log_rotation_size = 0
		# log_startup_progress_interval = 10000
		# log_statement = none
		# log_statement_sample_rate = 1
		# log_statement_stats = off
		# log_temp_files =		#1
		# log_timezone = Europe/Paris
		# log_transaction_sample_rate = 0
		# log_truncate_on_rotation = on
		# logging_collector = on
		# logical_decoding_work_mem = 65536
		# maintenance_io_concurrency = 10
		# maintenance_work_mem = 65536
		# max_connections = 500
		# max_files_per_process = 1000
		# max_function_args = 100
		# max_identifier_length = 63
		# max_index_keys = 32
		# max_locks_per_transaction = 64
		# max_logical_replication_workers = 4
		# max_parallel_apply_workers_per_subscription = 2
		# max_parallel_maintenance_workers = 2
		# max_parallel_workers = 8
		# max_parallel_workers_per_gather = 2
		# max_pred_locks_per_page = 2
		# max_pred_locks_per_relation =		#2
		# max_pred_locks_per_transaction = 64
		# max_prepared_transactions = 0
		# max_replication_slots = 10
		# max_slot_wal_keep_size =		#1
		# max_stack_depth = 2048
		# max_standby_archive_delay = 30000
		# max_standby_streaming_delay = 30000
		# max_sync_workers_per_subscription = 2
		# max_wal_senders = 10
		# max_wal_size = 1024
		# max_worker_processes = 8
		# min_dynamic_shared_memory = 0
		# min_parallel_index_scan_size = 64
		# min_parallel_table_scan_size = 1024
		# min_wal_size = 80
		# old_snapshot_threshold =		#1
		# parallel_leader_participation = on
		# parallel_setup_cost = 1000
		# parallel_tuple_cost = 0.1
		# password_encryption = scram-sha-256
		# plan_cache_mode = auto
		# port = 5432
		# post_auth_delay = 0
		# pre_auth_delay = 0
		# primary_conninfo = 
		# primary_slot_name = 
		# quote_all_identifiers = off
		# random_page_cost = 4
		# recovery_end_command = 
		# recovery_init_sync_method = fsync
		# recovery_min_apply_delay = 0
		# recovery_prefetch = try
		# recovery_target = 
		# recovery_target_action = pause
		# recovery_target_inclusive = on
		# recovery_target_lsn = 
		# recovery_target_name = 
		# recovery_target_time = 
		# recovery_target_timeline = latest
		# recovery_target_xid = 
		# recursive_worktable_factor = 10
		# remove_temp_files_after_crash = on
		# reserved_connections = 0
		# restart_after_crash = on
		# restore_command = 
		# restrict_nonsystem_relation_kind = 
		# row_security = on
		# scram_iterations = 4096
		# search_path = "$user", public
		# segment_size = 131072
		# send_abort_for_crash = off
		# send_abort_for_kill = off
		# seq_page_cost = 1
		# server_encoding = UTF8
		# server_version = 16.9
		# server_version_num = 160009
		# session_preload_libraries = 
		# session_replication_role = origin
		# shared_buffers = 5000
		# shared_memory_size = 69
		# shared_memory_size_in_huge_pages = 35
		# shared_memory_type = mmap
		# shared_preload_libraries = 
		# ssl = off
		# ssl_ca_file = 
		# ssl_cert_file = server.crt
		# ssl_ciphers = HIGH:MEDIUM:+3DES:!aNULL
		# ssl_crl_dir = 
		# ssl_crl_file = 
		# ssl_dh_params_file = 
		# ssl_ecdh_curve = prime256v1
		# ssl_key_file = server.key
		# ssl_library = OpenSSL
		# ssl_max_protocol_version = 
		# ssl_min_protocol_version = TLSv1.2
		# ssl_passphrase_command = 
		# ssl_passphrase_command_supports_reload = off
		# ssl_prefer_server_ciphers = on
		# standard_conforming_strings = on
		# statement_timeout = 0
		# stats_fetch_consistency = cache
		# superuser_reserved_connections = 3
		# synchronize_seqscans = on
		# synchronous_commit = on
		# synchronous_standby_names = 
		# syslog_facility = local0
		# syslog_ident = postgres
		# syslog_sequence_numbers = on
		# syslog_split_messages = on
		# tcp_keepalives_count = 9
		# tcp_keepalives_idle = 7200
		# tcp_keepalives_interval = 75
		# tcp_user_timeout = 0
		# temp_buffers = 1024
		# temp_file_limit =		#1
		# temp_tablespaces = 
		# TimeZone = Europe/Paris
		# timezone_abbreviations = Default
		# trace_notify = off
		# trace_recovery_messages = log
		# trace_sort = off
		# track_activities = on
		# track_activity_query_size = 1024
		# track_commit_timestamp = off
		# track_counts = on
		# track_functions = none
		# track_io_timing = off
		# track_wal_io_timing = off
		# transaction_deferrable = off
		# transaction_isolation = read committed
		# transaction_read_only = off
		# transform_null_equals = off
		# unix_socket_directories = /run/postgresql, /tmp
		# unix_socket_group = 
		# unix_socket_permissions = 0777
		# update_process_title = on
		# vacuum_buffer_usage_limit = 256
		# vacuum_cost_delay = 0
		# vacuum_cost_limit = 200
		# vacuum_cost_page_dirty = 20
		# vacuum_cost_page_hit = 1
		# vacuum_cost_page_miss = 2
		# vacuum_failsafe_age = 1600000000
		# vacuum_freeze_min_age = 50000000
		# vacuum_freeze_table_age = 150000000
		# vacuum_multixact_failsafe_age = 1600000000
		# vacuum_multixact_freeze_min_age = 5000000
		# vacuum_multixact_freeze_table_age = 150000000
		# wal_block_size = 8192
		# wal_buffers = 156
		# wal_compression = off
		# wal_consistency_checking = 
		# wal_decode_buffer_size = 524288
		# wal_init_zero = on
		# wal_keep_size = 0
		# wal_level = replica
		# wal_log_hints = off
		# wal_receiver_create_temp_slot = off
		# wal_receiver_status_interval = 10
		# wal_receiver_timeout = 60000
		# wal_recycle = on
		# wal_retrieve_retry_interval = 5000
		# wal_segment_size = 16777216
		# wal_sender_timeout = 60000
		# wal_skip_threshold = 2048
		# wal_sync_method = fdatasync
		# wal_writer_delay = 200
		# wal_writer_flush_after = 128
		# work_mem = 4096
		# xmlbinary = base64
		# xmloption = content
		# zero_damaged_pages = off

		#my $sth = $dbh->prepare( 'SELECT name, setting FROM pg_settings;' );
        #$sth->execute();
        #print "All server settings:\n";
        #while ( my ( $name, $setting ) = $sth->fetchrow_array ){
		#	push( @{$props}, { name => $name, value => $setting });
        #}

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
	my $dbh = $self->_connect( $database );
	if( $dbh ){
		my $res = $self->_sqlExec( "select count(*) as count from $table", {
			dbh => $dbh
		});
		if( $res->{ok} ){
			$count = $res->{result}[0]{count};
		}
	}

	msgVerbose( __PACKAGE__."::getTableRowscount() database='$database' table='$table' count=$count" );
	return $count;
}

# ------------------------------------------------------------------------------------------------
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
	msgErr( __PACKAGE__."::restoreDatabase() '--verifyonly' option is not supported" ) if $parms->{verifyonly};
	msgErr( __PACKAGE__."::restoreDatabase() '--diff' option is not supported" ) if $parms->{diff};
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
		my $res = TTP::filter( "file $parms->{full}" );
		my $gziped = false;
		$gziped = true if grep( /gzip/, @{$res} );
		msgVerbose( __PACKAGE__."::restoreDatabase() found that provided dump file is ".( $gziped ? '' : 'NOT ' )."gzip'ed" );
		# and restore, making sure the database exists
		my $server = $self->server();
		my @words = split( /:/, $server );
		my $cmd = "(";
		$cmd .= " echo 'drop database if exists \"$parms->{database}\";';";
		$cmd .= " echo 'create database \"$parms->{database}\";';";
		$cmd .= " echo '\\c \"$parms->{database}\";';";
		$cmd .= $gziped ? " gzip -cd" : " cat";
		$cmd .= " $parms->{full} )";
		$cmd .= " | PGPASSWORD=$passwd psql";
		$cmd .= " --host=$words[0]" if $words[0];
		$cmd .= " --port=$words[1]" if $words[1];
		$cmd .= " --username=$account";
		$res = TTP::commandExec( $cmd );
		$result->{ok} = $res->{success};
		#$result->{stdout} = $res->{stderr};
		#msgLog( __PACKAGE__."::backupDatabase() stdout='".TTP::chompDumper( $result->{stdout} )."'" );
	}

	msgVerbose( __PACKAGE__."::restoreDatabase() result='".( $result->{ok} ? 'true' : 'false' )."'" );
	return $result;
}

### Class methods

# ------------------------------------------------------------------------------------------------
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

# ------------------------------------------------------------------------------------------------
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
