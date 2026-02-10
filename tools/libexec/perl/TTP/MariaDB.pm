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
		my( $account, $passwd ) = $self->_getCredentials( undef, { node => $self->hostingNode() });
		if( length $account && length $passwd ){
			my $server = $self->connectionString() || 'localhost';
			my @words = split( /:/, $server );
			my $dsn = "DBI:MariaDB:";
			$dsn .= $database if $database;
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
		my $cmd = "mariadb-dump";
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
		$result->{stderr} = $res->{stderrs};
		#msgLog( __PACKAGE__."::backupDatabase() stdout='".TTP::chompDumper( $result->{stdout} )."'" );
		$result->{output} = $output;
	}

	msgVerbose( __PACKAGE__."::backupDatabase() returns '".( $result->{ok} ? 'true':'false' )."'" );
	return $result;
}

# ------------------------------------------------------------------------------------------------
# Get the different sizes of a database
# (I):
# - database name
# (O):
# - returns a hash with two items { key, value } describing the six different sizes to be considered
#   may return undef if the table is fake

sub databaseSize {
	my ( $self, $database ) = @_;
	my $result = undef;
	my $dbh = $self->_connect( $database );
	if( $dbh ){
		my $sql = "select * from information_schema.tables where table_schema='$database'";
		my $res = $self->_sqlExec( $sql, {
			dbh => $dbh
		});
		if( $res->{ok} && scalar( @{$res->{result}} )){
			$sql = "select sum(data_length) as data_length,sum(index_length) as index_length from information_schema.tables where table_schema='$database'";
			$res = $self->_sqlExec( $sql, {
				dbh => $dbh
			});
			$result = {};
			$result->{dataSize} = $res->{result}[0]{data_length};
			$result->{indexSize} = $res->{result}[0]{index_length};
		}
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
		my $res = $self->_sqlExec( "show tables", { dbh => $dbh });
		if( $res->{ok} ){
			my $key = 'Tables_in_'.$database;
			foreach my $it ( @{$res->{result}} ){
				if( !grep( /^$it->{$key}$/, @{$Const->{systemTables}} )){
					push( @{$tables}, $it->{$key} );
				}
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
		# alter_algorithm = DEFAULT
		# analyze_sample_percentage = 100.000000
		# aria_block_size = 8192
		# aria_checkpoint_interval = 30
		# aria_checkpoint_log_activity = 1048576
		# aria_encrypt_tables = OFF
		# aria_force_start_after_recovery_failures = 0
		# aria_group_commit = none
		# aria_group_commit_interval = 0
		# aria_log_dir_path = /opt/zextras/db/data/
		# aria_log_file_size = 1073741824
		# aria_log_purge_type = immediate
		# aria_max_sort_file_size = 9223372036853727232
		# aria_page_checksum = ON
		# aria_pagecache_age_threshold = 300
		# aria_pagecache_buffer_size = 134217728
		# aria_pagecache_division_limit = 100
		# aria_pagecache_file_hash_size = 512
		# aria_recover_options = BACKUP,QUICK
		# aria_repair_threads = 1
		# aria_sort_buffer_size = 268434432
		# aria_stats_method = nulls_unequal
		# aria_sync_log_dir = NEWFILE
		# aria_used_for_temp_tables = ON
		# auto_increment_increment = 1
		# auto_increment_offset = 1
		# autocommit = ON
		# automatic_sp_privileges = ON
		# back_log = 72
		# basedir = /opt/zextras/common
		# big_tables = OFF
		# bind_address = 127.0.0.1
		# binlog_annotate_row_events = ON
		# binlog_cache_size = 32768
		# binlog_checksum = CRC32
		# binlog_commit_wait_count = 0
		# binlog_commit_wait_usec = 100000
		# binlog_direct_non_transactional_updates = OFF
		# binlog_file_cache_size = 16384
		# binlog_format = MIXED
		# binlog_optimize_thread_scheduling = ON
		# binlog_row_image = FULL
		# binlog_row_metadata = NO_LOG
		# binlog_stmt_cache_size = 32768
		# bulk_insert_buffer_size = 8388608
		# character_set_client = utf8mb4
		# character_set_connection = utf8mb4
		# character_set_database = latin1
		# character_set_filesystem = binary
		# character_set_results = utf8mb4
		# character_set_server = utf8mb4
		# character_set_system = utf8
		# character_sets_dir = /opt/zextras/common/share/mysql/charsets/
		# check_constraint_checks = ON
		# collation_connection = utf8mb4_unicode_ci
		# collation_database = latin1_swedish_ci
		# collation_server = utf8mb4_unicode_ci
		# column_compression_threshold = 100
		# column_compression_zlib_level = 6
		# column_compression_zlib_strategy = DEFAULT_STRATEGY
		# column_compression_zlib_wrap = OFF
		# completion_type = NO_CHAIN
		# concurrent_insert = AUTO
		# connect_timeout = 10
		# core_file = OFF
		# datadir = /opt/zextras/db/data/
		# date_format = %Y-%m-%d
		# datetime_format = %Y-%m-%d %H:%i:%s
		# deadlock_search_depth_long = 15
		# deadlock_search_depth_short = 4
		# deadlock_timeout_long = 50000000
		# deadlock_timeout_short = 10000
		# debug_no_thread_alarm = OFF
		# default_master_connection = 
		# default_password_lifetime = 0
		# default_regex_flags = 
		# default_storage_engine = InnoDB
		# default_tmp_storage_engine = 
		# default_week_format = 0
		# delay_key_write = ON
		# delayed_insert_limit = 100
		# delayed_insert_timeout = 300
		# delayed_queue_size = 1000
		# disconnect_on_expired_password = OFF
		# div_precision_increment = 4
		# encrypt_binlog = OFF
		# encrypt_tmp_disk_tables = OFF
		# encrypt_tmp_files = OFF
		# enforce_storage_engine = 
		# eq_range_index_dive_limit = 200
		# error_count = 0
		# event_scheduler = OFF
		# expensive_subquery_limit = 100
		# expire_logs_days = 0
		# explicit_defaults_for_timestamp = OFF
		# external_user = 
		# extra_max_connections = 1
		# extra_port = 0
		# flush = OFF
		# flush_time = 0
		# foreign_key_checks = ON
		# ft_boolean_syntax = +		#><()~*:""&|
		# ft_max_word_len = 84
		# ft_min_word_len = 4
		# ft_query_expansion_limit = 20
		# ft_stopword_file = (built-in)
		# general_log = OFF
		# general_log_file = /opt/zextras/log/mysql-mailboxd.log
		# group_concat_max_len = 1048576
		# gtid_binlog_pos = 
		# gtid_binlog_state = 
		# gtid_cleanup_batch_size = 64
		# gtid_current_pos = 
		# gtid_domain_id = 0
		# gtid_ignore_duplicates = OFF
		# gtid_pos_auto_engines = 
		# gtid_seq_no = 0
		# gtid_slave_pos = 
		# gtid_strict_mode = OFF
		# have_compress = YES
		# have_crypt = YES
		# have_dynamic_loading = YES
		# have_geometry = YES
		# have_openssl = YES
		# have_profiling = YES
		# have_query_cache = YES
		# have_rtree_keys = YES
		# have_ssl = DISABLED
		# have_symlink = YES
		# histogram_size = 254
		# histogram_type = DOUBLE_PREC_HB
		# host_cache_size = 238
		# hostname = zimbra9.trychlos.lan
		# identity = 0
		# idle_readonly_transaction_timeout = 0
		# idle_transaction_timeout = 0
		# idle_write_transaction_timeout = 0
		# ignore_builtin_innodb = OFF
		# ignore_db_dirs = 
		# in_predicate_conversion_threshold = 1000
		# in_transaction = 0
		# init_connect = 
		# init_file = 
		# init_slave = 
		# innodb_adaptive_flushing = ON
		# innodb_adaptive_flushing_lwm = 10.000000
		# innodb_adaptive_hash_index = OFF
		# innodb_adaptive_hash_index_parts = 8
		# innodb_adaptive_max_sleep_delay = 0
		# innodb_autoextend_increment = 64
		# innodb_autoinc_lock_mode = 1
		# innodb_background_scrub_data_check_interval = 0
		# innodb_background_scrub_data_compressed = OFF
		# innodb_background_scrub_data_interval = 0
		# innodb_background_scrub_data_uncompressed = OFF
		# innodb_buf_dump_status_frequency = 0
		# innodb_buffer_pool_chunk_size = 134217728
		# innodb_buffer_pool_dump_at_shutdown = ON
		# innodb_buffer_pool_dump_now = OFF
		# innodb_buffer_pool_dump_pct = 25
		# innodb_buffer_pool_filename = ib_buffer_pool
		# innodb_buffer_pool_instances = 1
		# innodb_buffer_pool_load_abort = OFF
		# innodb_buffer_pool_load_at_startup = ON
		# innodb_buffer_pool_load_now = OFF
		# innodb_buffer_pool_size = 2415919104
		# innodb_change_buffer_max_size = 25
		# innodb_change_buffering = none
		# innodb_checksum_algorithm = full_crc32
		# innodb_cmp_per_index_enabled = OFF
		# innodb_commit_concurrency = 0
		# innodb_compression_algorithm = zlib
		# innodb_compression_default = OFF
		# innodb_compression_failure_threshold_pct = 5
		# innodb_compression_level = 6
		# innodb_compression_pad_pct_max = 50
		# innodb_concurrency_tickets = 0
		# innodb_data_file_path = ibdata1:10M:autoextend
		# innodb_data_home_dir = 
		# innodb_deadlock_detect = ON
		# innodb_default_encryption_key_id = 1
		# innodb_default_row_format = dynamic
		# innodb_defragment = OFF
		# innodb_defragment_fill_factor = 0.900000
		# innodb_defragment_fill_factor_n_recs = 20
		# innodb_defragment_frequency = 40
		# innodb_defragment_n_pages = 7
		# innodb_defragment_stats_accuracy = 0
		# innodb_disable_sort_file_cache = OFF
		# innodb_doublewrite = ON
		# innodb_encrypt_log = OFF
		# innodb_encrypt_tables = OFF
		# innodb_encrypt_temporary_tables = OFF
		# innodb_encryption_rotate_key_age = 1
		# innodb_encryption_rotation_iops = 100
		# innodb_encryption_threads = 0
		# innodb_fast_shutdown = 1
		# innodb_fatal_semaphore_wait_threshold = 600
		# innodb_file_format = 
		# innodb_file_per_table = ON
		# innodb_fill_factor = 100
		# innodb_flush_log_at_timeout = 1
		# innodb_flush_log_at_trx_commit = 0
		# innodb_flush_method = O_DIRECT
		# innodb_flush_neighbors = 1
		# innodb_flush_sync = ON
		# innodb_flushing_avg_loops = 30
		# innodb_force_load_corrupted = OFF
		# innodb_force_primary_key = OFF
		# innodb_force_recovery = 0
		# innodb_ft_aux_table = 
		# innodb_ft_cache_size = 8000000
		# innodb_ft_enable_diag_print = OFF
		# innodb_ft_enable_stopword = ON
		# innodb_ft_max_token_size = 84
		# innodb_ft_min_token_size = 3
		# innodb_ft_num_word_optimize = 2000
		# innodb_ft_result_cache_limit = 2000000000
		# innodb_ft_server_stopword_table = 
		# innodb_ft_sort_pll_degree = 2
		# innodb_ft_total_cache_size = 640000000
		# innodb_ft_user_stopword_table = 
		# innodb_immediate_scrub_data_uncompressed = OFF
		# innodb_instant_alter_column_allowed = add_drop_reorder
		# innodb_io_capacity = 200
		# innodb_io_capacity_max = 2000
		# innodb_large_prefix = 
		# innodb_lock_schedule_algorithm = fcfs
		# innodb_lock_wait_timeout = 50
		# innodb_log_buffer_size = 8388608
		# innodb_log_checksums = ON
		# innodb_log_compressed_pages = ON
		# innodb_log_file_size = 524288000
		# innodb_log_files_in_group = 1
		# innodb_log_group_home_dir = ./
		# innodb_log_optimize_ddl = OFF
		# innodb_log_write_ahead_size = 8192
		# innodb_lru_flush_size = 32
		# innodb_lru_scan_depth = 1536
		# innodb_max_dirty_pages_pct = 30.000000
		# innodb_max_dirty_pages_pct_lwm = 0.000000
		# innodb_max_purge_lag = 0
		# innodb_max_purge_lag_delay = 0
		# innodb_max_purge_lag_wait = 4294967295
		# innodb_max_undo_log_size = 10485760
		# innodb_monitor_disable = 
		# innodb_monitor_enable = 
		# innodb_monitor_reset = 
		# innodb_monitor_reset_all = 
		# innodb_old_blocks_pct = 37
		# innodb_old_blocks_time = 1000
		# innodb_online_alter_log_max_size = 134217728
		# innodb_open_files = 2710
		# innodb_optimize_fulltext_only = OFF
		# innodb_page_cleaners = 1
		# innodb_page_size = 16384
		# innodb_prefix_index_cluster_optimization = OFF
		# innodb_print_all_deadlocks = OFF
		# innodb_purge_batch_size = 300
		# innodb_purge_rseg_truncate_frequency = 128
		# innodb_purge_threads = 4
		# innodb_random_read_ahead = OFF
		# innodb_read_ahead_threshold = 56
		# innodb_read_io_threads = 4
		# innodb_read_only = OFF
		# innodb_replication_delay = 0
		# innodb_rollback_on_timeout = OFF
		# innodb_scrub_log = OFF
		# innodb_scrub_log_speed = 256
		# innodb_sort_buffer_size = 1048576
		# innodb_spin_wait_delay = 4
		# innodb_stats_auto_recalc = ON
		# innodb_stats_include_delete_marked = OFF
		# innodb_stats_method = nulls_equal
		# innodb_stats_modified_counter = 0
		# innodb_stats_on_metadata = OFF
		# innodb_stats_persistent = ON
		# innodb_stats_persistent_sample_pages = 20
		# innodb_stats_traditional = ON
		# innodb_stats_transient_sample_pages = 8
		# innodb_status_output = OFF
		# innodb_status_output_locks = OFF
		# innodb_strict_mode = ON
		# innodb_sync_array_size = 1
		# innodb_sync_spin_loops = 30
		# innodb_table_locks = ON
		# innodb_temp_data_file_path = ibtmp1:12M:autoextend
		# innodb_thread_concurrency = 0
		# innodb_thread_sleep_delay = 0
		# innodb_tmpdir = 
		# innodb_undo_directory = ./
		# innodb_undo_log_truncate = OFF
		# innodb_undo_logs = 128
		# innodb_undo_tablespaces = 0
		# innodb_use_atomic_writes = ON
		# innodb_use_native_aio = ON
		# innodb_version = 10.5.28
		# innodb_write_io_threads = 4
		# insert_id = 0
		# interactive_timeout = 28800
		# join_buffer_size = 262144
		# join_buffer_space_limit = 2097152
		# join_cache_level = 2
		# keep_files_on_create = OFF
		# key_buffer_size = 134217728
		# key_cache_age_threshold = 300
		# key_cache_block_size = 1024
		# key_cache_division_limit = 100
		# key_cache_file_hash_size = 512
		# key_cache_segments = 0
		# large_files_support = ON
		# large_page_size = 0
		# large_pages = OFF
		# last_gtid = 
		# last_insert_id = 0
		# lc_messages = en_US
		# lc_messages_dir = 
		# lc_time_names = en_US
		# license = GPL
		# local_infile = ON
		# lock_wait_timeout = 86400
		# locked_in_memory = OFF
		# log_bin = OFF
		# log_bin_basename = 
		# log_bin_compress = OFF
		# log_bin_compress_min_len = 256
		# log_bin_index = 
		# log_bin_trust_function_creators = OFF
		# log_disabled_statements = sp
		# log_error = /opt/zextras/log/mysql_error.log
		# log_output = FILE
		# log_queries_not_using_indexes = ON
		# log_slave_updates = OFF
		# log_slow_admin_statements = ON
		# log_slow_disabled_statements = sp
		# log_slow_filter = admin,filesort,filesort_on_disk,filesort_priority_queue,full_join,full_scan,not_using_index,query_cache,query_cache_miss,tmp_table,tmp_table_on_disk
		# log_slow_rate_limit = 1
		# log_slow_slave_statements = ON
		# log_slow_verbosity = 
		# log_tc_size = 24576
		# log_warnings = 2
		# long_query_time = 1.000000
		# low_priority_updates = OFF
		# lower_case_file_system = OFF
		# lower_case_table_names = 0
		# master_verify_checksum = OFF
		# max_allowed_packet = 16777216
		# max_binlog_cache_size = 18446744073709547520
		# max_binlog_size = 1073741824
		# max_binlog_stmt_cache_size = 18446744073709547520
		# max_connect_errors = 100
		# max_connections = 110
		# max_delayed_threads = 20
		# max_digest_length = 1024
		# max_error_count = 64
		# max_heap_table_size = 16777216
		# max_insert_delayed_threads = 20
		# max_join_size = 18446744073709551615
		# max_length_for_sort_data = 1024
		# max_password_errors = 4294967295
		# max_prepared_stmt_count = 16382
		# max_recursive_iterations = 4294967295
		# max_relay_log_size = 1073741824
		# max_rowid_filter_size = 131072
		# max_seeks_for_key = 4294967295
		# max_session_mem_used = 9223372036854775807
		# max_sort_length = 1024
		# max_sp_recursion_depth = 0
		# max_statement_time = 0.000000
		# max_tmp_tables = 32
		# max_user_connections = 0
		# max_write_lock_count = 4294967295
		# metadata_locks_cache_size = 1024
		# metadata_locks_hash_instances = 8
		# min_examined_row_limit = 0
		# mrr_buffer_size = 262144
		# myisam_block_size = 1024
		# myisam_data_pointer_size = 6
		# myisam_max_sort_file_size = 9223372036853727232
		# myisam_mmap_size = 18446744073709551615
		# myisam_recover_options = BACKUP,QUICK
		# myisam_repair_threads = 1
		# myisam_sort_buffer_size = 134216704
		# myisam_stats_method = NULLS_UNEQUAL
		# myisam_use_mmap = OFF
		# mysql56_temporal_format = ON
		# net_buffer_length = 16384
		# net_read_timeout = 30
		# net_retry_count = 10
		# net_write_timeout = 60
		# old = OFF
		# old_alter_table = DEFAULT
		# old_mode = 
		# old_passwords = OFF
		# open_files_limit = 19349
		# optimizer_adjust_secondary_key_costs = fix_card_multiplier
		# optimizer_max_sel_arg_weight = 32000
		# optimizer_prune_level = 1
		# optimizer_search_depth = 62
		# optimizer_selectivity_sampling_limit = 100
		# optimizer_switch = index_merge=on,index_merge_union=on,index_merge_sort_union=on,index_merge_intersection=on,index_merge_sort_intersection=off,engine_condition_pushdown=off,index_condition_pushdown=on,derived_merge=on,derived_with_keys=on,firstmatch=on,loosescan=on,materialization=on,in_to_exists=on,semijoin=on,partial_match_rowid_merge=on,partial_match_table_scan=on,subquery_cache=on,mrr=off,mrr_cost_based=off,mrr_sort_keys=off,outer_join_with_cache=on,semijoin_with_cache=on,join_cache_incremental=on,join_cache_hashed=on,join_cache_bka=on,optimize_join_buffer_size=on,table_elimination=on,extended_keys=on,exists_to_in=on,orderby_uses_equalities=on,condition_pushdown_for_derived=on,split_materialized=on,condition_pushdown_for_subquery=on,rowid_filter=on,condition_pushdown_from_having=on,not_null_range_scan=off
		# optimizer_trace = enabled=off
		# optimizer_trace_max_mem_size = 1048576
		# optimizer_use_condition_selectivity = 4
		# performance_schema = OFF
		# performance_schema_accounts_size =		#1
		# performance_schema_digests_size =		#1
		# performance_schema_events_stages_history_long_size =		#1
		# performance_schema_events_stages_history_size =		#1
		# performance_schema_events_statements_history_long_size =		#1
		# performance_schema_events_statements_history_size =		#1
		# performance_schema_events_transactions_history_long_size =		#1
		# performance_schema_events_transactions_history_size =		#1
		# performance_schema_events_waits_history_long_size =		#1
		# performance_schema_events_waits_history_size =		#1
		# performance_schema_hosts_size =		#1
		# performance_schema_max_cond_classes = 90
		# performance_schema_max_cond_instances =		#1
		# performance_schema_max_digest_length = 1024
		# performance_schema_max_file_classes = 80
		# performance_schema_max_file_handles = 32768
		# performance_schema_max_file_instances =		#1
		# performance_schema_max_index_stat =		#1
		# performance_schema_max_memory_classes = 320
		# performance_schema_max_metadata_locks =		#1
		# performance_schema_max_mutex_classes = 210
		# performance_schema_max_mutex_instances =		#1
		# performance_schema_max_prepared_statements_instances =		#1
		# performance_schema_max_program_instances =		#1
		# performance_schema_max_rwlock_classes = 50
		# performance_schema_max_rwlock_instances =		#1
		# performance_schema_max_socket_classes = 10
		# performance_schema_max_socket_instances =		#1
		# performance_schema_max_sql_text_length = 1024
		# performance_schema_max_stage_classes = 160
		# performance_schema_max_statement_classes = 222
		# performance_schema_max_statement_stack = 10
		# performance_schema_max_table_handles =		#1
		# performance_schema_max_table_instances =		#1
		# performance_schema_max_table_lock_stat =		#1
		# performance_schema_max_thread_classes = 50
		# performance_schema_max_thread_instances =		#1
		# performance_schema_session_connect_attrs_size =		#1
		# performance_schema_setup_actors_size =		#1
		# performance_schema_setup_objects_size =		#1
		# performance_schema_users_size =		#1
		# pid_file = /run/carbonio/mysql.pid
		# plugin_dir = /opt/zextras/common/lib/plugin/
		# plugin_maturity = gamma
		# port = 7306
		# preload_buffer_size = 32768
		# profiling = OFF
		# profiling_history_size = 15
		# progress_report_time = 5
		# protocol_version = 10
		# proxy_protocol_networks = 
		# proxy_user = 
		# pseudo_slave_mode = OFF
		# pseudo_thread_id = 12391
		# query_alloc_block_size = 16384
		# query_cache_limit = 1048576
		# query_cache_min_res_unit = 4096
		# query_cache_size = 1048576
		# query_cache_strip_comments = OFF
		# query_cache_type = OFF
		# query_cache_wlock_invalidate = OFF
		# query_prealloc_size = 24576
		# rand_seed1 = 1060613348
		# rand_seed2 = 238488079
		# range_alloc_block_size = 4096
		# read_binlog_speed_limit = 0
		# read_buffer_size = 1048576
		# read_only = OFF
		# read_rnd_buffer_size = 262144
		# relay_log = 
		# relay_log_basename = 
		# relay_log_index = 
		# relay_log_info_file = relay-log.info
		# relay_log_purge = ON
		# relay_log_recovery = OFF
		# relay_log_space_limit = 0
		# replicate_annotate_row_events = ON
		# replicate_do_db = 
		# replicate_do_table = 
		# replicate_events_marked_for_skip = REPLICATE
		# replicate_ignore_db = 
		# replicate_ignore_table = 
		# replicate_wild_do_table = 
		# replicate_wild_ignore_table = 
		# report_host = 
		# report_password = 
		# report_port = 7306
		# report_user = 
		# require_secure_transport = OFF
		# rowid_merge_buff_size = 8388608
		# rpl_semi_sync_master_enabled = OFF
		# rpl_semi_sync_master_timeout = 10000
		# rpl_semi_sync_master_trace_level = 32
		# rpl_semi_sync_master_wait_no_slave = ON
		# rpl_semi_sync_master_wait_point = AFTER_COMMIT
		# rpl_semi_sync_slave_delay_master = OFF
		# rpl_semi_sync_slave_enabled = OFF
		# rpl_semi_sync_slave_kill_conn_timeout = 5
		# rpl_semi_sync_slave_trace_level = 32
		# secure_auth = ON
		# secure_file_priv = 
		# secure_timestamp = NO
		# server_id = 1
		# server_uid = EciIEsr681Wlw7kRRmkOnfdmi1c=
		# session_track_schema = ON
		# session_track_state_change = OFF
		# session_track_system_variables = autocommit,character_set_client,character_set_connection,character_set_results,time_zone
		# session_track_transaction_info = OFF
		# skip_external_locking = OFF
		# skip_name_resolve = OFF
		# skip_networking = OFF
		# skip_parallel_replication = OFF
		# skip_replication = OFF
		# skip_show_database = OFF
		# slave_compressed_protocol = OFF
		# slave_ddl_exec_mode = IDEMPOTENT
		# slave_domain_parallel_threads = 0
		# slave_exec_mode = STRICT
		# slave_load_tmpdir = /opt/zextras/data/tmp
		# slave_max_allowed_packet = 1073741824
		# slave_net_timeout = 60
		# slave_parallel_max_queued = 131072
		# slave_parallel_mode = optimistic
		# slave_parallel_threads = 0
		# slave_parallel_workers = 0
		# slave_run_triggers_for_rbr = NO
		# slave_skip_errors = OFF
		# slave_sql_verify_checksum = ON
		# slave_transaction_retries = 10
		# slave_transaction_retry_errors = 1158,1159,1160,1161,1205,1213,1429,2013,12701
		# slave_transaction_retry_interval = 0
		# slave_type_conversions = 
		# slow_launch_time = 2
		# slow_query_log = ON
		# slow_query_log_file = /opt/zextras/log/myslow.log
		# socket = /run/carbonio/mysql.sock
		# sort_buffer_size = 1048576
		# sql_auto_is_null = OFF
		# sql_big_selects = ON
		# sql_buffer_result = OFF
		# sql_if_exists = OFF
		# sql_log_bin = ON
		# sql_log_off = OFF
		# sql_mode = STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION
		# sql_notes = ON
		# sql_quote_show_create = ON
		# sql_safe_updates = OFF
		# sql_select_limit = 18446744073709551615
		# sql_slave_skip_counter = 0
		# sql_warnings = OFF
		# ssl_ca = 
		# ssl_capath = 
		# ssl_cert = 
		# ssl_cipher = 
		# ssl_crl = 
		# ssl_crlpath = 
		# ssl_key = 
		# standard_compliant_cte = ON
		# storage_engine = InnoDB
		# stored_program_cache = 256
		# strict_password_validation = ON
		# sync_binlog = 0
		# sync_frm = ON
		# sync_master_info = 10000
		# sync_relay_log = 10000
		# sync_relay_log_info = 10000
		# system_time_zone = CEST
		# system_versioning_alter_history = ERROR
		# system_versioning_asof = DEFAULT
		# table_definition_cache = 400
		# table_open_cache = 1200
		# table_open_cache_instances = 8
		# tcp_keepalive_interval = 0
		# tcp_keepalive_probes = 0
		# tcp_keepalive_time = 0
		# tcp_nodelay = ON
		# thread_cache_size = 110
		# thread_handling = one-thread-per-connection
		# thread_pool_dedicated_listener = OFF
		# thread_pool_exact_stats = OFF
		# thread_pool_idle_timeout = 60
		# thread_pool_max_threads = 65536
		# thread_pool_oversubscribe = 3
		# thread_pool_prio_kickup_timer = 1000
		# thread_pool_priority = auto
		# thread_pool_size = 8
		# thread_pool_stall_limit = 500
		# thread_stack = 299008
		# time_format = %H:%i:%s
		# time_zone = SYSTEM
		# timestamp = 1748261027.032438
		# tls_version = TLSv1.2,TLSv1.3
		# tmp_disk_table_size = 18446744073709551615
		# tmp_memory_table_size = 16777216
		# tmp_table_size = 16777216
		# tmpdir = /opt/zextras/data/tmp
		# transaction_alloc_block_size = 8192
		# transaction_prealloc_size = 4096
		# tx_isolation = REPEATABLE-READ
		# tx_read_only = OFF
		# unique_checks = ON
		# updatable_views_with_limit = YES
		# use_stat_tables = PREFERABLY_FOR_QUERIES
		# userstat = OFF
		# version = 10.5.28-MariaDB-log
		# version_comment = Zextras MariaDB binary distribution
		# version_compile_machine = x86_64
		# version_compile_os = Linux
		# version_malloc_library = jemalloc 5.3.0-0-g54eaed1d8b56b1aa528be3bdd1877e59c56fa90c
		# version_source_revision = 7eded23be6597b4c485e8cad1538f2ae14541f91
		# version_ssl_library = OpenSSL 3.0.15 3 Sep 2024
		# wait_timeout = 28800
		# warning_count = 0
		# wsrep_osu_method = TOI
		# wsrep_sr_store = table
		# wsrep_auto_increment_control = ON
		# wsrep_causal_reads = OFF
		# wsrep_certification_rules = strict
		# wsrep_certify_nonpk = ON
		# wsrep_cluster_address = 
		# wsrep_cluster_name = my_wsrep_cluster
		# wsrep_convert_lock_to_trx = OFF
		# wsrep_data_home_dir = /opt/zextras/db/data/
		# wsrep_dbug_option = 
		# wsrep_debug = NONE
		# wsrep_desync = OFF
		# wsrep_dirty_reads = OFF
		# wsrep_drupal_282555_workaround = OFF
		# wsrep_forced_binlog_format = NONE
		# wsrep_gtid_domain_id = 0
		# wsrep_gtid_mode = OFF
		# wsrep_gtid_seq_no = 0
		# wsrep_ignore_apply_errors = 7
		# wsrep_load_data_splitting = OFF
		# wsrep_log_conflicts = OFF
		# wsrep_max_ws_rows = 0
		# wsrep_max_ws_size = 2147483647
		# wsrep_mysql_replication_bundle = 0
		# wsrep_node_address = 
		# wsrep_node_incoming_address = AUTO
		# wsrep_node_name = zimbra9.trychlos.lan
		# wsrep_notify_cmd = 
		# wsrep_on = OFF
		# wsrep_patch_version = wsrep_26.22
		# wsrep_provider = none
		# wsrep_provider_options = 
		# wsrep_recover = OFF
		# wsrep_reject_queries = NONE
		# wsrep_replicate_myisam = OFF
		# wsrep_restart_slave = OFF
		# wsrep_retry_autocommit = 1
		# wsrep_slave_fk_checks = ON
		# wsrep_slave_uk_checks = OFF
		# wsrep_slave_threads = 1
		# wsrep_sst_auth = 
		# wsrep_sst_donor = 
		# wsrep_sst_donor_rejects_queries = OFF
		# wsrep_sst_method = rsync
		# wsrep_sst_receive_address = AUTO
		# wsrep_start_position = 00000000-0000-0000-0000-000000000000:-1
		# wsrep_strict_ddl = OFF
		# wsrep_sync_wait = 0
		# wsrep_trx_fragment_size = 0
		# wsrep_trx_fragment_unit = bytes
		
		#my $sth = $dbh->prepare( 'SHOW VARIABLES;' );
        #$sth->execute();
        #while ( my ( $name, $value ) = $sth->fetchrow_array ){
		#	push( @{$props}, { name => $name, value => $value });
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
	my $sql = "select count(*) as count from $database.$table";
	my $res = $self->_sqlExec( $sql );
	if( $res->{ok} ){
		$count = $res->{result}[0]{count};
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
