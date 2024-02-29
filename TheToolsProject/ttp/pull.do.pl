# @(#) pull code and configurations from a reference machine
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --fromhost=<name>       pull from this host [${fromhost}]
#
# @(@) When pulling from the default host, you should take care of specifying at least one of '--nohelp' or '--noverbose' (or '--verbose').
# @(@) Also be warned that this script deletes the destination before installing the refreshed version, and will not be able of that if
# @(@) a user is inside of the tree (either through a file explorer or a command prompt).
#
# Copyright (@) 2023-2024 PWI Consulting

use Config;
use Data::Dumper;
use File::Copy::Recursive qw( dircopy );
use File::Spec;

use Mods::Constants qw( :all );
use Mods::Message;
use Mods::Path;
use Mods::Toops;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	fromhost => ''
};
$defaults->{fromhost} = $TTPVars->{config}{toops}{deployments}{pullReference} if exists $TTPVars->{config}{toops}{deployments}{pullReference};

my $opt_fromhost = $defaults->{fromhost};

# -------------------------------------------------------------------------------------------------
# pull the reference tree from the specified machine
sub doPull {
	my ( $pullConfig ) = @_;
	my $result = false;
	Mods::Message::msgOut( "pulling from '$opt_fromhost'..." );
	my $asked = 0;
	my $done = 0;
	# have pull share
	my $pullShare = undef;
	$pullShare = $pullConfig->{remoteShare} if exists $pullConfig->{remoteShare};
	if( $pullShare ){
		my ( $pull_vol, $pull_dirs, $pull_file ) = File::Spec->splitpath( $pullShare );
		# if a byOS command is specified, then use it
		my $command = $TTPVars->{config}{toops}{deployments}{byOS}{$Config{osname}}{command};
		Mods::Message::msgVerbose( "found command='$command'" );
		# may have several source dirs: iterate on each
		foreach my $pullDir ( @{$TTPVars->{config}{toops}{deployments}{sourceDirs}} ){
			Mods::Message::msgVerbose( "pulling '$pullDir'" );
			my ( $dir_vol, $dir_dirs, $dir_file ) = File::Spec->splitpath( $pullDir );
			my $srcPath = File::Spec->catpath( $pull_vol, $dir_dirs, $dir_file );
			if( $command ){
				$asked += 1;
				Mods::Message::msgVerbose( "source='$srcPath' target='$pullDir'" );
				my $cmdres = Mods::Toops::commandByOs({
					command => $command,
					macros => {
						SOURCE => $srcPath,
						TARGET => $pullDir
					}
				});
				$done += 1 if $cmdres->{result};
			} else {
				opendir( FD, "$srcPath" ) or Mods::Message::msgErr( "unable to open directory $srcPath: $!" );
				if( !Mods::Toops::errs()){
					$result = true;
					while( my $it = readdir( FD )){
						next if $it eq "." or $it eq "..";
						next if grep( /$it/i, @{$TTPVars->{config}{toops}{deployments}{excludes}} );
						$asked += 1;
						my $pull_path = File::Spec->catdir( $srcPath, $it );
						my $dst_path = File::Spec->catdir( $pullDir, $it );
						Mods::Message::msgOut( "  resetting from '$pull_path' into '$dst_path'" );
						Mods::Message::msgDummy( "Mods::Toops::removeTree( $dst_path )" );
						if( !Mods::Toops::wantsDummy()){
							$result = Mods::Toops::removeTree( $dst_path );
						}
						if( $result ){
							Mods::Message::msgDummy( "dircopy( $pull_path, $dst_path )" );
							if( !Mods::Toops::wantsDummy()){
								$result = dircopy( $pull_path, $dst_path );
								Mods::Message::msgVerbose( "dircopy() result=$result" );
							}
						}
						if( $result ){
							$done += 1;
						} else {
							Mods::Message::msgWarn( "error when copying from '$pull_path' to '$dst_path'" );
						}
					}
					closedir( FD );
				}
			}
		}
	} else {
		Mods::Message::msgErr( "remoteShare is not specified in '$opt_fromhost' host configuration" );
	}
	my $str = "$done/$asked subdirs copied";
	if( $done == $asked && !Mods::Toops::errs()){
		Mods::Message::msgOut( "success ($str)" );
	} else {
		Mods::Message::msgErr( "NOT OK ($str)" );
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"colored!"			=> \$TTPVars->{run}{colored},
	"dummy!"			=> \$TTPVars->{run}{dummy},
	"fromhost=s"		=> \$opt_fromhost )){

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
Mods::Message::msgVerbose( "found fromhost='$opt_fromhost'" );

# a pull host must be defined in command-line and have a json configuration file
Mods::Message::msgErr( "'--fromhost' value is required, but not specified" ) if !$opt_fromhost;
my $config = Mods::Toops::getHostConfig( $opt_fromhost );

if( !Mods::Toops::errs()){
	doPull( $config );
}

Mods::Toops::ttpExit();
