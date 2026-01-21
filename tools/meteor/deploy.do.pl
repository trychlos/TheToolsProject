# @(#) deploy an application from an environment to another
#
# @(-) --[no]help                  print this message, and exit [${help}]
# @(-) --[no]colored               color the output depending of the message level [${colored}]
# @(-) --[no]dummy                 dummy run [${dummy}]
# @(-) --[no]verbose               run verbosely [${verbose}]
# @(-) --application=<path>        application root path [${application}]
# @(-) --from=<from>               from this source environment [${from}]
# @(-) --to=<to>                   to this target environment [${to}]
# @(-) --[no]bundle                deploy the application bundle [${bundle}]
# @(-) --collection=<collection>   deploy the named collection, may be specified several times or as a comma-separated list [${collection}]
# @(-) --json=<json>               use this json deployment description [${json}]
# @(-) --[no]list-collections      list collections in the current environment [${list_collections}]
# @(-) --[no]list-environments     list defined target environments [${list_environments}]
# @(-) --[no]version               whether to update the version number in source tree [${version}]
#
# @(@) Note 1: Deploying from any environment 'A' to any environment 'B' always requires the availability of the json deployment description file,
# @(@)         which is not part of any bundle, so not deployed, and is expected to be only available in the development environment(s).
# @(@) Note 2: The JSON deployment file contains sensitive data. Remind that you MUST not publish it, and consider adding all your 'private/' subdirectories to your .gitignore.
# @(@) Note 3: If previous sentences are not clear enough, this verb is expected to be run against a local (development) environment.
#
#  Preparing the first deployement:
#   - on ZimbraAdmin:
#     > created a dedicated mail account
#           + record in Keepass
#   - on target host:
#     > have a dedicated filesystem
#       # lvcreate -n lvizmonitor /dev/vgdata -L 5G
#       # mkfs.xfs /dev/vgdata/lvizmonitor
#     > create an accout with ad-hoc uid, gid
#       # useradd -d /home/izmonitor -u 982 -g 982 -m izmonitor
#       # cp -rp /home/izmonitor /tmp
#       # rm -vf /home/izmonitor/{.b,.k,.v}*
#       # vi /etc/fstab
#       # systemctl daemon-reload
#       # mount /home/izmonitor
#       # chown izmonitor:izmonitor /home/izmonitor
#       # chmod 0700 /home/izmonitor
#       # mv -v /tmp/izmonitor/{.b,.k,.v}* /home/izmonitor/
#       # rmdir /tmp/izmonitor
#     > define the mongo database account
#       the Mongo user for the application must have been created before the first startup:
#       # mongosh --authenticationDatabase admin -u rootAdmin -p UftIqxBLvPCD
#         > use izmonitor
#         > db.createUser({ user: 'izmonitor', pwd: 'xxxxxx', roles: [{ role: 'dbOwner', db: 'izmonitor' }]})
#           + record in Keepass
#         > use admin
#         > db.system.users.find()
#       note 1: really 'use izmonitor' even if the database doesn't yet exists at that time
#       note 2: the izmonitor database will be actually created at first document insertion
#     > choose the NodeJS listening port:
#       # netstat -anp | grep 1024 is your friend
#       $ find .. -type f -name 'targets.json' -exec grep port {} \; -print
#
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

use strict;
use utf8;
use warnings;

use File::Spec;
use JSON;
use Path::Tiny;
use Time::Moment;
use URI::Encode qw( uri_encode uri_decode );

use TTP::Meteor;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	application => Path::Tiny->cwd,
	from => '',
	to => '',
	bundle => 'no',
	collection => 'ALL',
	json => './'.File::Spec->catfile( File::Spec->catdir( 'maintainer', 'private' ), 'deployments.json' ),
	list_collections => 'no',
	list_environments => 'no',
	version => 'yes'
};

my $opt_application = $defaults->{application};
my $opt_from = $defaults->{from};
my $opt_to = $defaults->{to};
my $opt_bundle = false;
my @opt_collections = ();
my $opt_json = $defaults->{json};
my $opt_list_collections = false;
my $opt_list_environments = false;
my $opt_version = true;

# whether we want list something
my $want_list = false;
# the application object as returned by TTP::Meteor::getApplication()
my $app;
# the full content of deployement.json
my $deployments;
# source and target data
my $from = undef;
my $to = undef;
# prev and next versions
my $versions = undef;

# -------------------------------------------------------------------------------------------------
# build web+mobile bundle
# Meteor build the bundle into the provided directory, naming it along the application directory last name
# (O):
# - the bundle full pathname, or undef

sub buildBundle {
	my $arch = "os.linux.x86_64";
	my $url = getRootURL( $to );
	if( $url ){
		my $dir = "/tmp";
		my $res = TTP::commandExec( "(cd $opt_application; meteor build $dir --server ${url} --architecture ${arch})" );
		#print STDERR "res ".Dumper( $res );
		if( $res->{success} ){
			my @dirs = File::Spec->splitdir( $opt_application );
			my $name = pop( @dirs );
			my $fname = File::Spec->catpath( "", $dir, "$name.tar.gz" );
			msgOut( "bundle '$fname' successfully built" );
			return $fname;
		} else {
			msgErr( $res->{stderrs}->[0] );
		}
	}
}

# -------------------------------------------------------------------------------------------------
# checking site host and path
# (O):
# - whether the provided definition is valid as a deployment environment

sub checkHostPath {
	my ( $h ) = @_;
	my $valid = false;
	if( isLocal( $h )){
		$valid = true;
	} else {
		my $host = $h->{host};
		my $path = $h->{path};
		if( $host && $path ){
			my $res = TTP::commandExec( "ssh $host \"[ -d $path ] && echo true\"" );
			if( $res->{success} ){
				if( $res->{stdouts}->[0] =~ m/true/ ){
					$valid = true;
					msgVerbose( "checkHostPath() host='$host' path=$path': ok" );
				} else {
					msgErr( "host='$host' path=$path': not found or not available" );
				}
			} else {
				msgErr( $res->{stderrs}->[0] );
			}
		}
	}
	return $valid;
}

# -------------------------------------------------------------------------------------------------
# check the space available on the target
# Our installation rules install each website on its own 5GB filesystem, and keep as many versions as
# possible until having filled this filesystem. Then we purge old versions to host new ones.

sub checkToSpace {
	if( isLocal( $to )){
		msgVerbose( "checkToSpace() deploying to a local target environment, space is not checked" );
	} else {
		my $host = $to->{host};
		my $path = $to->{path};
		if( $host && $path ){
			my $res = TTP::commandExec( "ssh $host \"du -sm ${path}/bundle/\"" );
			if( $res->{success} ){
				my @w = split( /\s/, $res->{stdouts}->[0] );
				my $size_mb = $w[0];
				my $wanted_mb = 2 * $size_mb;
				$res = TTP::commandExec( "ssh $host \"df -BM\"" );
				if( $res->{success} ){
					my @greped = scalar( @{$res->{stdouts}} ) ? grep( /$path/, @{$res->{stdouts}} ) : [];
					my @w = scalar( @greped ) ? split( /\s+/, $greped[0] ) : [];
					my $available_mb = scalar( @w ) ? $w[3] : "0M";
					$available_mb =~ s/.$//;
					if( $available_mb > $wanted_mb ){
						msgVerbose( "checkToSpace() available space=$available_mb MB, wanted=$wanted_mb MB: fine" );
					} else {
						msgVerbose( "checkToSpace() available space=$available_mb MB, wanted=$wanted_mb MB: have to free up some space" );
						$res = TTP::commandExec( "ssh $host ls -1dt ${path}/bundle-*" );
						if( $res->{success} ){
							my $count = scalar( @{$res->{stdouts}} );
							my @list = @{$res->{stdouts}};
							my $keep = 2;
							my $to_delete = $count - $keep;
							msgVerbose( "checkToSpace()  $count versions found, $to_delete to be removed" );
							for my $i ( 0 .. $count-1 ){
								if( $i < $keep ){
									msgVerbose( "checkToSpace()  keeping $list[$i]" );
								} else {
									msgVerbose( "checkToSpace()  removing $list[$i]" );
									$res = TTP::commandExec( "ssh $host \"rm -fr $list[$i]\"" );
									msgErr( $res->{stderrs}->[0] ) if !$res->{success};
								}
							}
						} else {
							msgErr( $res->{stderrs}->[0] );
						}
					}
				} else {
					msgErr( $res->{stderrs}->[0] );
				}
			} else {
				msgErr( $res->{stderrs}->[0] );
			}
		}
	}
}

# -------------------------------------------------------------------------------------------------
# Dump a collection into a .tgz file, and transfert it to the target host
# (I):
# - the collection name
# (O):
# - the path to the tgz file on the target host

sub collectionDumpSource {
	my ( $collection ) = @_;
	my $uri = mongoURI( $from );
	my $db = mongoDatabase( $from );
	if( TTP::errs()){
		msgVerbose( "an error happened when decoding 'from' Mongo URL" );
		return undef;
	}
	my $tgz = "/tmp/$collection.tgz";
	my $srctmpdir = "/tmp/$collection";
	# if source is local
	if( isLocal( $from )){
		msgVerbose( "collectionDumpSource() ...dumping to '$srctmpdir'" );
		my $res = TTP::commandExec( "mongodump --uri $uri --collection $collection --out $srctmpdir" );
		if( !$res->{success} ){
			msgErr( $res->{stderrs}->[0] );
			return undef;
		}
		msgVerbose( "collectionDumpSource() ...compressing to '$tgz'" );
		$res = TTP::commandExec( "(cd $srctmpdir/$db; tar -czf - ".uri_encode( $collection ).".* > $tgz)" );  # have a local /tmp.tgz
		if( !$res->{success} ){
			msgErr( $res->{stderrs}->[0] );
			return undef;
		}
		if( !isLocal( $to )){
			msgVerbose( "collectionDumpSource() ...transfering to '$to->{host}'" );
			$res = TTP::commandExec( "scp $tgz $to->{host}:/tmp/" );     # have a /tmp.tgz on the target
			if( !$res->{success} ){
				msgErr( $res->{stderrs}->[0] );
				return undef;
			}
		}
	} else {
		msgVerbose( "collectionDumpSource() ...dumping to '$from->{host}:$srctmpdir'" );
		my $res = TTP::commandExec( "ssh $from->{host} \"mongodump --uri $uri --collection $collection --out $srctmpdir\"" );
		if( !$res->{success} ){
			msgErr( $res->{stderrs}->[0] );
			return undef;
		}
		msgVerbose( "collectionDumpSource() ...compressing to '$from->{host}:$tgz'" );
		$res = TTP::commandExec( "ssh $from->{host} \"(cd $srctmpdir/$db; tar -czf - ".uri_encode( $collection ).".* > $tgz)\"" );
		if( !$res->{success} ){
			msgErr( $res->{stderrs}->[0] );
			return undef;
		}
		if( $from->{host} ne $to->{host} ){
			msgVerbose( "collectionDumpSource() ...get a local copy" );
			$res = TTP::commandExec( "scp $from->{host}:$tgz /tmp/" );
			if( !$res->{success} ){
				msgErr( $res->{stderrs}->[0] );
				return undef;
			}
			if( !isLocal( $to )){
				msgVerbose( "collectionDumpSource() ...transfering to '$to->{host}'" );
				$res = TTP::commandExec( "scp $tgz $to->{host}:/tmp/" );
				if( !$res->{success} ){
					msgErr( $res->{stderrs}->[0] );
					return undef;
				}
			}
		}
	}
	return $tgz;
}

# -------------------------------------------------------------------------------------------------
# Import a collection from a .tgz file
# (I):
# - the collection name
# - the pathname to the dump.tgz
# (O):
# - true|false

sub collectionImportTarget {
	my ( $collection, $tgz ) = @_;
	my $uri = mongoURI( $to );
	my $db = mongoDatabase( $to );
	if( TTP::errs()){
		msgVerbose( "an error happened when decoding 'to' Mongo URL" );
		return false;
	}
	if( isLocal( $to )){
		msgVerbose( "collectionImportTarget() ...uncompressing" );
		my $res = TTP::commandExec( "(cd /tmp; rm -fr $collection; mkdir $collection; cd $collection; tar -xzf $tgz)" );
		if( !$res->{success} ){
			msgErr( $res->{stderrs}->[0] );
			return false;
		}
		msgVerbose( "collectionImportTarget() ...restoring" );
		$res = TTP::commandExec( "mongorestore --uri $uri --nsInclude $db.$collection /tmp/$collection/".uri_encode( $collection ).".bson --drop" );
		if( !$res->{success} ){
			msgErr( $res->{stderrs}->[0] );
			return false;
		}
	} else {
		msgVerbose( "collectionImportTarget() ...uncompressing" );
		my $res = TTP::commandExec( "ssh $to->{host} \"(cd /tmp; rm -fr $collection; mkdir $collection; cd $collection; tar -xzf $tgz)\"" );
		if( !$res->{success} ){
			msgErr( $res->{stderrs}->[0] );
			return false;
		}
		msgVerbose( "collectionImportTarget() ...restoring" );
		$res = TTP::commandExec( "ssh $to->{host} \"mongorestore --uri $uri --nsInclude $db.$collection /tmp/$collection/".uri_encode( $collection ).".bson --drop\"" );
		if( !$res->{success} ){
			msgErr( $res->{stderrs}->[0] );
			return false;
		}
	}
	return true;
}

# -------------------------------------------------------------------------------------------------
# compute current and next versions
# version is the current date with a daily increment counter as 'yy.mm.dd.n'
# the sequence number start from 1, and increments the last deployed version at this same date.
# - if source is local, then next version is current date + sequence number
# - if source is remote, then we deploy the exact same version from the source, unless it already exists on the target
# (O):
# - an object with following keys:
#   > prev: the current version, can be undef the first time
#   > next: the next version
# or undef in case of an error

sub computeNextVersion {
	my $prev = getLastRemoteVersion( $to );	# may be undef
	my $next = undef;
	if( isLocal( $from )){
		my $today = Time::Moment->now->strftime( '%y.%m.%d' );
		my $sequence = 0;
		if( $prev ){
			my $prev_date = substr( $prev, 0, 8 );
			if( $prev_date eq $today ){
				$sequence = 0+substr( $prev, 9 );
			}
		}
		$sequence += 1;
		$next = "$today.$sequence";
	} else {
		my $last_from = getLastRemoteVersion( $from );
		if( $last_from ){
			if( $last_from eq $prev ){
				msgErr( "cowardly refuse to deploy from '$opt_from' v$last_from to '$opt_to' already existing v$prev" );
				return undef;
			}
			$next = $last_from;
		} else {
			msgErr( "unable to deply a non-existant version from '$opt_from'" );
			return undef;
		}
	}
	return {
		prev => $prev,
		next => $next
	};
}

# -------------------------------------------------------------------------------------------------
# deploy a bundle
# we have here:
# - from: the source environment properties, may be undef
# - to: the target environment properties

sub doDeployBundle {
	msgOut( "deploying an application bundle from '".( $opt_from || "local" )."' to '".( $opt_to || "local" )."'..." );
	# check source
	if( isLocal( $from )){
		gitCheckBranch();
	} else {
		checkHostPath( $from );
	}
	# check target
	# never ever deploy a bundle to a local (development) environment
	checkHostPath( $to ) if !TTP::errs();
	checkToSpace() if !TTP::errs();
	msgErr( "deploying a bundle to a local (development) environment is not possible" ) if isLocal( $to );
	# version computing - may trigger error
	$versions = computeNextVersion() if !TTP::errs();
	if( !TTP::errs()){
		msgOut( "deployed version will be $versions->{next}" );
		# build the source bundle
		# transfer it to the target host
		if( isLocal( $from )){
			updateVersions();
			$from->{bundle} = buildBundle();
		} else {
			$from->{bundle} = "/tmp/bundle.tgz";
			my $res = TTP::commandExec( "ssh $from->{host} \"(cd $from->{path}; tar -czf - bundle-$versions->{next} > $from->{bundle})\"" );
			if( $res->{success} ){
				$res = TTP::commandExec( "scp $from->{host}:$from->{bundle} /tmp/" );
				if( $res->{success} ){
					msgVerbose( "doDeployBundle() '$from->{bundle}' bundle successfully transferred from '$from->{host}'")
				} else {
					msgErr( $res->{stderrs}->[0] );
				}
			} else {
				msgErr( $res->{stderrs}->[0] );
			}
		}
	}
	# install on target environment
	if( !TTP::errs()){
		my $res = TTP::commandExec( "scp $from->{bundle} $to->{host}:/tmp" );
		if( $res->{success} ){
			msgVerbose( "doDeployBundle() '$from->{bundle}' bundle successfully transferred to '$to->{host}'")
		} else {
			msgErr( $res->{stderrs}->[0] );
		}
	}
	if( !TTP::errs() && !isLocal( $to )){
        installTarget() &&
        setupSystemdService() &&
        setupStartupScript() &&
        setupEnv() &&
        sysRestart();
		if( !TTP::errs()){
	        msgOut( "server deployed as v$versions->{next}" );
		}
	}
	# update our local development git repository
	if( !TTP::errs() && isLocal( $from )){
		gitUpdateOrRevert();
	}
=pod
		# mobile apk preparation
		if [ $_ret -eq 0 -a -r "${projectdir}/mobile-config.js" ]; then
			apk="/tmp/${app_name}-v${version}.apk" &&
			apk_release_path="/tmp/android/project/app/build/outputs/apk/release/app-release-unsigned.apk" &&
			execcmd "rm -f ${apk}" &&
			execcmd "jarsigner -storepass abcdef -keystore ${projectdir}/.keystore -verbose -sigalg SHA1withRSA -digestalg SHA1 ${apk_release_path} ${target_domain}" &&
			execcmd "${HOME}/data/Android/Sdk/build-tools/29.0.2/zipalign 4 /tmp/android/project/app/build/outputs/apk/release/app-release-unsigned.apk ${apk}" &&
			execcmd "rm -fr ${projectdir}/public/res/apk" &&
			execcmd "mkdir -p ${projectdir}/public/res/apk" &&
			execcmd "cp ${apk} ${projectdir}/public/res/apk/" &&
			echo "APK prepared as ${apk}"
			_ret=$?
		fi
=cut
	if( TTP::errs()){
		msgErr( TTP::errs()." errors detected", { incErr => false });
	} else {
		msgOut( "done" );
	}
}

# -------------------------------------------------------------------------------------------------
# deploy one or more collections

sub doDeployCollections {
	msgOut( "deploying [ '".join( '\', \'', @opt_collections )."' ] collections from '".( $opt_from || "local" )."' to '".( $opt_to || "local" )."'..." );
	foreach my $collection ( @opt_collections ){
		msgVerbose( "doDeployCollections() deploying '$collection' collection.." );
		my $tgz = collectionDumpSource( $collection );
		next if !$tgz;
		# if target is local
		collectionImportTarget( $collection, $tgz );
	}
	if( TTP::errs()){
		msgErr( TTP::errs()." errors detected", { incErr => false });
	} else {
		msgOut( "done" );
	}
}

# -------------------------------------------------------------------------------------------------
# list the known collections

sub doListCollections {
	msgOut( "listing known collections for '$app->{name}' application..." );
	my $count = 0;
	my $collections = getCollections();
	foreach my $it ( @{$collections} ){
		print " $it";
		print EOL;
		$count += 1;
	}
	msgOut( "found $count known collection(s)" );
}

# -------------------------------------------------------------------------------------------------
# list the defined target environments

sub doListEnvironments {
	msgOut( "listing defined target environments for '$app->{name}' application..." );
	my $count = 0;
	foreach my $it ( sort keys %{$deployments->{targets}} ){
		print " $it";
		print " ($deployments->{targets}{$it}{label_env})" if $deployments->{targets}{$it}{label_env};
		print EOL;
		$count += 1;
	}
	msgOut( "found $count defined target environment(s)" );
}

# -------------------------------------------------------------------------------------------------
# returns the list of known collections in the current environment
# Note that running 'meteor' as well as '~/.meteor/meteor' requires that we run from a Meteor project directory
# (I):
# - none
# (O):
# - the collections list

sub getCollections {
	my $res = [];
	my $cmdline = "mongosh \$((cd $opt_application; meteor mongo --url) | sed -r \'s/\\x1B\\[(([0-9]+)(;[0-9]+)*)?[m,K,H,f,J]//g\' | awk \'{ print \$NF }\') --quiet --eval \'db.getCollectionNames()\'";
	my $out = TTP::commandExec( $cmdline );
	#print STDERR "out ".Dumper( $out );
	if( @{$out->{stderrs}} ){
		msgErr( $out->{stderrs}->[0] );
	} else {
		# the output is a stringified list - has to eval it to an actual js list
		foreach my $it ( @{$out->{stdouts}} ){
			next if $it eq '[' or $it eq ']';
			$it =~ s/^\s*\'//;
			$it =~ s/\',?$//;
			push( @{$res}, $it );
		}
	}
    return $res;
}

# -------------------------------------------------------------------------------------------------
# returns the content of a json file
# (I):
# - none
# (O):
# - the read json or undef

sub getJSON {
	my ( $json_path ) = @_;
	my $res;
	if( -r $json_path ){
		$res = decode_json( path( $json_path )->slurp_utf8 );
	} else {
		msgErr( "$json_path: file not found or not readable" );
		return undef;
	}
    return $res;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - the 'from' or 'to' object
# (O):
# - the last version, or undef if doesn't exist yet

sub getLastRemoteVersion {
	my ( $h ) = @_;
	my $host = $h->{host};
	my $path = $h->{path};
	if( $host && $path ){
		my $res = TTP::commandExec( "ssh $host /bin/ls -1dt $path/bundle-* 2>/dev/null" );
		my $list = $res->{stdouts} || [];
		my $fname = scalar( @{$list} ) ? $list->[0] : '';
		my ( $volume, $directories, $version ) = File::Spec->splitpath( $fname );
		$version =~ s/^bundle-//;
		return $version || undef;
	}
	return undef;
}

# -------------------------------------------------------------------------------------------------
# compute the target root url
# this should be defined per deployment target, but may default to 'https://host'
# (I):
# - the 'from' or 'to' object
# (O):
# - the target url, always set

sub getRootURL {
	my ( $h ) = @_;
	my $url = $h->{root_url};
	if( $url ){
		msgVerbose( "getRootURL() got root url '$url'" );
	} else {
		my $host = $h->{host};
		$url = "https://$host";
		msgVerbose( "getRootURL() computed default root url '$url'" );
	}
	return $url;
}

# -------------------------------------------------------------------------------------------------
# the name of the scripts which runs the application
# can be overriden on a target-basis
# (I):
# - the 'from' or 'to' object
# (O):
# - the script name

sub getScriptName {
	my ( $h ) = @_;
	my $script = $h->{script_name} // $app->{name};
	return $script;
}

# -------------------------------------------------------------------------------------------------
# the name of the website service defaults to the name of the Meteor application
# can be overriden on a target-basis
# (I):
# - the 'from' or 'to' object
# (O):
# - the service name

sub getServiceName {
	my ( $h ) = @_;
	my $service = $h->{service_name} // $app->{name};
	return $service;
}

# -------------------------------------------------------------------------------------------------
# the name of the website account defaults to the name of the Meteor application
# can be overriden on a target-basis
# (I):
# - the 'from' or 'to' object
# (O):
# - the account name

sub GetUserAccount {
	my ( $h ) = @_;
	my $name = $h->{user_account} // $app->{name};
	return $name;
}

# -------------------------------------------------------------------------------------------------
# the group of the website account defaults to the name of the Meteor application
# can be overriden on a target-basis
# (I):
# - the 'from' or 'to' object
# (O):
# - the account group

sub getUserGroup {
	my ( $h ) = @_;
	my $name = $h->{user_group} // $app->{name};
	return $name;
}

# -------------------------------------------------------------------------------------------------
# check that we are deploying from the ad-hoc git branch
# check that there is no uncommitted change(s)
# this should be master, but can be overriden in deployments.json 'git_branches'
# Note: to be reviewed as the below code considers that we are deploying from the local env.
# (O):
# - whether the application directory is suitable for a deployment source

sub gitCheckBranch {
	my $valid = false;
	# are we in a git repository ?
	my $status = TTP::commandExec( "(cd $opt_application; git status)" );
	if( scalar( @{$status->{stderrs}} )){
		if( $status->{stderrs}->[0] =~ m/fatal: not a git repository/ ){
			msgVerbose( "gitCheckBranch() ".$status->{stderrs}->[0].": fine (from deployment point of view, at least)" );
			return true;
		}
		msgErr( $status->{stderrs}->[0] );
	# if yes, are there any uncommitted changes ?
	} elsif( grep( /^Changes/, @{$status->{stdouts}} )){
		msgErr( "found uncommitted changes: cowarding refusing to deploy" );
	# if not, are we on the right branch ?
	} else {
		my $allowed = $deployments->{targets}{$opt_from}{git_branches} // [ 'master' ];
		my $branch = TTP::commandExec( "(cd $opt_application; git branch) | grep -E '^\\*' | awk '{ print \$2 }'" );
		if( $branch->{success} ){
			if( scalar( @{$branch->{stdouts}} ) == 1 ){
				if( grep( /$branch->{stdouts}->[0]/, @{$allowed} )){
					msgVerbose( "gitCheckBranch() got current branch $branch->{stdouts}->[0]: fine" );
					return true;
				} else {
					msgErr( "got current branch $branch->{stdouts}->[0]: not in allowed branches [ '".join( '\', \'', @{$allowed} )."' ]" );
				}
			} else {
				msgErr( "unable to determine the current branch" );
			}
		} else {
			msgErr( $branch->{stderrs}->[0] );
		}
	}
	return $valid;
}

# -------------------------------------------------------------------------------------------------
# commit the updated files and set a tag
# (O):
# - true|false

sub gitUpdateOrRevert {
	if( scalar( @{$from->{updatedFiles}} )){
		if( $opt_version ){
			msgVerbose( "gitUpdateOrRevert() updating and tagging local git repository" );
			my $res = TTP::commandExec( "cd $opt_application && git add ".join( ' ', @{$from->{updatedFiles}} ));
			$res = TTP::commandExec( "cd $opt_application && git commit -m \"Deploy v$versions->{next} to \'$opt_to\' site\"" ) if $res->{success};
			$res = TTP::commandExec( "cd $opt_application && git tag -am \"Releasing v$versions->{next} to \'$opt_to\' site\" $versions->{next}" ) if $res->{success};
			$res = TTP::commandExec( "cd $opt_application && git remote" ) if $res->{success};
			if( $res->{success} && scalar( @{$res->{stdouts}} ) > 0 ){
				msgVerbose( "gitUpdateOrRevert() updating and tagging remote git repository" );
				$res = TTP::commandExec( "(cd $opt_application && git push && git push --tags)" );
			}
		} else {
			msgVerbose( "gitUpdateOrRevert() reverting updated versioned files" );
			my $res = TTP::commandExec( "cd $opt_application && git checkout ".join( ' ', @{$from->{updatedFiles}} ));
		}
	}
}

# -------------------------------------------------------------------------------------------------
# Test whether the environment is local
# (I):
# - the global 'from' or 'to' object
# (O):
# - whether the provided environment is local

sub isLocal {
	my ( $h ) = @_;
	my $local = $h->{local} // false;
	return $local;
}

# -------------------------------------------------------------------------------------------------
# Install the prepared 'from' bundle into the target environment
# (I):
# - none
# (O):
# - true|false

sub installTarget {
	msgVerbose( "installTarget() installing the provided '$from->{bundle}' bundle" );
	my $res = TTP::commandExec( "scp $from->{bundle} $to->{host}:/tmp" );
	if( !$res->{success} ){
		msgErr( $res->{stderrs}->[0] );
		return false;
	}
	msgVerbose( "installTarget()  ...removing current symlink" );
	$res = TTP::commandExec( "ssh $to->{host} \"cd $to->{path} && rm -f bundle\"" );
	if( !$res->{success} ){
		msgErr( $res->{stderrs}->[0] );
		return false;
	}
	msgVerbose( "installTarget()  ...extracting" );
	$res = TTP::commandExec( "ssh $to->{host} \"cd $to->{path} && tar -xzf $from->{bundle}\"" );
	if( !$res->{success} ){
		msgErr( $res->{stderrs}->[0] );
		return false;
	}
	msgVerbose( "installTarget()  ...changing ownership" );
	my $uid = GetUserAccount( $to );
	my $gid = getUserGroup( $to );
	if( isLocal( $from )){
		$res = TTP::commandExec( "ssh $to->{host} \"cd $to->{path} && chown -R $uid:$gid bundle\"" );
		if( !$res->{success} ){
			msgErr( $res->{stderrs}->[0] );
			return false;
		}
		msgVerbose( "installTarget()  ...renaming" );
		$res = TTP::commandExec( "ssh $to->{host} \"cd $to->{path} && mv bundle bundle-$versions->{next}\"" );
		if( !$res->{success} ){
			msgErr( $res->{stderrs}->[0] );
			return false;
		}
	} else {
		$res = TTP::commandExec( "ssh $to->{host} \"cd $to->{path} && chown -R $uid:$gid bundle-$versions->{next}\"" );
		if( !$res->{success} ){
			msgErr( $res->{stderrs}->[0] );
			return false;
		}
	}
	msgVerbose( "installTarget()  ...restablishing symlink" );
	$res = TTP::commandExec( "ssh $to->{host} \"cd $to->{path} && ln -s bundle-$versions->{next} bundle\"" );
	if( !$res->{success} ){
		msgErr( $res->{stderrs}->[0] );
		return false;
	}
	return true;
}

# -------------------------------------------------------------------------------------------------
# returns the Mongo database
# (I):
# - the 'from' or 'to' object
# (O):
# - the to-be-accessed MongoDB database, or undef

sub mongoDatabase {
	my ( $h ) = @_;
	my $db = undef;
	my $uri = mongoURI( $h );
	if( $uri ){
		my @w = split( /\//, $uri );
		$db = pop( @w );
	} else {
		msgErr( "cannot get MongoDB database URI from provided deployment properties" );
	}
	return $db || undef;
}

# -------------------------------------------------------------------------------------------------
# returns the MongoDB server URI
# (I):
# - the 'from' or 'to' object
# (O):
# - the MongoDB server URI, or undef

sub mongoURI {
	my ( $h ) = @_;
	$h->{additional_env} //= {};
	my $uri = $h->{additional_env}{MONGO_URL};
	$uri = "mongodb://127.0.0.1:3001/meteor" if !$uri && isLocal( $h );
	if( $uri ){
		msgVerbose( "mongoURI() uri='$uri'" );
	} else {
		msgErr( "cannot get MongoDB server URI from provided deployment properties" );
	}
	return $uri || undef;
}

# -------------------------------------------------------------------------------------------------
# normalize the application path and check for its existence
# (I):
# - the candidate path
# (O):
# - the normalized (absolute) path, or undef in case of an error

sub normalizeApplicationPath {
	my ( $path ) = @_;
	my $normalized = $path;
	if( substr( $path, 0, 1 ) ne "/" ){
		$normalized = path( $path )->realpath;
		msgVerbose( "normalizeApplicationPath() path='$path' normalized to '$normalized'" );
	}
	if( -d $normalized ){
		msgVerbose( "normalizeApplicationPath() path='$normalized' exists" );
	} else {
		msgErr( "--application='$opt_application': directory not found or not available" );
		$normalized = undef;
	}
	return $normalized;
}

# -------------------------------------------------------------------------------------------------
# A file path can be specified either as an absolute path or a one relative to the project directory
#  as in './dir/myfname.xx'.
# Note that we should avoid something like 'dir/fname.xxx' as File::Spec will silently eat the first dir level.
# Normalize that to an absolute path.
# (I):
# - the candidate path
# (O):
# - the normalized (absolute) path

sub normalizeFilePath {
	my ( $fname ) = @_;
	my $normalized = $fname;
	if( substr( $fname, 0, 1 ) ne "/" ){
		my ( $volume, $directories, $filename ) = File::Spec->splitpath( $fname );
		my @in_dirs = File::Spec->splitdir( $directories );
		shift( @in_dirs ) if !$in_dirs[0];
		my @app_dirs = File::Spec->splitdir( $opt_application );
		unshift( @in_dirs, @app_dirs );
		$normalized = File::Spec->catfile( File::Spec->catdir( @in_dirs ), $filename );
		msgVerbose( "normalizeFilePath() filename='$fname' normalized to '$normalized'" );
	}
	return $normalized;
}

# -------------------------------------------------------------------------------------------------
# Sanitize our global 'from' and 'to' hashes:
# - must have both host and path, or none of them
# - local is determined by the absence of host and path
# (I):
# - the global to sanitize

sub sanitize {
	my ( $h ) = @_;
	if( $h->{host} && $h->{path} ){
		delete $h->{local};
		msgVerbose( "sanitize() host='$h->{host}' path='$h->{path}': assuming remote environment" );
	} else {
		delete $h->{host};
		delete $h->{path};
		$h->{local} = true;
		msgVerbose( "sanitize() host and path are both undefined: assuming local environment" );
	}
}

# -------------------------------------------------------------------------------------------------
# initialize and sanitize the 'from' object

sub setFrom {
	$from = \%{ $deployments->{targets}{$opt_from} } if $opt_from;
	$from //= {};
	sanitize( $from );
}

# -------------------------------------------------------------------------------------------------
# initialize and sanitize the 'to' object

sub setTo {
	$to = \%{ $deployments->{targets}{$opt_to} };
	sanitize( $to );
}

# -------------------------------------------------------------------------------------------------
# create the sourced environment file
#	export MONGO_URL='mongodb://accord33:9f6udSQYXAnKRefVoY@localhost:27017/accord33'
#	export ROOT_URL='https://accord33.trychlos.org'
#	export PORT=10247
#	export MAIL_URL="smtps://accord33%40trychlos.org:UY-PHz.7DE+sKbo@mail.trychlos.org:465?tls.rejectUnauthorized=false"
#	export NODE_ENV="staging"
#	export APP_ENV="show.1"
# (O):
# - true|false

sub setupEnv {
    my $fname = "env.sh";
    msgVerbose( "setupEnv() installing '$fname' on '$to->{host}:$to->{path}'" );
	my $today = Time::Moment->now->strftime( '%Y-%m-%d %H:%M:%S' );
	my $account_name = GetUserAccount( $to );
	my $account_group = getUserGroup( $to );
    my $content = [];
	push( @{$content}, "# $to->{path}/$fname" );
	push( @{$content}, "# Automatically generated when deploying '$app->{name}' v$versions->{next} to '$opt_to' environment" );
	push( @{$content}, "# $today creation" );
	push( @{$content}, "" );
	# set root_utl
	push( @{$content}, "export ROOT_URL=\"$to->{root_url}\"" ) if $to->{root_url};
	# set additional environment variables
	foreach my $k ( sort keys %{$to->{additional_env}} ){
		push( @{$content}, "export $k=\"$to->{additional_env}{$k}\"" );
	}
	# set APP_ENV
	push( @{$content}, "export APP_ENV=\"$opt_to\"" );
	push( @{$content}, "" );
	my $tmpname = "/tmp/$fname";
	path( $tmpname )->spew_utf8( join( EOL, @{$content} ));
	my $res = TTP::commandExec( "scp $tmpname $to->{host}:$to->{path}/$fname" );
	if( !$res->{success} ){
		msgErr( $res->{stderrs}->[0] );
		return false;
	}
	$res = TTP::commandExec( "ssh $to->{host} \"chown $account_name:$account_group $to->{path}/$fname && chmod 0600 $to->{path}/$fname\"" );
	if( !$res->{success} ){
		msgErr( $res->{stderrs}->[0] );
		return false;
	}
	return true;
}

# -------------------------------------------------------------------------------------------------
# create the startup script
# (O):
# - true|false

sub setupStartupScript {
	my $script_name = getScriptName( $to );
    my $fname = "$script_name.sh";
    msgVerbose( "setupStartupScript() installing '$fname' on '$to->{host}:$to->{path}'" );
	my $today = Time::Moment->now->strftime( '%Y-%m-%d %H:%M:%S' );
	my $account_name = GetUserAccount( $to );
	my $account_group = getUserGroup( $to );
    my $content = [];
	push( @{$content}, "#!/bin/sh" );
	push( @{$content}, "#" );
	push( @{$content}, "# $to->{path}/$fname" );
	push( @{$content}, "# Automatically generated when deploying '$app->{name}' v$versions->{next} to '$opt_to' environment" );
	push( @{$content}, "# $today creation" );
	push( @{$content}, "" );
	push( @{$content}, "[ \"\$(whoami)\" == \"$account_name\" ] || { echo \"Must be executed as '$account_name'\" 1>&2; exit 1; }" );
	push( @{$content}, "" );
	push( @{$content}, "cd \${0%/*} &&" );
	push( @{$content}, "cwd=\"\$(pwd)\" &&" );
	push( @{$content}, "export PATH=\$HOME/node/bin:\$PATH &&" );
	push( @{$content}, "cd bundle &&" );
	push( @{$content}, "(cd programs/server && npm install) &&" );
	push( @{$content}, "source \"\${cwd}/env.sh\" &&" );
	push( @{$content}, "node main.js" );
	push( @{$content}, "" );
	my $tmpname = "/tmp/$fname";
	path( $tmpname )->spew_utf8( join( EOL, @{$content} ));
	my $res = TTP::commandExec( "scp $tmpname $to->{host}:$to->{path}/$fname" );
	if( !$res->{success} ){
		msgErr( $res->{stderrs}->[0] );
		return false;
	}
	$res = TTP::commandExec( "ssh $to->{host} \"chown $account_name:$account_group $to->{path}/$fname && chmod a+x $to->{path}/$fname\"" );
	if( !$res->{success} ){
		msgErr( $res->{stderrs}->[0] );
		return false;
	}
	return true;
}

# -------------------------------------------------------------------------------------------------
# create the systemctl service file and reload
# (O):
# - true|false

sub setupSystemdService {
	my $service_name = getServiceName( $to );
    my $fname = "$service_name.service";
    my $todir = "/etc/systemd/system/";
    msgVerbose( "setupSystemdService() installing '$fname' on '$to->{host}:$todir'" );
	my $today = Time::Moment->now->strftime( '%Y-%m-%d %H:%M:%S' );
    my $content = [];
	push( @{$content}, "# $todir/$fname" );
	push( @{$content}, "# Automatically generated when deploying '$app->{name}' v$versions->{next} to '$opt_to' environment" );
	push( @{$content}, "# $today creation" );
	push( @{$content}, "" );
	push( @{$content}, "[Unit]" );
	push( @{$content}, "Description=$app->{name} \@ $opt_to" );
	push( @{$content}, "After=local-fs.target network-online.target" );
	push( @{$content}, "Requires=local-fs.target network-online.target" );
	push( @{$content}, "" );
	push( @{$content}, "[Service]" );
	push( @{$content}, "User=".GetUserAccount( $to ));
	push( @{$content}, "Group=".getUserGroup( $to ));
	push( @{$content}, "Type=simple" );
	push( @{$content}, "ExecStart=$to->{path}/$service_name.sh" );
	push( @{$content}, "Restart=on-failure" );
	push( @{$content}, "StartLimitInterval=30s" );
	push( @{$content}, "StartLimitBurst=3" );
	push( @{$content}, "TimeoutSec=60" );
	push( @{$content}, "" );
	push( @{$content}, "[Install]" );
	push( @{$content}, "WantedBy=multi-user.target" );
	push( @{$content}, "" );
	my $tmpname = "/tmp/$fname";
	path( $tmpname )->spew_utf8( join( EOL, @{$content} ));
	my $res = TTP::commandExec( "scp $tmpname $to->{host}:$todir/$fname" );
	if( !$res->{success} ){
		msgErr( $res->{stderrs}->[0] );
		return false;
	}
	$res = TTP::commandExec( "ssh $to->{host} \"systemctl daemon-reload && systemctl enable $service_name\"" );
	if( !$res->{success} ){
		msgErr( $res->{stderrs}->[0] );
		return false;
	}
	return true;
}

# -------------------------------------------------------------------------------------------------
# restart the newly installed version
# (O):
# - true|false

sub sysRestart {
    my $service_name = getServiceName( $to );
    msgVerbose( "sysRestart() restarting the target '$service_name' service on '$to->{host}'" );
	my $res = TTP::commandExec( "ssh $to->{host} \"systemctl restart $service_name\"" );
	if( !$res->{success} ){
		msgErr( $res->{stderrs}->[0] );
		return false;
	}
	return true;
}

# -------------------------------------------------------------------------------------------------
# update the project version (if any)
# This version.json file is our own way to display the version in the web sites

sub updateVersions {
	my $versionings = $deployments->{versioning} // [];
	if( $versions && $versions->{next} && scalar( @{$versionings} )){
		msgVerbose( "updateVersions() versions: ".TTP::chompDumper( $versions ));
		$from->{updatedFiles} = [];
		foreach my $it ( @${versionings} ){
			if( $it->{filename} && $it->{pattern} && $it->{replacement} ){
				my $fname = normalizeFilePath( $it->{filename} );
				if( -r $fname ){
					my $pat = qr/$it->{pattern}/m;
					my $rep = $it->{replacement};
					#print STDERR "pat ".Dumper( $pat );
					#print STDERR "rep ".Dumper( $rep );
					my $content = path( $fname )->slurp_utf8();
					#print STDERR "before ".Dumper( $content );
					#msgVerbose( "matched" ) if $content =~ m/$pat/;
					my @captures = ( $content =~ $pat );
					#print STDERR "captures ".Dumper( @captures );
					$content =~ s/$pat/$rep/;
					for( reverse 0 .. $#captures ){ 
						my $n = $_ + 1;
						#  Many More Rules can go here, ie: \g matchers  and \{ } 
						$content =~ s/\$$n/${captures[$_]}/g ;
					}
					$content =~ s/<VERSION>/$versions->{next}/g;
					#print STDERR "after ".Dumper( $content );
					path( $fname )->spew_utf8( $content );
					push( @{$from->{updatedFiles}}, $fname );
				} else {
					msgVerbose( "updateVersions() $fname: not found or not readable, do not update version" );
				}
			} else {
				msgErr( "either 'filename' or 'pattern' or 'replacement' are missing keys" );
			}
		}
	} else {
		msgVerbose( "updateVersions() no version found or no versioning configured: nowhere or nothing to update" );
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"					=> sub { $ep->runner()->help( @_ ); },
	"colored!"				=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"				=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"				=> sub { $ep->runner()->verbose( @_ ); },
	"application=s"			=> \$opt_application,
	"from=s"				=> \$opt_from,
	"to=s"					=> \$opt_to,
	"bundle!"				=> \$opt_bundle,
	"collection=s"			=> \@opt_collections,
	"json=s"				=> \$opt_json,
	"list-collections!"		=> \$opt_list_collections,
	"list-environments!"	=> \$opt_list_environments,
	"version!"				=> \$opt_version )){

		msgOut( "try '".$ep->runner()->command()." ".$ep->runner()->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $ep->runner()->help()){
	$ep->runner()->displayHelp( $defaults );
	TTP::exit();
}

msgVerbose( "got colored='".( $ep->runner()->colored() ? 'true':'false' )."'" );
msgVerbose( "got dummy='".( $ep->runner()->dummy() ? 'true':'false' )."'" );
msgVerbose( "got verbose='".( $ep->runner()->verbose() ? 'true':'false' )."'" );
msgVerbose( "got application='$opt_application'" );
msgVerbose( "got from='$opt_from'" );
msgVerbose( "got to='$opt_to'" );
msgVerbose( "got bundle='".( $opt_bundle ? 'true':'false' )."'" );
@opt_collections= split( /,/, join( ',', @opt_collections ));
msgVerbose( "got collections=[".join( ',', @opt_collections )."]" );
msgVerbose( "got json='$opt_json'" );
msgVerbose( "got list-collections='".( $opt_list_collections ? 'true':'false' )."'" );
msgVerbose( "got list-environments='".( $opt_list_environments ? 'true':'false' )."'" );
msgVerbose( "got version='".( $opt_version ? 'true':'false' )."'" );

# check that the application path addresses a Meteor project
# get the deployment informations
$opt_application = normalizeApplicationPath( $opt_application );
if( $opt_application ){
	$app = TTP::Meteor::getApplication( $opt_application );
	if( $app ){
		$opt_json = normalizeFilePath( $opt_json );
		$deployments = getJSON( $opt_json );
		if( !$deployments->{targets} ){
			msgErr( "$opt_json deployement file lacks of a non-empty 'targets' value" );
		}
		#print STDERR "targets ".Dumper( $deployments );
	} else {
		msgErr( "--application='$opt_application' doesn't address a Meteor application" );
	}
}

# from, to, bundle, collection are deployment options, are ignored when just listing the environments
# when listing, we do not deploy
if( $opt_list_collections || $opt_list_environments ){
	msgWarn( "'--from' is a deploiement option, ignored when listing collections or environment" ) if $opt_from;
	msgWarn( "'--to' is a deploiement option, ignored when listing collections or environment" ) if $opt_to;
	msgWarn( "'--bundle' is a deploiement option, ignored when listing collections or environment" ) if $opt_bundle;
	msgWarn( "'--collection' is a deploiement option, ignored when listing collections or environment" ) if scalar @opt_collections;
	$want_list = true;
} else {
	# when deploying, --from defaults to the current local environment
	if( $opt_from ){
		if( $deployments->{targets}{$opt_from} ){
			msgVerbose( "'--from=$opt_from' is a known environment" );
			my $allowed = $deployments->{targets}{$opt_from}{isAllowedSource} // true;
			if( $allowed ){
				msgVerbose( "'--from=$opt_from' is allowed as a source environment" );
				if( $opt_to ){
					my $targets = $deployments->{targets}{$opt_from}{allowed_targets} // [];
					if( scalar( @{$targets} )){
						if( grep( /$opt_to/, @{$targets} )){
							msgVerbose( "'--from=$opt_from' accepts '$opt_to' target" );
						} else {
							msgErr( "'--from=$opt_from' doesn't accept '$opt_to' target among allowed [ '".join('\', \'', @{$targets} )."' ]" );
						}
					} else {
						msgVerbose( "'--from=$opt_from' accepts all targets" );
					}
					$targets = $deployments->{targets}{$opt_from}{forbidden_targets} // [];
					if( scalar( @{$targets} )){
						if( grep( /$opt_to/, @{$targets} )){
							msgErr( "'--from=$opt_from' forbids '$opt_to' target, forbidden being [ '".join('\', \'', @{$targets} )."' ]" );
						} else {
							msgVerbose( "'--from=$opt_from' doesn't forbid '$opt_to'" );
						}
					} else {
						msgVerbose( "'--from=$opt_from' doesn't forbid any target" );
					}
				}
			} else {
				msgErr( "'--from=$opt_from' is not allowed as a source environment" );
			}
		} else {
			msgErr( "'--from=$opt_from': unknown environment" );
		}
	} else {
		msgVerbose( "'--from' option is not specified, defaulting to addressed local environment in '$opt_application'" );
		if( 0 ){
			my $devs = [];
			foreach my $k ( sort keys %{$deployments} ){
				my $env = $deployments->{$k};
				my $node_env = $env->{node_env} // 'development';
				push( @{$devs}, $k ) if $node_env eq 'development';
			}
			my $count = scalar( @{$devs} );
			if( $count == 0 ){
				msgErr( "no development environment is found: unable to get a '--from' default source" );
			} elsif( $count == 1 ){
				$opt_from = $devs->[0];
				msgVerbose( "compute default source '$opt_from'" );
			} else {
				msgErr( "$count development environments have been found: unable to compute a '--from' default source" );
			}
		}
	}
	# --to is mandatory
	# and must be compatible with --from
	if( $opt_to ){
		if( $deployments->{targets}{$opt_to} ){
			msgVerbose( "'--to=$opt_to' is a known environment" );
			my $allowed = $deployments->{targets}{$opt_to}{isAllowedTarget} // true;
			if( $allowed ){
				msgVerbose( "'--to=$opt_to' is allowed as a target environment" );
				if( $opt_from ){
					my $sources = $deployments->{targets}{$opt_to}{allowed_sources} // [];
					if( scalar( @{$sources} )){
						if( grep( /$opt_from/, @{$sources} )){
							msgVerbose( "'--to=$opt_to' accepts '$opt_from' source" );
						} else {
							msgErr( "'--to=$opt_to' doesn't accept '$opt_from' source among allowed [ '".join('\', \'', @{$sources} )."' ]" );
						}
					} else {
						msgVerbose( "'--to=$opt_to' accepts all sources" );
					}
					$sources = $deployments->{targets}{$opt_to}{forbidden_sources} // [];
					if( scalar( @{$sources} )){
						if( grep( /$opt_from/, @{$sources} )){
							msgErr( "'--to=$opt_to' forbids '$opt_from' source, forbidden being [ '".join('\', \'', @{$sources} )."' ]" );
						} else {
							msgVerbose( "'--to=$opt_to' doesn't forbid '$opt_from'" );
						}
					} else {
						msgVerbose( "'--to=$opt_to' doesn't forbid any target" );
					}
				}
			} else {
				msgErr( "'--to=$opt_to' is not allowed as a target environment" );
			}
		} else {
			msgErr( "'--to=$opt_to': unknown environment" );
		}
	} else {
		msgErr( "'--to' option is mandatory when deploying" );
	}
	# from and to cannot be the same
	msgErr( "cowardly refuse to have same source and target environments" ) if $opt_from eq $opt_to;
	# must deploy at least a bundle or a collection
	msgWarn( "neither '--bundle' nor '--collection' options are specified, will not deploy anything" ) if !$opt_bundle && !scalar( @opt_collections );
}

if( !TTP::errs()){
	if( $want_list ){
		doListCollections() if $opt_list_collections;
		doListEnvironments() if $opt_list_environments;
	} else {
		setFrom();
		setTo();
		doDeployBundle() if $opt_bundle;
		doDeployCollections() if scalar( @opt_collections );
	}
}

TTP::exit();
