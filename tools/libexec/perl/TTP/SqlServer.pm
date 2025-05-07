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

# -------------------------------------------------------------------------------------------------
# Backup a database
# (I):
# - the DBMS instance
# - parms is a hash ref with following keys:
#   > database: mandatory
#   > output: optional
#   > mode: full-diff, defaulting to 'full'
#   > compress: true|false
# (O):
# - returns a hash with following keys:
#   > ok: true|false
#   > stdout: a copy of lines outputed on stdout as an array ref

sub apiBackupDatabase {
	my ( $me, $dbms, $parms ) = @_;
	my $result = { ok => false };
	msgErr( __PACKAGE__."::apiBackupDatabase() database is mandatory, but is not specified" ) if !$parms->{database};
	msgErr( __PACKAGE__."::apiBackupDatabase() mode must be 'full' or 'diff', found '$parms->{mode}'" ) if $parms->{mode} ne 'full' && $parms->{mode} ne 'diff';
	msgErr( __PACKAGE__."::apiBackupDatabase() output is mandatory, but is not specified" ) if !$parms->{output};
	if( !TTP::errs()){
		msgVerbose( __PACKAGE__."::apiBackupDatabase() entering with instance='".$dbms->instance()."' database='$parms->{database}' mode='$parms->{mode}'..." );
		my $tstring = Time::Moment->now->strftime( '%Y-%m-%d %H:%M:%S.%6N %:z' );
		# if full
		my $options = "NOFORMAT, NOINIT, MEDIANAME='SQLServerBackups'";
		my $label = "Full";
		# if diff
		if( $parms->{mode} eq 'diff' ){
			$options .= ", DIFFERENTIAL";
			$label = "Differential";
		}
		$options .= ", COMPRESSION" if defined $parms->{compress} && $parms->{compress};
		$parms->{sql} = "USE master; BACKUP DATABASE $parms->{database} TO DISK='$parms->{output}' WITH $options, NAME='$parms->{database} $label Backup $tstring';";
		msgVerbose( __PACKAGE__."::apiBackupDatabase() sql='$parms->{sql}'" );
		$result = _sqlExec( $dbms, $parms->{sql} );
	}
	msgVerbose( __PACKAGE__."::apiBackupDatabase() returns '".( $result->{ok} ? 'true':'false' )."'" );
	return $result;
}

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

# -------------------------------------------------------------------------------------------------
# get and returns the list of databases in the instance
# (I):
# - the DBMS instance
# (O):
# returns a hash with following keys:
# - ok: true|false
# - output: a ref to an array of output lines

sub apiGetInstanceDatabases {
	my ( $me, $dbms ) = @_;
	my $result = { ok => false, output => [] };
	msgVerbose( __PACKAGE__."::apiGetInstanceDatabases() entering with instance='".$dbms->instance()."'" );
	my $sqlres = _sqlExec( $dbms, "select name from master.sys.databases order by name" );
	if( $sqlres->{ok} ){
		foreach( @{$sqlres->{result}} ){
			my $dbname = $_->{'name'};
			if( !grep( /^$dbname$/, @{$Const->{systemDatabases}} )){
				push( @{$result->{output}}, $dbname );
			}
		}
		msgVerbose( __PACKAGE__."::apiGetInstanceDatabases() found ".scalar @{$result->{output}}." databases" );
	}
	msgVerbose( __PACKAGE__."::apiGetInstanceDatabases() result='".( $result->{ok} ? 'true' : 'false' )."'" );
	return $result;
}

# ------------------------------------------------------------------------------------------------
# returns the list of tables in the database
# (I):
# - the DBMS instance
# - a parms hash with following keys:
#   > database: the database name
# (O):
# returns a hash with following keys:
# - ok: true|false
# - output: a ref to an array of output lines

sub apiGetDatabaseTables {
	my ( $me, $dbms, $parms ) = @_;
	my $result = { ok => false, output => [] };
	if( $parms->{database} ){
		msgVerbose( __PACKAGE__."::apiGetDatabaseTables() entering with instance='".$dbms->instance()."', database='$parms->{database}'" );
		my $sqlres = _sqlExec( $dbms,  "SELECT TABLE_SCHEMA,TABLE_NAME FROM $parms->{database}.INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE' ORDER BY TABLE_SCHEMA,TABLE_NAME" );
		if( $sqlres->{ok} ){
			foreach my $it ( @{$sqlres->{result}} ){
				if( !grep( /^$it->{TABLE_NAME}$/, @{$Const->{systemTables}} )){
					push( @{$result->{output}}, "$it->{TABLE_SCHEMA}.$it->{TABLE_NAME}" );
				}
			}
			msgVerbose( __PACKAGE__."::apiGetDatabaseTables() found ".scalar @{$result->{output}}." tables" );
		}
	} else {
		msgErr( __PACKAGE__."::apiGetDatabaseTables() database is mandatory, but not specified" );
	}
	msgVerbose( __PACKAGE__."::apiGetDatabaseTables() result='".( $result->{ok} ? 'true' : 'false' )."'" );
	return $result;
}

# -------------------------------------------------------------------------------------------------
# Restore a file into a database
# (I):
# - the DBMS instance
# - parms is a hash ref with keys:
#   > database: mandatory
#   > full: mandatory, the full backup file
#   > diff: optional, the diff backup file
#   > verifyonly: whether we want only check the restorability of the provided file
# (O):
# - returns a hash with following keys:
#   > ok: true|false

sub apiRestoreDatabase {
	my ( $me, $dbms, $parms ) = @_;
	my $result = { ok => false };
	my $verifyonly = false;
	$verifyonly = $parms->{verifyonly} if defined $parms->{verifyonly};
	msgErr( __PACKAGE__."::apiRestoreDatabase() database is mandatory, not specified" ) if !$parms->{database} && !$verifyonly;
	msgErr( __PACKAGE__."::apiRestoreDatabase() full is mandatory, not specified" ) if !$parms->{full};
	if( !TTP::errs()){
		msgVerbose( __PACKAGE__."::apiRestoreDatabase() entering with instance='".$dbms->instance()."' database='$parms->{database}' verifyonly='$verifyonly'..." );
		my $diff = $parms->{diff} || '';
		if( $verifyonly || _restoreDatabaseSetOffline( $dbms, $parms )){
			$parms->{'file'} = $parms->{full};
			$parms->{'last'} = length $diff == 0 ? true : false;
			if( $verifyonly ){
				$result->{ok} = _restoreDatabaseVerify( $dbms, $parms );
			} else {
				$result->{ok} = _restoreDatabaseFile( $dbms, $parms );
			}
			if( $result->{ok} && length $diff ){
				$parms->{'file'} = $diff;
				$parms->{'last'} = true;
				if( $verifyonly ){
					$result->{ok} &= _restoreDatabaseVerify( $dbms, $parms );
				} else {
					$result->{ok} &= _restoreDatabaseFile( $dbms, $parms );
				}
			}
		}
	}
	msgVerbose( __PACKAGE__."::apiRestoreDatabase() result='".( $result->{ok} ? 'true' : 'false' )."'" );
	return $result;
}

# ------------------------------------------------------------------------------------------------
# get a connection to a local SqlServer instance
# (I):
# - the DBMS instance
# (O):
# - an opaque handle on the connection, or undef

sub _connect {
	my ( $dbms ) = @_;
	$dbms->{_sqlserver} //= {};
	my $sqlsrv = $dbms->{_sqlserver}{sqlsrv};
	if( $sqlsrv ){
		msgVerbose( __PACKAGE__."::_connect() instance already connected" );
	} else {
		my $instance = $dbms->instance();
		Win32::SqlServer::SetDefaultForEncryption( 'Optional', true );
		my( $account, $passwd ) = _getCredentials( $dbms );
		if( length $account && length $passwd ){
			my $server = $dbms->ep()->node()->name()."\\".$instance;
			# SQLServer 2008R2 doesn't like have a server connection string with MSSQLSERVER default instance
			$server = undef if $instance eq "MSSQLSERVER";
			msgVerbose( __PACKAGE__."::_connect() calling sql_init with server='".( $server || '(undef)' )."', account='$account'..." );
			$sqlsrv = Win32::SqlServer::sql_init( $server, $account, $passwd );
			msgVerbose( __PACKAGE__."::_connect() sqlsrv->isconnected()=".$sqlsrv->isconnected());
			#print Dumper( $sqlsrv );
			if( $sqlsrv && $sqlsrv->isconnected()){
				$sqlsrv->{ErrInfo}{MaxSeverity} = 17;
				$sqlsrv->{ErrInfo}{SaveMessages} = 1;
				msgVerbose( __PACKAGE__."::_connect() successfully connected" );
				$dbms->{_sqlserver}{sqlsrv} = $sqlsrv;
			} else {
				msgErr( __PACKAGE__."::_connect() unable to connect to '$instance' instance" );
				$sqlsrv = undef;
			}
		} else {
			msgErr( __PACKAGE__."::_connect() unable to get account/password couple" );
		}
	}
	return $sqlsrv;
}

# ------------------------------------------------------------------------------------------------
# returns the first account defined for the named instance
# (I):
# - the DBMS instance
# (O):
# - an array ( username, password )

sub _getCredentials {
	my ( $dbms ) = @_;
	my $credentials = TTP::Credentials::get([ 'DBMS', $dbms->instance(), ]);
	my $account = undef;
	my $passwd = undef;
	if( $credentials ){
		$account = ( keys %{$credentials} )[0];
		$passwd = $credentials->{$account};
		msgVerbose( __PACKAGE__."::_getCredentials() got account='".( $account || '(undef)' )."'" );
	} else {
		msgErr( __PACKAGE__."::_getCredentials() unable to get credentials with provided arguments" );
	}
	return ( $account, $passwd );
}

# -------------------------------------------------------------------------------------------------
# restore the target database from the specified backup file
# (I):
# - the DBMS instance
# - parms is a hash ref with keys:
#   > database: mandatory
#   > file: mandatory
#   > last: mandatory
# (O):
# - returns the needed 'MOVE' sentence

sub _restoreDatabaseFile {
	my ( $dbms, $parms ) = @_;
	my $instance = $dbms->instance();
	my $database = $parms->{database};
	my $fname = $parms->{file};
	my $last = $parms->{last};
	#
	msgVerbose(  __PACKAGE__."::_restoreDatabaseFile() restoring $fname" );
	my $recovery = 'NORECOVERY';
	if( $last ){
		$recovery = 'RECOVERY';
	}
	my $move = _restoreDatabaseMove( $dbms, $parms );
	my $result = true;
	if( $move ){
		my $res = _sqlExec( $dbms, "RESTORE DATABASE $database FROM DISK='$fname' WITH $recovery, $move;" );
		$result = $res->{ok};
	}
	return $result;
}

# -------------------------------------------------------------------------------------------------
# returns the move option in case of the datapath is different from the source or when the target
# database has changed
# (I):
# - the DBMS instance
# - parms is a hash ref with keys:
#   > database: mandatory
#   > file: mandatory
# (O):
# - returns the needed 'MOVE' sentence

sub _restoreDatabaseMove {
	my ( $dbms, $parms ) = @_;
	my $instance = $dbms->instance();
	my $database = $parms->{database};
	my $fname = $parms->{file};
	msgVerbose( __PACKAGE__."::_restoreDatabaseMove() database='$database'" );
	my $result = _sqlExec( $dbms, "RESTORE FILELISTONLY FROM DISK='$fname'" );
	my $move = undef;
	if( $dbms->ep()->runner()->dummy()){
		msgDummy( "considering nomove" );
	} elsif( !scalar @{$result->{result}} ){
		msgErr( __PACKAGE__."::_restoreDatabaseMove() unable to get the files list of the backup set" );
	} else {
		my $sqlDataPath = $dbms->ep()->node()->var([ 'DBMS', 'byInstance', $instance, 'dataPath' ]);
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
# - the DBMS instance
# - parms is a hash ref with keys:
#   > database: mandatory
# (O):
# - returns true|false

sub _restoreDatabaseSetOffline {
	my ( $dbms, $parms ) = @_;
	my $database = $parms->{database};
	msgVerbose( __PACKAGE__."::_restoreDatabaseSetOffline() database='$database'" );
	my $result = true;
	if( $dbms->databaseExists( $database )){
		my $res = _sqlExec( $dbms, "ALTER DATABASE $database SET OFFLINE WITH ROLLBACK IMMEDIATE;" );
		$result = $res->{ok};
	}
	return $result;
}

# -------------------------------------------------------------------------------------------------
# verify the restorability of the file
# (I):
# - the DBMS instance
# - parms is a hash ref with keys:
#   > database: mandatory
#   > file: mandatory
# (O):
# - returns true|false

sub _restoreDatabaseVerify {
	my ( $dbms, $parms ) = @_;
	my $instance = $dbms->instance();
	my $database = $parms->{database};
	my $fname = $parms->{file};
	msgVerbose( __PACKAGE__."::_restoreDatabaseVerify() verifying $fname" );
	my $move = _restoreDatabaseMove( $dbms, $parms );
	my $res = _sqlExec( $dbms, "RESTORE VERIFYONLY FROM DISK='$fname' WITH $move;" );
	return $res->{ok};
}

# -------------------------------------------------------------------------------------------------
# execute a SQL request
# (I):
# - dbms: the connection object as provided by Dbms.pm
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
	my ( $dbms, $sql, $opts ) = @_;
	$opts //= {};
	msgErr( __PACKAGE__."::_sqlExec() sql is mandatory, but is not specified" ) if !$sql;
	my $res = {
		ok => false,
		result => [],
		stdout => []
	};
	my $sqlsrv = undef;
	if( !TTP::errs()){
		$sqlsrv = _connect( $dbms );
	}
	if( !TTP::errs()){
		#msgVerbose( __PACKAGE__."::_sqlExec() executing '$sql'" );
		msgVerbose( __PACKAGE__."::_sqlExec() executing" );
		if( $dbms->ep()->runner()->dummy()){
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

1;

__END__
