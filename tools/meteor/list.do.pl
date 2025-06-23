# @(#) list objects
#
# @(-) --[no]help                  print this message, and exit [${help}]
# @(-) --[no]colored               color the output depending of the message level [${colored}]
# @(-) --[no]dummy                 dummy run [${dummy}]
# @(-) --[no]verbose               run verbosely [${verbose}]
# @(-) --root=<path>               root tree path [${root}]
# @(-) --[no]applications          apply to applications [${applications}]
# @(-) --[no]packages              apply to packages [${packages}]
# @(-) --bypath=<regex>            identify packages by their pathname [${bypath}]
# @(-) --[no]tree                  display packages as a tree [${tree}]
# @(-) --[no]callers               display packages callers [${callers}]
# @(-) --[no]publish-infos         also display packages publication informations [${publishInfos}]
# @(-) --[no]only-publishables     only display packages which have something to publish [${onlyPublishables}]
#
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

use strict;
use utf8;
use warnings;

use File::Spec;
use Path::Tiny;

use TTP::Meteor;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	root => Path::Tiny->cwd,
	applications => 'no',
	packages => 'no',
	bypath => '',
	tree => 'no',
	callers => 'no',
	publishInfos => 'no',
	onlyPublishables => 'no'
};

my $opt_root = $defaults->{root};
my $opt_list = false;
my $opt_applications = false;
my $opt_packages = false;
my $opt_bypath = $defaults->{bypath};
my $opt_tree = false;
my $opt_callers = false;
my $opt_publishInfos = false;
my $opt_onlyPublishables = false;

# -------------------------------------------------------------------------------------------------
# a function to deal with the next level
# returns the count of packages we have seen not yet ordered at that level
# ends when this count is zero
# (I):
# - the list of package objects
# - the iteration management object:
#   > names: the list of managed package names (those we have found)
#   > tree: the tree being built
#   > ordered: a hash of already ordered packages
#   > level: the current level number
#   > totalCount: the total packages count
#   > unknown: an array of unreferenced packages
# (O):
# - the count of packages ordered in this round

sub buildDependenciesLevel {
	my ( $packages, $iter ) = @_;
	my $count = 0;
	my $thisRound = {};
	my $unknown = [];
	foreach my $it ( @{$packages} ){
		msgVerbose( "($iter->{level}) examining $it->{name}" );
		# we didn't yet have ordered this package
		if( !$iter->{ordered}{$it->{name}} ){
			my $unorderedDeps = 0;
			foreach my $dep ( @{$it->{uses}} ){
				my $managed = grep( /^$dep$/, @{$iter->{names}} );
				msgVerbose( "  $dep is not managed here, considering it as resolved" ) if !$managed;
				if( $managed && !$iter->{ordered}{$dep} ){
					$unorderedDeps += 1;
					msgVerbose( "  depends of (unordered) $dep" );
					push( @{$iter->{unknown}}, $dep );
				}
			};
			if( $unorderedDeps ){
				msgVerbose( " still found $unorderedDeps unordered dependencies" );
			} else {
				msgVerbose( " ready to be ordered" );
				$thisRound->{$it->{name}} = true;
				$iter->{totalCount} += 1;
				$count += 1;
			}
		} else {
			msgVerbose( " already ordered" );
		}
	};
	# we have first searched for the available package at this round before storing them
	#  so that a we are sure that we do not have intra-dependency at the round level
	foreach my $it ( sort keys %{$thisRound} ){
		push( @{$iter->{tree}}, { name => $it, level => $iter->{level} });
		$iter->{ordered}{$it} = true;
	};
	return $count;
}

# -------------------------------------------------------------------------------------------------
# build a dependency tree of Meteor packages
# (I):
# - the list of package objects
# (O):
# - the dependency tree, as an object:
#   > tree: the built tree as an (alpha sorted) array, where each item is an object { name, deps }
#   > unknown: an array of unreferenced packages

sub buildDependenciesTree {
	my ( $packages ) = @_;
	my $res = {
		tree => [],
		unknown => []
	};
	my $iter = {
		tree => $res->{tree},
		names => [],
		totalCount => $res->{count},
		unknown => $res->{unknwon},
		ordered => {},
		level => 0
	};
    my $done = false;
	my $count = -1;
	foreach my $it ( @{$packages} ){
		push( @{$iter->{names}}, $it->{name} );
	}
	#print "names: ".Dumper( @{$iter->{names}} );
    while( !$done ){
        $count = buildDependenciesLevel( $packages, $iter );
        $iter->{level} += 1;
        $done = ( $count == 0 );
    }
	my $c = scalar( @{$res->{unknown}} );
	if( $c ){
		msgWarn( "found $c missing package(s): [ ".join( ', ', @{$res->{unknown}} )." ]" );
	} else {
		msgVerbose( "all packages were successfully ordered" );
	}
	return $res;
}

# -------------------------------------------------------------------------------------------------
# display a dependency tree of Meteor packages
# (I):
# - the list of packages
# - the hash of callers
# - the built dependency tree
# (O):
# - the count of displayed packages

sub displayDependenciesTree {
	my ( $packages, $callers, $tree ) = @_;
	my $count = 0;
	# build a hash of the packages by their full name
	my $packs = {};
	foreach my $it ( @{$packages} ){
		$packs->{$it->{name}} = $it;
	}
	# display the ordered tree
	foreach my $ordered ( @{$tree} ){
		my $pck = $packs->{$ordered->{name}};
		#print Dumper( $pck ) if $pck->{name} eq 'aldeed:tabular';
		my $publishable = $opt_onlyPublishables ? !$pck->{infos} || !$pck->{infos}{prev} || $pck->{infos}{changes} > 0 : true;
		if( $publishable ){
			my $str = '-';
			for( my $i=0 ; $i<$ordered->{level} ; ++$i ){
				$str .= '-';
			}
			my $publishInfos = $opt_publishInfos ? "\t".packagePublishInfos( $pck ) : '';
			printf( "%s: %s %s%s", $ordered->{level}, $str, $pck->{name}, $publishInfos );
			print EOL;
			if( $opt_callers ){
				my $line = $str;
				$line =~ s/-/ /g;
				$line .= '  ';
				$line .= ' ' if $ordered->{level} < 10;
				my $count = $callers->{$pck->{name}} ? scalar( @{$callers->{$pck->{name}}} ) : 0;
				if( $count ){
					foreach my $p ( @{$callers->{$pck->{name}}} ){
						print "$line > used by: $p".EOL;
					}
				} else {
					print "$line (unused by any package)".EOL;
				}
			}
			$count += 1;
		} else {
			msgVerbose( "$pck->{name} has nothing to release" );
			#print Dumper( $pck->{infos} );
		}
	}
	return $count;
}

# -------------------------------------------------------------------------------------------------
# display the list of the Meteor applications
# (I):
# - the list of applications
# (O):
# - the count of displayed applis

sub displayApplications {
	my ( $applications ) = @_;
	my $count = 0;
	foreach my $app ( sort { $a->{name} cmp $b->{name} } @{$applications} ){
		print " $app->{name}".EOL;
		$count += 1;
	}
	return $count;
}

# -------------------------------------------------------------------------------------------------
# display the list of the Meteor packages
# (I):
# - the list of packages
# - the hash of callers
# (O):
# - the count of displayed packages

sub displayPackages {
	my ( $packages, $callers ) = @_;
	my $count = 0;
	# build the alpha-sorted-on-name list of packages
	my $list = {};
	foreach my $it ( @{$packages} ){
		$list->{$it->{name}} = $it;
	}
	foreach my $short ( sort keys %{$list} ){
		my $pck = $list->{$short};
		#print Dumper( $pck ) if $pck->{name} eq 'aldeed:tabular';
		my $publishable = $opt_onlyPublishables ? !$pck->{infos} || !$pck->{infos}{prev} || $pck->{infos}{changes} > 0 : true;
		if( $publishable ){
			print " ".$pck->{name};
			print "\t".packagePublishInfos( $pck ) if $opt_publishInfos;
			print EOL;
			if( $opt_callers ){
				my $line = ' ';
				my $count = $callers->{$pck->{name}} ? scalar( @{$callers->{$pck->{name}}} ) : 0;
				if( $count ){
					foreach my $p ( @{$callers->{$pck->{name}}} ){
						print "$line > used by: $p".EOL;
					}
				} else {
					print "$line (unused by any package)".EOL;
				}
			}
			$count += 1;
		} else {
			msgVerbose( "$pck->{name} has nothing to release" );
			#print Dumper( $pck->{infos} );
		}
	}
	return $count;
}

# -------------------------------------------------------------------------------------------------
# list Meteor applications
# a Meteor application is identified by its (mandatory) package.json file with a (mandatory) 'meteor' key
# may have a ChangeLog.md

sub doListApplications {
	msgOut( "listing Meteor applications in '$opt_root'..." );
	my $count = 0;
	my $displayed = 0;
	# get the items in the root path, filtering directories which have a suitable package.json file
	my @items = path( $opt_root )->children;
	my @applications = ();
	# try to get and identify all Meteor applications
	foreach my $it ( @items ){
		my $obj = TTP::Meteor::getApplication( $it );
		if( $obj ){
			$obj->{infos} = getChangeLogInfos( $it );
			push( @applications, $obj );
			$count += 1;
		}
	}
	#print "packages: ".Dumper( @packages );
	$displayed = displayApplications( \@applications );
	msgOut( "found $count applications(s)" );
}

# -------------------------------------------------------------------------------------------------
# list Meteor packages
# a Meteor package is identified by its (mandatory) package.js file
# may have a ChangeLog.md

sub doListPackages {
	msgOut( "listing Meteor packages in '$opt_root'..." );
	my $count = 0;
	my $displayed = 0;
	# get the items in the root path, filtering directories which have a suitable package.js file
	my @items = path( $opt_root )->children;
	my @packages = ();
	my $callers = {};
	# try to get and identify all Meteor packages
	foreach my $it ( @items ){
		my $obj = getMeteorPackageJs( $it );
		if( $obj ){
			$obj->{infos} = getChangeLogInfos( $it );
			push( @packages, $obj );
			$count += 1;
			#print Dumper( $obj ) if $obj->{name} eq 'accounts-iziam';
			# increments the list of callers for each of the used packages
			foreach my $pck ( @{$obj->{uses}} ){
				$callers->{$pck} = [] if !$callers->{$pck};
				push( @{$callers->{$pck}}, $obj->{name} );
			}
		}
	}
	#print "packages: ".Dumper( @packages );

	# display packages as a dependency tree
	if( $opt_tree ){
		my $deps = buildDependenciesTree( \@packages );
		#print Dumper( $deps );
		#print Dumper( scalar( @{$deps->{tree}} ));
		$displayed = displayDependenciesTree( \@packages, $callers, $deps->{tree} );

	# display alpha-sorted list of packages
	} else {
		$displayed = displayPackages( \@packages, $callers );
	}
	msgOut( "found $count package(s)" );
	msgOut( "$displayed packages have something to release" ) if $opt_onlyPublishables;
}

# -------------------------------------------------------------------------------------------------
# extract publication informations from ChangeLog
# (I):
# - the directory path
# (O):
# - the informations object as an object:
#   > changes: the count of changes in the to-be-next release
#   > prev: the last release date (as a string expected to be 'yyyy-mm-dd')

sub getChangeLogInfos {
	my ( $dir ) = @_;
	my $res = undef;
	my $file = File::Spec->catfile( $dir, 'ChangeLog.md' );
	if( -r $file ){
	    my @content = split( /[\r\n]/, path( $file )->slurp_utf8 );
	    my $releaseStr = 'Release date:';
		my $status = 'start';
		my $changes = 0;
		my $prev = undef;
		foreach my $line ( @content ){
			if( $status eq 'start' ){
				if( $line =~ m/^### / ){
					if( $line =~ m/-rc/ ){
						$status = 'current';
					}
				}
			} elsif( $status eq 'current' ){
				if( $line =~ m/^\s*-/ && $line !~ m/^\s*-\s*$/ ){
					$changes += 1;
				} elsif( $line =~ m/^### / ){
					$status = 'prev';
				}
			} elsif( $status eq 'prev' ){
				if( $line =~ m/$releaseStr/ ){
					$prev = $line;
					$prev =~ s/^\s*$releaseStr\s*//;
					$status = 'end';
				}
			}
			if( $status eq 'end' ){
				$res = {
					changes => $changes,
					prev => $prev
				};
				last;
			}
		}
	} else {
		msgVerbose( "$file: file not found or not readable" );
		return undef;
	}
	return $res;
}

# -------------------------------------------------------------------------------------------------
# given a directory path, try to read the package.js (which may identify a Meteor package) inside
# (I):
# - the directory path
# (O):
# - a package object, or undef

sub getMeteorPackageJs {
	my ( $dir ) = @_;
	my $res = undef;
	if( -d $dir ){
		my $jspck = File::Spec->catfile( $dir, 'package.js' );
		if( -r $jspck ){
			$res = {
				jspck => $jspck
			};
			my $content = path( $jspck )->slurp_utf8;
			my @lines = split( /[\r\n]/, $content );
			my $c;
			# expect at least Package.describe() and maybe Package.onUse()
			my $describe = $content;
			$describe =~ s/^.*Package\.describe\s*\(\s*{([^\)}]+).*$/$1/s;
			if( $describe ){
				$res->{describe} = $describe;
			} else {
				msgWarn( "$jspck: 'Package.describe() call not found, so ignore the package" );
				return undef;
			}
			# get the name (and the owner), making sure there is one and only one
			my @names = grep( /\sname\s*:/, @lines );
			$c = scalar( @names );
			if( $c != 1 ){
				msgWarn( "$jspck: found unexpected $c 'name' tag(s), so ignore the package" );
				return undef;
			} else {
				my @parts = split( ':', $names[0], 2 );
				my $name = $parts[1];
				$name =~ s/^\s*//;
				$name =~ s/,\s*$//;
				$name =~ s/['"]//g;
				my @words = split( ':', $name );
				$res->{owner} = $words[0];
				$res->{shortName} = $words[1];
				$res->{name} = $name;
			}
			# get the version
			my @versions = grep( /\sversion\s*:/, @lines );
			$c = scalar( @versions );
			if( $c != 1 ){
				msgWarn( "$jspck: found unexpected $c 'version' tag(s), so ignore the package" );
				return undef;
			} else {
				my @parts = split( ':', $versions[0], 2 );
				my $version = $parts[1];
				$version =~ s/^\s*//;
				$version =~ s/,\s*$//;
				$version =~ s/['"]//g;
				$res->{version} = $version;
			}
			# get the summary
			my @summaries = grep( /\ssummary\s*:/, @lines );
			$c = scalar( @summaries );
			if( $c != 1 ){
				msgWarn( "$jspck: found unexpected $c 'summary' tag(s), so ignore the package" );
				return undef;
			} else {
				my @parts = split( ':', $summaries[0], 2 );
				my $summary = $parts[1];
				$summary =~ s/^\s*//;
				$summary =~ s/,\s*$//;
				$summary =~ s/['"]//g;
				$res->{summary} = $summary;
			}
			# get all api.use() dependents
			# which can be specified as something.use( package ) or .use([ pack1, pck2 ]) with one package per line or all on the same line
			# plus a small hack to consider the _use() cases
			my @uses = ( $content =~ /[\._]use\s*\(([^\);]+)\)\s*;/g );
			my $useres = {};
			my $debug = false;
			#$debug = true if $res->{name} eq 'accounts-iziam';
			foreach my $it ( @uses ){
				my $args = $it;
				print "\$args ".Dumper( $args ) if $debug;
				if( $args =~ m/^\s*\[/ ){
					print "have [".EOL if $debug;
					$args =~ s/^\s*\[([^\]]+)\].*$/$1/s;
					print "\$args='$args'".EOL if $debug;
					my @args = split( /[\r\n,]/, $args );
					print "\@args ".Dumper( @args ) if $debug;
					foreach my $arg ( @args ){
						_getMeteorPackageDependency( $res, $useres, $arg );
					}
				} else {
					print "do not have [".EOL if $debug;
					my @args = split( /\s*,\s*/, $args, 2 );
					$args = $args[0];
					$args =~ s/^\s*([^,]+).*$/$1/;
					_getMeteorPackageDependency( $res, $useres, $args );
				}
			}
			my @useres = sort keys %{$useres};
			$res->{uses} = \@useres;
		} else {
			msgVerbose( "$jspck: file not found or not readable" );
			return undef;
		}
	} else {
		msgVerbose( "$dir: not a directory" );
		return undef;
	}
	return $res;
}

sub _getMeteorPackageDependency {
	my ( $self, $deps, $arg ) = @_;

	$arg =~ s/^\s*['",]\s*//g;
	$arg =~ s/\s*['",]\s*$//g;
	$arg =~ s/^\s*$//;
	$arg =~ s/\@.*$//;

	# do not consider as a dependency this same package
	$deps->{$arg} = true if $arg && $arg ne "$self->{name}" && $arg !~ m/\.\.\.arguments/;
}

# -------------------------------------------------------------------------------------------------
# build a string with publication informations
# (I):
# - the package object with an 'infos' key
# (O):
# - the built string

sub packagePublishInfos {
	my ( $pck ) = @_;
	my $str = '';
	if( $pck->{infos} ){
		$str .= '{ lastRelease: "'
			.$pck->{infos}{prev}
			.'", pendingChanges: '
			.$pck->{infos}{changes}
			.' }';
	}
	return $str;
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"					=> sub { $ep->runner()->help( @_ ); },
	"colored!"				=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"				=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"				=> sub { $ep->runner()->verbose( @_ ); },
	"root=s"				=> \$opt_root,
	"applications!"			=> \$opt_applications,
	"packages!"				=> \$opt_packages,
	"bypath=s"				=> \$opt_bypath,
	"tree!"					=> \$opt_tree,
	"callers!"				=> \$opt_callers,
	"publishInfos!"			=> \$opt_publishInfos,
	"only-publishables!"	=> \$opt_onlyPublishables )){

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
msgVerbose( "got root='$opt_root'" );
msgVerbose( "got applications='".( $opt_applications ? 'true':'false' )."'" );
msgVerbose( "got packages='".( $opt_packages ? 'true':'false' )."'" );
msgVerbose( "got bypath='$opt_bypath'" );
msgVerbose( "got tree='".( $opt_tree ? 'true':'false' )."'" );
msgVerbose( "got callers='".( $opt_callers ? 'true':'false' )."'" );
msgVerbose( "got publish-infos='".( $opt_publishInfos ? 'true':'false' )."'" );
msgVerbose( "got only-publishables='".( $opt_onlyPublishables ? 'true':'false' )."'" );

# get root absolute path which must exist
$opt_root = path( $opt_root )->realpath;
msgErr( "--root='$opt_root': directory not found or not available" ) if !-d $opt_root;

# should list (packages or applications)
msgWarn( "will not list anything as neither '--applications' nor '--packages' options are set" ) if !$opt_applications && !$opt_packages;

if( !TTP::errs()){
	doListApplications() if $opt_applications;
	doListPackages() if $opt_packages;
}

TTP::exit();
