# @(#) run a database backup
# Copyright (@) 2023-2024 PWI Consulting
#
# @(-) --[no]help              print this message, and exit [${opt_help_def}]
# @(-) --[no]dummy             dummy run [$opt_dummy_def]
# @(-) --[no]verbose           run verbosely [$opt_verbose_def]
# @(-) --instance=name         Sql Server instance name [${opt_instance_def}]
# @(-) --database=name         database name [${opt_db_def}]
# @(-) --[no]full              operate a full backup [${opt_full_def}]
# @(-) --[no]diff              operate a differential backup [${opt_diff_def}]
# @(-) --output=filename       target filename [${opt_fname_def}]

use Mods::Dbms;

my $TTPVars = Mods::Toops::TTPVars();

my $opt_help_def = 'no';
my $opt_verbose_def = 'no';
my $opt_dummy_def = 'no';
my $opt_dummy = false;
my $opt_instance_def = 'MSSQLSERVER';
my $opt_instance = $opt_instance_def;
my $opt_database_def = '';
my $opt_database = $opt_database_def;
my $opt_full_def = 'no';
my $opt_full = false;
my $opt_diff_def = 'no';
my $opt_diff = false;
my $opt_output_def = 'DEFAULT';
my $opt_output ='';

# -------------------------------------------------------------------------------------------------
# backup the source database to the target backup file
sub doBackup(){
	# do the backup
	my $res = Mods::Dbms::backupDatabase({
		instance => $opt_instance,
		database => $opt_database,
		output => $opt_output,
		mode => $opt_diff ? 'diff' : 'full',
		dummy => $opt_dummy
	});
	if( $res ){
		Mods::Toops::msgOut( "successfully done" );
	} else {
		Mods::Toops::msgErr( "erroneous!" );
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

=pod
Mods::Toops::getOptions([
	{
		key	 => 'instance',
		help => "address named instance",
		opt	 => '=s',
		var	 => \$opt_instance,
		def	 => $opt_instance_def
	},
	{
		key	 => 'database',
		help => "backup named database",
		opt	 => '=s',
		var	 => \$opt_database,
		def	 => $opt_database_def
	},
	{
		key	 => 'full',
		help => "whether to do a full backup",
		opt	 => '!',
		var	 => \$opt_full,
		def	 => $opt_full_def
	},
	{
		key	 => 'diff',
		help => "whether to do a differential backup",
		opt	 => '!',
		var	 => \$opt_diff,
		def	 => $opt_diff_def
	},
	{
		key	 => 'output',
		help => "output filename",
		opt	 => '=s',
		var	 => \$opt_output,
		def	 => $opt_output_def
	}
]);
=cut

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"dummy!"			=> \$opt_dummy,
	"instance=s"		=> \$opt_instance,
	"database=s"		=> \$opt_database,
	"full!"				=> \$opt_full,
	"diff!"				=> \$opt_diff,
	"output=s"			=> \$opt_output )){

		Mods::Toops::msgOut( "try '$TTPVars->{command_basename} $TTPVars->{verb} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::doHelpVerb();
	Mods::Toops::ttpExit();
}

Mods::Toops::msgVerbose( "found verbose='true'" );
Mods::Toops::msgVerbose( "found instance='$opt_instance'" );
Mods::Toops::msgVerbose( "found database='$opt_database'" );
Mods::Toops::msgVerbose( "found full='".( $opt_full ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found diff='".( $opt_diff ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found output='$opt_output'" );

my $instance = Mods::Dbms::checkInstanceOpt( $opt_instance );

if( $opt_database ){
	my $exists = Mods::Dbms::checkDatabaseExists( $opt_instance, $opt_database );
	if( !$exists ){
		Mods::Toops::msgErr( "database '$opt_database' doesn't exist" );
	}
} else {
	Mods::Toops::msgErr( "'--database' option is required, but is not specified" );
}

my $count = 0;
$count += 1 if $opt_full;
$count += 1 if $opt_diff;
if( $count != 1 ){
	Mods::Toops::msgErr( "one of '--full' or '--diff' options must be specified" );
}

if( !$opt_output ){
	msgVerbose( "'--output' option not specified, will use the computed default" );
}

if( !Mods::Toops::errs()){
	doBackup();
}

Mods::Toops::ttpExit();
