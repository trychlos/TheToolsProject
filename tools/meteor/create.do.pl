# @(#) create a new application or package
#
# @(-) --[no]help                  print this message, and exit [${help}]
# @(-) --[no]colored               color the output depending of the message level [${colored}]
# @(-) --[no]dummy                 dummy run [${dummy}]
# @(-) --[no]verbose               run verbosely [${verbose}]
# @(-) --path=<path>               new object root path [${path}]
# @(-) --[no]application           create a new application [${application}]
# @(-) --name=<name>               the name of the application [${name}]
# @(-) --label=<label>             the label of the application [${label}]
# @(-) --title=<title>             the title of the application [${title}]
# @(-) --[no]tenants               have a multi-tenants application [${tenants}]
# @(-) --[no]package               create a new package [${package}]
#
# @(@) Note 1: The created object will reflect our design decisions:
# @(@)         - application will be created with Blaze front-end, bootstrap-based, and our pwix:core-app main package
# @(@)         - both application and package will be created with our standard structure.
# @(@) Note 2: The name of the package is directly derived from the name of the directory which should be formatted as 'owner-name'.
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

use Config;
use File::Spec;
use JSON;
use Path::Tiny;

use TTP::Meteor;
use TTP::Path;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	path => Path::Tiny->cwd,
	application => 'no',
	name => 'MyApplication',
	label => 'MyApplication AppLabel',
	title => 'MyApplication AppTitle',
	tenants => 'no',
	package => 'no'
};

my $opt_path = $defaults->{path};
my $opt_application = false;
my $opt_name = $defaults->{name};
my $opt_label = $defaults->{label};
my $opt_title = $defaults->{title};
my $opt_tenants = false;
my $opt_package = false;

# the NPM packages to be installed in our standard application
my $app_npms = [
	'@popperjs/core',
	'@vestergaard-company/js-mixin',
	'bootstrap',
	'datatables.net-bs5',
    'datatables.net-buttons-bs5',
    'datatables.net-colreorder-bs5',
    'datatables.net-fixedheader-bs5',
    'datatables.net-responsive-bs5',
    'datatables.net-rowgroup-bs5',
    'datatables.net-scroller-bs5',
	'detect-it',
    'ellipsize',
    'email-validator',
    'jquery-resizable-dom',
    'jquery-ui',
    'js-yaml',
    'jstree',
	'lodash',
	'multiple-select',
	'printf',
	'strftime',
	'uuid',
	'valid-url',
	'zxcvbn'
];

# the Meteor packages to be installed in our standard application
my $app_meteor_packages = [
	'jquery'
];

# the Meteor packages to be locally installed in our standard application
my $app_meteor_local = [
	'pwix:accounts-hub',
	'pwix:accounts-manager',
	'pwix:accounts-ui',
	'pwix:app-pages',
	'pwix:app-pages-edit',
	'pwix:app-pages-i18n',
	'pwix:blaze-layout',
	'pwix:bootbox',
	'pwix:collection-behaviours',
	'pwix:collection-timestampable',
	'pwix:core-app',
	'pwix:cookie-manager',
	'pwix:date',
	'pwix:date-input',
	'pwix:editor',
	'pwix:env-settings',
	'pwix:env-settings-ext',
	'pwix:field',
	'pwix:forms',
	'pwix:i18n',
	'pwix:image-includer',
	'pwix:jquery-ui',
	'pwix:jstree',
	'pwix:modal',
	'pwix:modal-info',
	'pwix:notes',
	'pwix:options',
	'pwix:permissions',
	'pwix:plus-button',
	'pwix:roles',
	'pwix:ssr',
	'pwix:startup-app-admin',
	'pwix:tabbed',
	'pwix:tabular',
	'pwix:tenants-manager',
	'pwix:toggle-switch',
	'pwix:tolert',
	'pwix:typed-message',
	'pwix:ui-bootstrap5',
	'pwix:ui-fontawesome6',
	'pwix:ui-layout',
	'pwix:ui-utils',
	'pwix:validity',
];

# whether we have specified application-only options
my $opt_name_set = false;
my $opt_label_set = false;
my $opt_tenants_set = false;
my $opt_title_set = false;

# -------------------------------------------------------------------------------------------------
# create a new application
# meteor script let us choose either bare, minimal or full options
# at least with Blaze, minimal and full are same, include a home page and jquery, but bare is enough

sub doCreateApplication {
	msgOut( "creating a new Meteor application in '$opt_path'..." );
	my $stdout = execLocal( "meteor create --blaze --bare $opt_path" );
	return if !$stdout;
	# install application initial scaffolding
	msgOut( " install initial scaffolding" );
	my @roots = split( /$Config{path_sep}/, $ENV{TTP_ROOTS} );
	my $specs = TTP::Meteor::appFinder()->{dirs};
	LOOP: foreach my $it ( @roots ){
		foreach my $sub ( @{$specs} ){
			my $dir = File::Spec->catdir( $it, $sub );
			if( -d $dir ){
				execLocal( "cp -rp $dir/* $opt_path/" );
				execLocal( "for f in \$(find $opt_path -type f); do sed -i -e 's|MyApplication AppLabel|$opt_label|' -e 's|MyApplication AppTitle|$opt_title|' -e 's|MyApplication|$opt_name|' \$f; done" );
				last LOOP;
			}
		}
	}
	# update application package.json
	msgOut( " update package.json" );
	return if !updatePackageJson();
	# install npm packages
	msgOut( " install npm packages" );
	$stdout = execLocal( "(cd $opt_path && meteor npm install ".join( ' ', @{$app_npms} ).")" );
	return if !$stdout;
	# install standard Meteor packages
	msgOut( " install standard Meteor packages" );
	execLocal( "(cd $opt_path && meteor add ".join( ' ', @{$app_meteor_packages} ).")" );
	# install local Meteor packages
	msgOut( " install local Meteor packages" );
	foreach my $it ( @{$app_meteor_local} ){
		my $dir = $it;
		$dir =~ s/:/-/;
		my @words = split( /:/, $it, 2 );
		my $name = $words[1];
		execLocal( "(cd $opt_path/packages && ln -s ../../$dir $name)" );
	}
	execLocal( "(cd $opt_path && meteor add ".join( ' ', @{$app_meteor_local} ).")" );
	# if the applications wants manage several tenants
	msgOut( " patching application configuration for multi-tenants (or not)" );
	my $tenant_enabled = $opt_tenants ? 'true' : 'false';
	execLocal( "for f in \$(find $opt_path -type f); do sed -i -e 's|TENANTS_ENABLED|$tenant_enabled|' \$f; done" );
	msgOut( "done" );
}

# -------------------------------------------------------------------------------------------------
# create a new package

sub doCreatePackage {
	msgOut( "creating a new Meteor package in '$opt_path'..." );
	msgOut( "done" );
}

# -------------------------------------------------------------------------------------------------
# after execution, stderr is printed as errors
# return $stdout or undef if an errors have been printed

sub execLocal {
    my ( $cmd, $opts ) = @_;
	$opts //= {};
	msgVerbose( $cmd );
	my $res = TTP::commandExec( $cmd, $opts );
	if( scalar( @{$res->{stderrs}} )){
		msgErr( $res->{stderrs} );
		delete $res->{stdouts};
	}
	return $res->{stdouts};
}

# -------------------------------------------------------------------------------------------------
# update the bare package.json to be identical to the full one
# set name and scripts datas
# return true|false

sub updatePackageJson {
	my $json = File::Spec->catfile( $opt_path, 'package.json' );
	if( -r $json ){
		my $pck = decode_json( path( $json )->slurp_utf8 );
		$pck->{name} = $opt_name;
		$pck->{scripts}{test} = 'meteor test --once --driver-package meteortesting:mocha';
		$pck->{scripts}{'test-app'} = 'TEST_WATCH=1 meteor test --full-app --driver-package meteortesting:mocha';
		$pck->{scripts}{visualize} = 'meteor --production --extra-packages bundle-visualizer';
		$pck->{meteor} = {};
		$pck->{meteor}{mainModule} = {
			client => 'client/main.js',
			server => 'server/main.js'
		};
		$pck->{meteor}{testModule} = 'tests/main.js';
		path( $json )->spew_utf8( to_json( $pck, { utf8 => true, pretty => true }));
	} else {
		msgErr( "$json: file not found or not readable" );
		return false;
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
	"path=s"				=> \$opt_path,
	"application!"			=> \$opt_application,
	"name=s"				=> sub {
		my ( $name, $value ) = @_;
		$opt_name = $value;
		$opt_name_set = true;
	},
	"label=s"				=> sub {
		my ( $name, $value ) = @_;
		$opt_label = $value;
		$opt_label_set = true;
	},
	"title=s"				=> sub {
		my ( $name, $value ) = @_;
		$opt_title = $value;
		$opt_title_set = true;
	},
	"tenants!"				=> sub {
		my ( $name, $value ) = @_;
		$opt_tenants = $value;
		$opt_tenants_set = true;
	},
	"package!"				=> \$opt_package )){

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
msgVerbose( "got path='$opt_path'" );
msgVerbose( "got application='".( $opt_application ? 'true':'false' )."'" );
msgVerbose( "got name='$opt_name'" );
msgVerbose( "got label='$opt_label'" );
msgVerbose( "got title='$opt_title'" );
msgVerbose( "got tenants='".( $opt_tenants ? 'true':'false' )."'" );
msgVerbose( "got package='".( $opt_package ? 'true':'false' )."'" );

# get absolute path which must not exist
$opt_path = path( $opt_path )->realpath;
if( -d $opt_path ){
	msgErr( "--path='$opt_path': directory already exists" );
}

# expect either a package or an application (and not both)
msgErr( "expect either '--application' or '--package' option, both found" ) if $opt_application && $opt_package;
msgWarn( "neither '--application' nor '--package' options are specified, will not create anything" ) if !$opt_application && !$opt_package;

# the name, label, title, tenants must only be set for an application
if( $opt_name_set && !$opt_application ){
	msgWarn( "'--name' option only applies when creating a new application, ignored here" );
}
if( $opt_label_set && !$opt_application ){
	msgWarn( "'--label' option only applies when creating a new application, ignored here" );
}
if( $opt_title_set && !$opt_application ){
	msgWarn( "'--title' option only applies when creating a new application, ignored here" );
}
if( $opt_tenants_set && !$opt_application ){
	msgWarn( "'--[no]tenants' option only applies when creating a new application, ignored here" );
}

if( !TTP::errs()){
	doCreateApplication() if $opt_application;
	doCreatePackage() if $opt_package;
}

TTP::exit();
