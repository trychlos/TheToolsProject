# @(#) write JSON data into a file
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --file=<filename>       the filename where to write the data [${file}]
# @(-) --dir=<dir>             the directory where to create the file [${dir}]
# @(-) --template=<template>   the filename template [${template}]
# @(-) --suffix=<suffix>       the filename suffix [${suffix}]
# @(-) --data=<data>           the data to be written as a JSON string [${data}]
# @(-) --[no]append            whether to append to the file [${append}]
#
# The Tools Project - Tools System and Working Paradigm for IT Production
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

use File::Temp;
use JSON;

my $running = $ep->runner();

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	file => '',
	dir => '',
	template => '',
	suffix => '.json',
	data => '{}',
	append => 'no'
};

my $opt_file = $defaults->{file};
my $opt_dir = $defaults->{dir};
my $opt_template = $defaults->{template};
my $opt_suffix = $defaults->{suffix};
my $opt_data = $defaults->{data};
my $opt_append = false;

# -------------------------------------------------------------------------------------------------
# write the data into the file

sub doWriteJson {
	msgOut( "writing JSON data into ".( $opt_file ? "'$opt_file' file" : "'$opt_dir' dir" )."..." );
	my $res = false;
	my $json = JSON->new;
	my $data = $json->decode( $opt_data );
	# if no filename is provided, compute one with maybe a dir, maybe a template, maybe a suffix
	if( !$opt_file ){
		my %parms = ();
		if( $opt_dir ){
			$parms{DIR} = $opt_dir;
			TTP::makeDirExist( $opt_dir );
		}
		$parms{TEMPLATE} = $opt_template if $opt_template;
		$parms{SUFFIX} = $opt_suffix if $opt_suffix;
		$parms{UNLINK} = false;
		my $tmp = File::Temp->new( %parms );
		$opt_file = $tmp->filename();
		msgVerbose( "setting opt_file tp '$opt_file'" );
	}
	if( $opt_append ){
		$res = TTP::jsonAppend( $data, $opt_file );
	} else {
		$res = TTP::jsonWrite( $data, $opt_file );
	}
	if( $res ){
		msgOut( "success" );
	} else {
		msgErr( "NOT OK" );
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$ep->{run}{help},
	"colored!"			=> \$ep->{run}{colored},
	"dummy!"			=> \$ep->{run}{dummy},
	"verbose!"			=> \$ep->{run}{verbose},
	"file=s"			=> \$opt_file,
	"dir=s"				=> \$opt_dir,
	"template=s"		=> \$opt_template,
	"suffix=s"			=> \$opt_suffix,
	"data=s"			=> \$opt_data,
	"append!"			=> \$opt_append )){

		msgOut( "try '".$running->command()." ".$running->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $running->help()){
	$running->verbHelp( $defaults );
	TTP::exit();
}

msgVerbose( "got colored='".( $running->colored() ? 'true':'false' )."'" );
msgVerbose( "got dummy='".( $running->dummy() ? 'true':'false' )."'" );
msgVerbose( "got verbose='".( $running->verbose() ? 'true':'false' )."'" );
msgVerbose( "got file='$opt_file'" );
msgVerbose( "got dir='$opt_dir'" );
msgVerbose( "got template='$opt_template'" );
msgVerbose( "got suffix='$opt_suffix'" );
msgVerbose( "got data='$opt_data'" );
msgVerbose( "got append='".( defined $opt_append ? ( $opt_append ? 'true':'false' ) : '(undef)' )."'" );

# data is mandatory
msgErr( "data is mandatory, not specified" ) if !$opt_data;
# a filename is mandatory if we want to append to it
msgErr( "filename is mandatory to be able to append to it, not specified" ) if !$opt_file && $opt_append;

if( !TTP::errs()){
	doWriteJson();
}

TTP::exit();
