# @(#) compute and publish the size of a directory content
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --dirpath=s             the source path [${dirpath}]
# @(-) --dircmd=s              the command which will give the source path [${dircmd}]
# @(-) --[no]mqtt              publish the metrics to the (MQTT-based) messaging system [${mqtt}]
# @(-) --[no]http              publish the metrics to the (HTTP-based) Prometheus PushGateway system [${http}]
# @(-) --[no]text              publish the metrics to the (text-based) Prometheus TextFile Collector system [${text}]
# @(-) --prepend=<name=value>  label to be appended to the telemetry metrics, may be specified several times or as a comma-separated list [${prepend}]
# @(-) --append=<name=value>   label to be appended to the telemetry metrics, may be specified several times or as a comma-separated list [${append}]
#
# The Tools Project: a Tools System and Paradigm for IT Production
# Copyright (©) 1998-2023 Pierre Wieser (see AUTHORS)
# Copyright (©) 2023-2024 PWI Consulting
#
# The Tools Project is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version.
#
# The Tools Project is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with The Tools Project; see the file COPYING. If not,
# see <http://www.gnu.org/licenses/>.

use Data::Dumper;
use File::Path qw( remove_tree );
use File::Find;

use TTP::Constants qw( :all );
use TTP::Message qw( :all );
use TTP::Metric;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	dirpath => '',
	dircmd => '',
	mqtt => 'no',
	http => 'no',
	text => 'no',
	prepend => '',
	append => ''
};

my $opt_dirpath = $defaults->{dirpath};
my $opt_dircmd = $defaults->{dircmd};
my $opt_mqtt = false;
my $opt_http = false;
my $opt_text = false;
my @opt_prepends = ();
my @opt_appends = ();

# global variables here
my $dirCount = 0;
my $fileCount = 0;
my $totalSize = 0;

# -------------------------------------------------------------------------------------------------
# receive here all found files in the searched directories
# According to https://perldoc.perl.org/File::Find
#   $File::Find::dir is the current directory name,
#   $_ is the current filename within that directory
#   $File::Find::name is the complete pathname to the file.

sub compute {
	$dirCount += 1 if -d $File::Find::name;
	$fileCount += 1 if -f $File::Find::name;
	$totalSize += -s if -f $File::Find::name;
}

# -------------------------------------------------------------------------------------------------
# Compute the size of a directory content

sub doComputeSize {
	msgOut( "computing the '$opt_dirpath' content size" );
	find ( \&compute, $opt_dirpath );
	print " directories: $dirCount".EOL;
	print " files: $fileCount".EOL;
	print " size: $totalSize".EOL;
	my $code = 0;
	if( $opt_mqtt || $opt_http || $opt_text ){
		my $path = $opt_dirpath;
		$path =~ s/\//_/g;
		$path =~ s/\\/_/g;
		my @labels = ( @opt_prepends, "path=$path", @opt_appends );
		TTP::Metric->new( $ttp, {
			name => 'dirs_count',
			value => $dirCount,
			type => 'gauge',
			help => 'Directories count',
			labels => \@labels
		})->publish({
			mqtt => $opt_mqtt,
			mqttPrefix => 'sizedir/',
			http => $opt_http,
			httpPrefix => 'ttp_filesystem_sizedir_',
			text => $opt_text,
			textPrefix => 'ttp_filesystem_sizedir_'
		});
		TTP::Metric->new( $ttp, {
			name => 'files_count',
			value => $fileCount,
			type => 'gauge',
			help => 'Files count',
			labels => \@labels
		})->publish({
			mqtt => $opt_mqtt,
			mqttPrefix => 'sizedir/',
			http => $opt_http,
			httpPrefix => 'ttp_filesystem_sizedir_',
			text => $opt_text,
			textPrefix => 'ttp_filesystem_sizedir_'
		});
		TTP::Metric->new( $ttp, {
			name => 'content_size',
			value => $totalSize,
			type => 'gauge',
			help => 'Total size',
			labels => \@labels
		})->publish({
			mqtt => $opt_mqtt,
			mqttPrefix => 'sizedir/',
			http => $opt_http,
			httpPrefix => 'ttp_filesystem_sizedir_',
			text => $opt_text,
			textPrefix => 'ttp_filesystem_sizedir_'
		});
	}
	if( $code ){
		msgErr( "NOT OK" );
	} else {
		msgOut( "success" );
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$ttp->{run}{help},
	"colored!"			=> \$ttp->{run}{colored},
	"dummy!"			=> \$ttp->{run}{dummy},
	"verbose!"			=> \$ttp->{run}{verbose},
	"dirpath=s"			=> \$opt_dirpath,
	"dircmd=s"			=> \$opt_dircmd,
	"mqtt!"				=> \$opt_mqtt,
	"http!"				=> \$opt_http,
	"text!"				=> \$opt_text,
	"prepend=s@"		=> \@opt_prepends,
	"append=s@"			=> \@opt_appends )){

		msgOut( "try '".$running->command()." ".$running->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $running->help()){
	$running->verbHelp( $defaults );
	TTP::exit();
}

msgVerbose( "found colored='".( $running->colored() ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $running->dummy() ? 'true':'false' )."'" );
msgVerbose( "found verbose='".( $running->verbose() ? 'true':'false' )."'" );
msgVerbose( "found dirpath='$opt_dirpath'" );
msgVerbose( "found dircmd='$opt_dircmd'" );
msgVerbose( "found mqtt='".( $opt_mqtt ? 'true':'false' )."'" );
msgVerbose( "found http='".( $opt_http ? 'true':'false' )."'" );
msgVerbose( "found text='".( $opt_text ? 'true':'false' )."'" );
@opt_prepends = split( /,/, join( ',', @opt_prepends ));
msgVerbose( "found prepends='".join( ',', @opt_prepends )."'" );
@opt_appends = split( /,/, join( ',', @opt_appends ));
msgVerbose( "found appends='".join( ',', @opt_appends )."'" );

# dircmd and dirpath options are not compatible
my $count = 0;
$count += 1 if $opt_dirpath;
$count += 1 if $opt_dircmd;
msgErr( "one of '--dirpath' and '--dircmd' options must be specified" ) if $count != 1;

# if we have a source cmd, get the path and make it exist to be sure to have something to publish
$opt_dirpath = TTP::fromCommand( $opt_dircmd, { makeExist => true }) if $opt_dircmd;

if( !TTP::errs()){
	doComputeSize();
}

TTP::exit();
