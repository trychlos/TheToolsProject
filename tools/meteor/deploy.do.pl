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
# @(-) --collection=<collection>   deploy the named collection, may be specified several times or as a comma-separated list [${collection}|ALL]
# @(-) --json=<json>               use this json deployment description [${json}]
# @(-) --[no]list                  list defined target environments [${list}]
#
# @(@) Note 1: Deploying from any environment A to any environment B always requires the availability of the json deploiement description file,
# @(@)         which is not part of any bundle, so not delpoyed, so only available in the development environment(s).
# @(@) Note 2: The json deployment description contains sensitive data. Remind that you SHOULD not publish it, and consider adding it to your .gitignore.
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
	collection => '',
	json => File::Spec->catfile( File::Spec->catdir( Path::Tiny->cwd, 'maintainer', 'private' ), 'deployments.json' ),
	list => 'no'
};

my $opt_application = $defaults->{application};
my $opt_from = $defaults->{from};
my $opt_to = $defaults->{to};
my $opt_bundle = false;
my @opt_collections = ();
my $opt_json = $defaults->{json};
my $opt_list = false;

# the application object as returned by TTP::Meteor::getApplication()
my $app;
# the defined target environments from deployement.json
my $targets;

# -------------------------------------------------------------------------------------------------
# deploy a bundle

sub doDeployBundle {
	msgOut( "deploying..." );
	msgOut( "done" );
}

# -------------------------------------------------------------------------------------------------
# deploy one or more collections

sub doDeployCollections {
	msgOut( "deploying..." );
	msgOut( "done" );
}

# -------------------------------------------------------------------------------------------------
# list the defined target environments

sub doListEnvironments {
	msgOut( "listing defined target environments for '$app->{name}' application..." );
	my $count = 0;
	foreach my $it ( sort keys %{$targets->{targets}} ){
		print " $it";
		print " ($targets->{targets}{$it}{env})" if $targets->{targets}{$it}{env};
		print EOL;
		$count += 1;
	}
	msgOut( "found $count defined target environment(s)" );
}

# -------------------------------------------------------------------------------------------------
# returns the content of the deployement.json file
# must have a non-empty 'targets' value
# (I):
# - none
# (O):
# - the read json or undef

sub getJsonDeployement {
    my $json = $opt_json || File::Spec->catfile( File::Spec->catdir( $opt_application, 'maintainer' ), 'targets.json' );
	my $res;
	if( -r $json ){
		$res = decode_json( path( $json )->slurp_utf8 );
		if( !$res->{targets} ){
			msgErr( "$json deployement file lacks of a non-empty 'targets' value" );
			return undef;
		}
	} else {
		msgErr( "$json: file not found or not readable" );
		return undef;
	}
    return $res;
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
	"list!"					=> \$opt_list )){

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
msgVerbose( "got list='".( $opt_list ? 'true':'false' )."'" );

# get application absolute path which must exist
$opt_application = path( $opt_application )->realpath;
if( -d $opt_application ){
	$app = TTP::Meteor::getApplication( $opt_application );
	if( $app ){
		$targets = getJsonDeployement();
	} else {
		msgErr( "--application='$opt_application' doesn't address a Meteor application" );
	}
} else {
	msgErr( "--application='$opt_application': directory not found or not available" );
}

# from, to, bundle, collection are deploiement options, are ignored when just listing the environments
# when listing, we do not deploy
if( $opt_list ){
	msgWarn( "'--from' is a deploiement option, ignored when listing environment" ) if $opt_from;
	msgWarn( "'--to' is a deploiement option, ignored when listing environment" ) if $opt_to;
	msgWarn( "'--bundle' is a deploiement option, ignored when listing environment" ) if $opt_bundle;
	msgWarn( "'--collection' is a deploiement option, ignored when listing environment" ) if scalar @opt_collections;
} else {
	# when deploying, '--from- defaults to the current local environment
	# --to is mandatory
	# must deploy at least a bundle or a collection
	# cowardly refuse to deploy to a development environment
	if( $opt_to ){

	} else {
		msgErr( "'--to' option is mandatory when deploying" );
	}
	msgWarn( "neither '--bundle' nor '--collection' options are specified, will not deploy anything" ) if !$opt_bundle && !scalar( @opt_collections );
}

if( !TTP::errs()){
	if( $opt_list ){
		doListEnvironments();
	} else {
		doDeployBundle() if $opt_bundle;
		doDeployCollections() if scalar( @opt_collections );
	}
}

TTP::exit();
