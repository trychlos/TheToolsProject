# @(#) purge directories from a path
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --dirpath=s             the source path [${dirpath}]
# @(-) --dircmd=s              the command which will give the source path [${dircmd}]
# @(-) --keep=s                count of to-be-kept directories [${keep}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use File::Path qw( remove_tree );
use File::Spec;

use Mods::Constants qw( :all );
use Mods::Message;
use Mods::Path;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	dirpath => '',
	dircmd => '',
	keep => '0'
};

my $opt_dirpath = $defaults->{dirpath};
my $opt_dircmd = $defaults->{dircmd};
my $opt_keep = $defaults->{keep};

# -------------------------------------------------------------------------------------------------
# Purge directories from source, only keeping some in source
# - ignore dot files and dot dirs
# - ignore files, only considering dirs
sub doPurgeDirs {
	Mods::Message::msgOut( "purging from '$opt_dirpath', keeping '$opt_keep' item(s)" );
	my $count = 0;
	opendir( FD, "$opt_dirpath" ) || Mods::Message::msgErr( "unable to open directory $opt_dirpath: $!" );
	if( !Mods::Toops::errs()){
		my @list = ();
		while ( my $it = readdir( FD )){
			my $path = File::Spec->catdir( $opt_dirpath, $it );
			if( $it =~ /^\./ ){
				msgVerbose( "ignoring '$path'" );
				next;
			}
			if( -d "$path" ){
				push( @list, "$it" );
				next;
			}
			msgVerbose( "ignoring '$path'" );
		}
		closedir( FD );
		# sort in inverse order: most recent first
		@list = sort { $b cmp $a } @list;
		msgVerbose( "got ".scalar @list." item(s) in $opt_dirpath" );
		# build the lists to be kept and moved
		my @keep = ();
		if( $opt_keep >= scalar @list ){
			msgOut( "found ".scalar @list." item(s) in '$opt_dirpath' while wanting keep $opt_keep: nothing to do" );
		} else {
			for( my $i=0 ; $i<$opt_keep ; ++$i ){
				my $it = shift( @list );
				msgVerbose( "keeping "._sourcePath( $it ));
				push( @keep, $it );
			}
			# and remove the rest
			foreach my $it ( @list ){
				my $dir = File::Spec->catdir( $opt_dirpath, $it );
				Mods::Message::msgOut( " removing '$dir'" );
				remove_tree( $dir );
				$count += 1;
			}
		}
	}
	Mods::Message::msgOut( "$count purged directory(ies)" );
}

sub _sourcePath {
	my ( $it ) = @_;
	return File::Spec->catdir( $opt_dirpath, $it );
}

sub _targetPath {
	my ( $it ) = @_;
	return File::Spec->catdir( $opt_targetpath, $it );
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"colored!"			=> \$TTPVars->{run}{colored},
	"dummy!"			=> \$TTPVars->{run}{dummy},
	"dirpath=s"			=> \$opt_dirpath,
	"dircmd=s"			=> \$opt_dircmd,
	"keep=s"			=> \$opt_keep )){

		Mods::Message::msgOut( "try '$TTPVars->{run}{command}{basename} $TTPVars->{run}{verb}{name} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpVerb( $defaults );
	Mods::Toops::ttpExit();
}

Mods::Message::msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found colored='".( $TTPVars->{run}{colored} ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found dummy='".( $TTPVars->{run}{dummy} ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found dirpath='$opt_dirpath'" );
Mods::Message::msgVerbose( "found dircmd='$opt_dircmd'" );
Mods::Message::msgVerbose( "found keep='$opt_keep'" );

# dircmd and dirpath options are not compatible
my $count = 0;
$count += 1 if $opt_dirpath;
$count += 1 if $opt_dircmd;
msgErr( "one of '--dirpath' and '--dircmd' options must be specified" ) if $count != 1;

# if we have a source cmd, get the path and check it exists
$opt_dirpath = Mods::Path::fromCommand( $opt_dircmd, { mustExists => true }) if $opt_dircmd;

if( !Mods::Toops::errs()){
	doPurgeDirs();
}

Mods::Toops::ttpExit();
