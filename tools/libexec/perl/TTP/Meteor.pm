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
# A package dedicated to PostgreSQL

package TTP::Meteor;
die __PACKAGE__ . " must be loaded as TTP::Meteor\n" unless __PACKAGE__ eq 'TTP::Meteor';

use strict;
use utf8;
use warnings;

use Data::Dumper;
use File::Spec;
use JSON;
use Path::Tiny;

use TTP;
use TTP::Constants qw( :all );
use TTP::Message qw( :all );

my $Const = {
	# how to find the initial scaffolding
	appFinder => {
		dirs => [
			'libexec/meteor/app'
		]
	},
	pckFinder => {
		dirs => [
			'libexec/meteor/package'
		]
	},
	# 
	app => {

	},
	package => {
		md => [
			'ChangeLog.md',
			'README.md',
			'TODO.md'
		]
	}
};

# ------------------------------------------------------------------------------------------------
# Returns the full specifications to find the application scaffolding
# (I):
# - none
# (O):
# - returns a ref to the finder

sub appFinder {
	my %finder = %{$Const->{appFinder}};

	return \%finder;
}

# ------------------------------------------------------------------------------------------------
# does the given directory host a Meteor application ?
# (I):
# - a directory path
# (O):
# - an application object with following keys:
#   > dir: the path to the application directory
#   > json: the path to the package.json file
#   > name: the name of the application, from package.json
#   > version: the Meteor version for the application
# - returns undef if not a Meteor application

sub getApplication {
	my ( $dir ) = @_;
	my $res = undef;

	if( -d $dir ){
		# must have a .meteor/ subdirectory
		my $meteor = File::Spec->catdir( $dir, '.meteor' );
		if( ! -d $meteor ){
			msgVerbose( "$meteor: directory not found or not available" );
			return undef;
		}
		# must have a package.json with 'name' and 'meteor' keys
		my $json = File::Spec->catfile( $dir, 'package.json' );
		my $content;
		if( -r $json ){
			$content = decode_json( path( $json )->slurp_utf8 );
			# expect a non-empty 'name' value
			if( !$content->{name} ){
				msgVerbose( "$json: expects a 'name' key, not found" );
				return undef;
			}
			# expect a non-empty 'meteor' value
			if( !$content->{meteor} ){
				msgVerbose( "$json: expects a 'meteor' key, not found" );
				return undef;
			}
		} else {
			msgVerbose( "$json: file not found or not readable" );
			return undef;
		}
		# must accept the execution of meteor commands
		my $command = '(cd $dir; meteor --version)';
		my $out = TTP::commandExec( $command );
		if( @{$out->{stderrs}} ){
			msgVerbose( "$dir: $out->{stderrs}->[0]" );
			return undef;
		}
		my $version = $out->{stdouts}->[0];
		$res = {
			dir => $dir,
			json => $json,
			name => $content->{name},
			version => $version
		};
	} else {
		msgVerbose( "$dir: not a directory" );
		return undef;
	}

	return $res;
}

# ------------------------------------------------------------------------------------------------
# does the given directory host a Meteor package ?
# (I):
# - a directory path
# (O):
# - a package object with following keys:
#   > dir: the path to the package directory
#   > js: the path to the package.js file
#   > name: the name of the package
#   > ChangeLog.md: the full path to ChangeLog.md
#   > README.md: the full path to README.md
#   > TODO.md: the full path to TODO.md
# - returns undef if not a Meteor package

sub getPackage {
	my ( $dir ) = @_;
	my $res = undef;

	if( -d $dir ){
		# test package.js
		my $jspck = File::Spec->catfile( $dir, 'package.js' );
		if( -r $jspck ){
			$res = {};
			$res->{jspck} = $jspck;
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
						_getPackageDependency( $res, $useres, $arg );
					}
				} else {
					print "do not have [".EOL if $debug;
					my @args = split( /\s*,\s*/, $args, 2 );
					$args = $args[0];
					$args =~ s/^\s*([^,]+).*$/$1/;
					_getPackageDependency( $res, $useres, $args );
				}
			}
			my @useres = sort keys %{$useres};
			$res->{uses} = \@useres;
			# test other files
			my $ok = true;
			foreach my $it ( @{$Const->{package}{md}} ){
				my $file = File::Spec->catfile( $dir, $it );
				if( -r $file ){
					$res->{$it} = $file;
				} else {
					msgWarn( "$file: not found or not readable" );
					$ok = false;
				}
			}
			return undef if !$ok;
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

sub _getPackageDependency {
	my ( $self, $deps, $arg ) = @_;

	$arg =~ s/^\s*['",]\s*//g;
	$arg =~ s/\s*['",]\s*$//g;
	$arg =~ s/^\s*$//;
	$arg =~ s/\@.*$//;

	# do not consider as a dependency this same package
	$deps->{$arg} = true if $arg && $arg ne "$self->{name}" && $arg !~ m/\.\.\.arguments/;
}

# ------------------------------------------------------------------------------------------------
# get the list of .md files of a package
# (I):
# - none
# (O):
# - the list of MD files a package is expected to manage as an array ref

sub getPackageMD {
	return $Const->{package}{md};
}

# ------------------------------------------------------------------------------------------------
# Says if the directory hosts a Meteor application project
# (I):
# - the directory path
# (O):
# - true|false

sub isDevel {
	my( $dir ) = @_;

	my $app = TTP::Meteor::getApplication( $dir );

	return defined( $app ) && ref( $app ) eq 'HASH';
}

1;

__END__
