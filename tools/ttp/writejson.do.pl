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

use File::Temp;
use JSON;

use TTP::Path;

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

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> sub { $ep->runner()->help( @_ ); },
	"colored!"			=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"			=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"			=> sub { $ep->runner()->verbose( @_ ); },
	"file=s"			=> \$opt_file,
	"dir=s"				=> \$opt_dir,
	"template=s"		=> \$opt_template,
	"suffix=s"			=> \$opt_suffix,
	"data=s"			=> \$opt_data,
	"append!"			=> \$opt_append )){

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
msgVerbose( "got file='$opt_file'" );
msgVerbose( "got dir='$opt_dir'" );
msgVerbose( "got template='$opt_template'" );
msgVerbose( "got suffix='$opt_suffix'" );
msgVerbose( "got data='$opt_data'" );
msgVerbose( "got append='".( defined $opt_append ? ( $opt_append ? 'true':'false' ) : '(undef)' )."'" );

msgWarn( "'ttp.pl writejson' verb is deprecated in favor of 'ttp.pl writefile' since v4.32. You should update your code and/or your configurations." );

my @argv = @{ $ep->runner()->argv() };
shift( @argv );
# protect data against shell interpretation
for( my $i=0; $i<scalar( @argv ); ++$i ){
	my $it = $argv[$i];
	if( $it =~ m/-data/ ){
		if( $it =~ m/-data=/ ){
			$it =~ s/"/\\"/g;
			$it =~ s/=/="/;
			$it = "$it\"";
			$argv[$i] = $it;
		} else {
			$it = $argv[$i+1];
			$it =~ s/"/\\"/g;
			$it = "\"$it\"";
			$argv[$i+1] = $it;
		}
		last;
	}
}

my $res = TTP::commandExec( "ttp.pl writefile ".join( ' ', @argv ));
foreach my $it ( @{$res->{stdouts}} ){
	print $it.EOL;
}
foreach my $it ( @{$res->{stderrs}} ){
	print $it.EOL;
}

TTP::exit();
