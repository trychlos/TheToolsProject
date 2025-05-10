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
# A package dedicated to Microsoft SQL-Server

package TTP::SqlServer;
die __PACKAGE__ . " must be loaded as TTP::SqlServer\n" unless __PACKAGE__ eq 'TTP::SqlServer';

use base qw( TTP::DBMS );
our $VERSION = '1.00';

use strict;
use utf8;
use warnings;

use Config;
use Capture::Tiny qw( :all );
use Data::Dumper;
use File::Spec;
use Path::Tiny;
use Time::Moment;
use if $Config{osname} eq 'MSWin32', "Win32::SqlServer", qw( :DEFAULT :consts );

use TTP;
use TTP::Constants qw( :all );
use TTP::Credentials;
use TTP::Message qw( :all );

my $Const = {
	# the list of system databases to be excluded
	systemDatabases => [
		'master',
		'tempdb',
		'model',
		'msdb'
	],
	# the list of system tables to be excluded
	systemTables => [
		'dtproperties',
		'sysdiagrams'
	]
};

### Private methods

# ------------------------------------------------------------------------------------------------
# get a connection to a local SqlServer instance
# (I):
# - the DBMS instance
# (O):
# - an opaque handle on the connection, or undef

sub _connect {
	my ( $self ) = @_;

	my $handle = $self->{_dbms}{connect};
	if( $handle ){
		msgVerbose( __PACKAGE__."::_connect() already connected" );

	} else {
		my( $account, $passwd ) = $self->_getCredentials();
		#print STDERR __PACKAGE__."::_connect() got account='$account' password='$passwd'".EOL;
		if( length $account && length $passwd ){
			Win32::SqlServer::SetDefaultForEncryption( 'Optional', true );
			# SQLServer 2008R2 doesn't like have a server connection string with MSSQLSERVER default instance -> obsoleted
			# SQLServer 2012 doesn't like connect to localhost:1433, but rather wants the COMPUTERNAME
			my $server = $self->server();
			msgVerbose( __PACKAGE__."::_connect() calling sql_init with server='".( $server || '(undef)' )."', account='$account'..." );
			$handle = Win32::SqlServer::sql_init( $server, $account, $passwd );
			if( $handle && $handle->isconnected()){
				$handle->{ErrInfo}{MaxSeverity} = 17;
				$handle->{ErrInfo}{SaveMessages} = 1;
				$self->{_dbms}{connect} = $handle;
				#print STDERR Dumper( $handle );
				msgVerbose( __PACKAGE__."::_connect() successfully connected" );
			} else {
				msgErr( __PACKAGE__."::_connect() unable to connect to the server" );
				$handle = undef;
			}
		} else {
			msgErr( __PACKAGE__."::_connect() unable to get account/password couple" );
		}
	}

	return $handle;
}

# -------------------------------------------------------------------------------------------------
# restore the target database from the specified backup file
# (I):
# - parms is a hash ref with keys:
#   > database: mandatory
#   > file: mandatory
#   > last: mandatory
# (O):
# - returns the needed 'MOVE' sentence

sub _restoreFile {
	my ( $self, $parms ) = @_;

	my $database = $parms->{database};
	my $fname = $parms->{file};
	my $last = $parms->{last};

	msgVerbose(  __PACKAGE__."::_restoreFile() restoring $fname" );
	my $recovery = 'NORECOVERY';
	if( $last ){
		$recovery = 'RECOVERY';
	}
	my $move = $self->_restoreMove( $parms );
	my $result = true;
	if( $move ){
		my $res = $self->_sqlExec( "RESTORE DATABASE $database FROM DISK='$fname' WITH $recovery, $move;" );
		msgLog( __PACKAGE__."::_restoreFile() stdout='".TTP::chompDumper( $res->{stdout} )."'" );
		$result = $res->{ok};
	}

	return $result;
}

# -------------------------------------------------------------------------------------------------
# returns the move option in case of the datapath is different from the source or when the target
# database has changed
# (I):
# - parms is a hash ref with keys:
#   > database: mandatory
#   > file: mandatory
# (O):
# - returns the needed 'MOVE' sentence

sub _restoreMove {
	my ( $self, $parms ) = @_;

	my $database = $parms->{database};
	my $fname = $parms->{file};
	msgVerbose( __PACKAGE__."::_restoreMove() database='$database'" );

	my $result = $self->_sqlExec( "RESTORE FILELISTONLY FROM DISK='$fname'" );
	my $move = undef;
	if( $self->ep()->runner()->dummy()){
		msgDummy( "considering nomove" );
	} elsif( !scalar @{$result->{result}} ){
		msgErr( __PACKAGE__."::_restoreMove() unable to get the files list of the backup set" );
	} else {
		# starting with v4.11, dataPath no more comes from the configuration, but is dynamically read from SqlServer
		#my $sqlDataPath = $self->service()->var([ 'DBMS', 'dataPath' ]);
		my $res = $self->_sqlExec( "select InstanceDefaultDataPath = serverproperty( 'InstanceDefaultDataPath' )" );
		my $sqlDataPath = $res->{result}[0]{InstanceDefaultDataPath};
		foreach( @{$result->{result}} ){
			my $row = $_;
			$move .= ', ' if length $move;
			my ( $vol, $dirs, $fname ) = File::Spec->splitpath( $sqlDataPath, true );
			my $target_file = File::Spec->catpath( $vol, $dirs, $database.( $row->{Type} eq 'D' ? '.mdf' : '.ldf' ));
			$move .= "MOVE '".$row->{'LogicalName'}."' TO '$target_file'";
		}
	}

	return $move;
}

# -------------------------------------------------------------------------------------------------
# restore the target database from the specified backup file
# in this first phase, set it first offline (if it exists)
# (I):
# - parms is a hash ref with keys:
#   > database: mandatory
# (O):
# - returns true|false

sub _restoreSetOffline {
	my ( $self, $parms ) = @_;

	my $database = $parms->{database};
	msgVerbose( __PACKAGE__."::_restoreSetOffline() database='$database'" );

	my $result = true;
	if( $self->databaseExists( $database )){
		my $res = $self->_sqlExec( "ALTER DATABASE $database SET OFFLINE WITH ROLLBACK IMMEDIATE;" );
		$result = $res->{ok};
	}

	return $result;
}

# -------------------------------------------------------------------------------------------------
# verify the restorability of the file
# (I):
# - parms is a hash ref with keys:
#   > database: mandatory
#   > file: mandatory
# (O):
# - returns true|false

sub _restoreVerify {
	my ( $self, $parms ) = @_;

	my $database = $parms->{database};
	my $fname = $parms->{file};
	msgVerbose( __PACKAGE__."::_restoreVerify() verifying $fname" );

	my $move = $self->_restoreMove( $parms );
	my $res = $self->_sqlExec( "RESTORE VERIFYONLY FROM DISK='$fname' WITH $move;" );
	msgLog( __PACKAGE__."::_restoreVerify() stdout='".TTP::chompDumper( $res->{stdout} )."'" );

	return $res->{ok};
}

# -------------------------------------------------------------------------------------------------
# execute a SQL request
# (I):
# - sql: the command
# - opts: an optional options hash with following keys:
#   > printStdout, defaulting to true
#   > resultStyle, defaulting to SINGLESET
#   > colinfoStyle, defaulting to COLINFO_NONE
# (O):
# returns hash with following keys:
# - ok: true|false
# - result: as an array ref
# - stdout: as an array ref
# - columns: as an array ref (if asked for)

sub _sqlExec {
	my ( $self, $sql, $opts ) = @_;
	$opts //= {};
	msgErr( __PACKAGE__."::_sqlExec() sql is mandatory, but is not specified" ) if !$sql;
	my $res = {
		ok => false,
		result => [],
		stdout => []
	};
	my $sqlsrv = undef;
	if( !TTP::errs()){
		$sqlsrv = $self->_connect();
	}
	if( !TTP::errs()){
		#msgVerbose( __PACKAGE__."::_sqlExec() executing '$sql'" );
		msgVerbose( __PACKAGE__."::_sqlExec() executing" );
		if( $self->ep()->runner()->dummy()){
			msgDummy( $sql );
			$res->{ok} = true;
		} else {
			my $printStdout = true;
			$printStdout = $opts->{printStdout} if defined $opts->{printStdout};
			my $colinfoStyle;
			if( $opts->{colinfoStyle} ){
				$colinfoStyle = $opts->{colinfoStyle};
				msgVerbose( "colinfoStyle=$opts->{colinfoStyle}" );
			} else {
				$colinfoStyle = Win32::SqlServer::COLINFO_NONE;
				msgVerbose( "colinfoStyle= Win32::SqlServer::COLINFO_NONE (default)" );
			}
			my $rowStyle;
			if( $opts->{rowStyle} ){
				$rowStyle = $opts->{rowStyle};
				msgVerbose( "rowStyle=$opts->{rowStyle}" );
			} else {
				$rowStyle = Win32::SqlServer::HASH;
				msgVerbose( "rowStyle= Win32::SqlServer::HASH (default)" );
			}
			my $resultStyle;
			if( $opts->{resultStyle} ){
				$resultStyle = $opts->{resultStyle};
				msgVerbose( "resultStyle=$opts->{resultStyle}" );
			} else {
				$resultStyle = Win32::SqlServer::SINGLESET;
				msgVerbose( "resultStyle=Win32::SqlServer::SINGLESET (default)" );
			}
			my $merged = capture_merged { $res->{result} = $sqlsrv->sql( $sql, $colinfoStyle, $rowStyle, $resultStyle )};
			my @merged = split( /[\r\n]/, $merged );
			foreach my $line ( @merged ){
				chomp( $line );
				$line =~ s/^\s*//;
				$line =~ s/\s*$//;
				if( length $line ){
					print " $line".EOL if $printStdout;
					push( @{$res->{stdout}}, $line );
				}
			}
			$res->{ok} = $sqlsrv->sql_has_errors() ? false : true;
			delete $sqlsrv->{ErrInfo}{Messages};
			# if we are ok, and the colinfo style has prepended a row, then remove from the result set
			# pwi 2024-12-23 happens that we are unable to get the prepended row with columns infos :(
			#if( $res->{ok} && $colinfoStyle != Win32::SqlServer::COLINFO_NONE ){
			#if( $res->{ok} ){
				#print Dumper( $result );
				#$res->{columns} = @{shift( @$result )};
				#my $row = shift( @$result );
				#if( $resultStyle == Win32::SqlServer::SINGLESET ){
				#} else {
				#}
			#}
		}
	}
	#print Dumper( $sql );
	#print Dumper( $opts );
	#print Dumper( $res );
	msgVerbose( __PACKAGE__."::_sqlExec() returns '".( $res->{ok} ? 'true':'false' )."'" );
	return $res;
}

### Public methods

# -------------------------------------------------------------------------------------------------
# Backup a database
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
	if( !TTP::errs()){
		msgVerbose( __PACKAGE__."::backupDatabase() entering with service='".$self->service()->name()."' database='$parms->{database}' mode='$parms->{mode}'..." );
		my $output = $parms->{output} || $self->computeDefaultBackupFilename( $parms );
		my $tstring = Time::Moment->now->strftime( '%Y-%m-%d %H:%M:%S.%6N %:z' );
		# if full
		my $options = "NOFORMAT, NOINIT, MEDIANAME='SQLServerBackups'";
		my $label = "Full";
		# if diff
		if( $parms->{mode} eq 'diff' ){
			$options .= ", DIFFERENTIAL";
			$label = "Differential";
		}
		$options .= ", COMPRESSION" if $parms->{compress};
		my $sql = "USE master; BACKUP DATABASE $parms->{database} TO DISK='$output' WITH $options, NAME='$parms->{database} $label Backup $tstring';";
		msgVerbose( __PACKAGE__."::backupDatabase() sql='$sql'" );
		$result = $self->_sqlExec( $sql );
		msgLog( __PACKAGE__."::backupDatabase() stdout='".TTP::chompDumper( $result->{stdout} )."'" );
		$result->{output} = $output;
	}
	msgVerbose( __PACKAGE__."::backupDatabase() returns '".( $result->{ok} ? 'true':'false' )."'" );
	return $result;
}

# -------------------------------------------------------------------------------------------------
# get and returns the list of databases in the server, minus the predefined system databases
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
		$databases = [];
		my $res = $self->_sqlExec( "select name from master.sys.databases order by name" );
		if( $res->{ok} ){
			foreach my $it ( @{$res->{result}} ){
				my $dbname = $it->{name};
				if( !$self->dbFilteredBySystem( $dbname, $Const->{systemDatabases} ) && !$self->dbFilteredbyLimit( $dbname )){
					push( @{$databases}, $dbname );
				}
			}
			msgVerbose( __PACKAGE__."::getDatabases() got databases [ ". join( ', ', @{$databases} )." ]" );
			$self->{_dbms}{databases} = $databases;
		}
	}

	return $databases;
}

# ------------------------------------------------------------------------------------------------
# returns the list of tables in the database
# (I):
# - the database to list the tables from
# (O):
# - the list of tables, which may be empty

sub getDatabaseTables {
	my ( $self, $database ) = @_;

	my $tables = [];
	my $res = $self->_sqlExec( "SELECT TABLE_SCHEMA,TABLE_NAME FROM $database.INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE' ORDER BY TABLE_SCHEMA,TABLE_NAME" );
	if( $res->{ok} ){
		foreach my $it ( @{$res->{result}} ){
			if( !grep( /^$it->{TABLE_NAME}$/, @{$Const->{systemTables}} )){
				push( @{$tables}, "$it->{TABLE_SCHEMA}.$it->{TABLE_NAME}" );
			}
		}
		msgVerbose( __PACKAGE__."::getDatabaseTables() got ".scalar @{$tables}." table(s)" );
	}

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

	# get SqlServer-specific properties
	my $res = $self->_sqlExec( "SELECT \@\@SERVICENAME as name" );
	if( $res->{ok} ){
		push( @{$props}, { name => 'serviceName', value => $res->{result}[0]{name} });
	}
	$res = $self->_sqlExec( "SELECT \@\@VERSION as version" );
	if( $res->{ok} ){
		# limit to the first line of the version
		my @lines = split( /[\r\n]/,  $res->{result}[0]{version} );
		push( @{$props}, { name => 'version', value => $lines[0] });
	}

	return $props;
}

# -------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - returns the instance name

sub instance {
	my ( $self ) = @_;

	my $instance = $self->{_dbms}{instance};

	return $instance;
}

# -------------------------------------------------------------------------------------------------
# Restore a file into a database
# (I):
# - parms is a hash ref with keys:
#   > database: mandatory
#   > full: mandatory, the full backup file
#   > diff: optional, the diff backup file
#   > verifyonly: whether we want only check the restorability of the provided file
# (O):
# - returns a hash with following keys:
#   > ok: true|false

sub restoreDatabase {
	my ( $self, $parms ) = @_;
	my $result = { ok => false };
	my $verifyonly = false;
	$verifyonly = $parms->{verifyonly} if defined $parms->{verifyonly};
	msgErr( __PACKAGE__."::restoreDatabase() database is mandatory, not specified" ) if !$parms->{database} && !$verifyonly;
	msgErr( __PACKAGE__."::restoreDatabase() full is mandatory, not specified" ) if !$parms->{full};
	if( !TTP::errs()){
		msgVerbose( __PACKAGE__."::restoreDatabase() entering with service='".$self->service()->name()."' database='$parms->{database}' verifyonly='$verifyonly'..." );
		my $diff = $parms->{diff} || '';
		if( $verifyonly || $self->_restoreSetOffline( $parms )){
			$parms->{'file'} = $parms->{full};
			$parms->{'last'} = length $diff == 0 ? true : false;
			if( $verifyonly ){
				$result->{ok} = $self->_restoreVerify( $parms );
			} else {
				$result->{ok} = $self->_restoreFile( $parms );
			}
			if( $result->{ok} && length $diff ){
				$parms->{'file'} = $diff;
				$parms->{'last'} = true;
				if( $verifyonly ){
					$result->{ok} &= $self->_restoreVerify( $parms );
				} else {
					$result->{ok} &= $self->_restoreFile( $parms );
				}
			}
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

# ------------------------------------------------------------------------------------------------
# execute a SQL command and returns its result
# (I):
# - the DBMS instance
# - an object with following keys:
#   > command: the sql command
#   > opts: an optional options hash which following keys:
#     - multiple: whether several result sets are expected, defaulting to false
#     - columns: the output filename for the columns array(s)
# (O):
# returns a hash with following keys:
# - ok: true|false
# - result: the result set as an array ref
# - stdout: a copy of lines outputed on stdout as an array ref

sub apiExecSqlCommand {
	my ( $me, $dbms, $parms ) = @_;
	my $result = { ok => false };
	msgErr( __PACKAGE__."::apiExecSqlCommand() command is mandatory, but not specified" ) if !$parms || !$parms->{command};
	if( !TTP::errs()){
		msgVerbose( __PACKAGE__."::apiExecSqlCommand() entering with instance='".$dbms->instance()."' sql='$parms->{command}'" );
		my $resultStyle = undef;
		my $colinfoStyle = undef;
		my $rowStyle = undef;
		if( $Config{osname} eq "MSWin32" ){
			$resultStyle = Win32::SqlServer::SINGLESET;
			$resultStyle = Win32::SqlServer::MULTISET if $parms->{opts} && $parms->{opts}{multiple};
			$colinfoStyle = Win32::SqlServer::COLINFO_NONE;
			$colinfoStyle = Win32::SqlServer::COLINFO_FULL if $parms->{opts} && $parms->{opts}{columns};
			$rowStyle = Win32::SqlServer::HASH;
		}
		my $opts = {
			resultStyle => $resultStyle,
			colinfoStyle => $colinfoStyle,
			rowStyle => $rowStyle
		};
		$result = _sqlExec( $dbms, $parms->{command}, $opts );
	}
	msgVerbose( __PACKAGE__."::apiExecSqlCommand() result='".( $result->{ok} ? 'true' : 'false' )."'" );
	return $result;
}

1;

__END__
