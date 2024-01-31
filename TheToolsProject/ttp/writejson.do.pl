# @(#) write JSON data into a file
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --file=<filename>       the filename where to write the data [${file}]
# @(-) --data=<data>           the data to be written as a JSON string [${data}]
# @(-) --[no]append            whether to append to the file [${append}]
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

use JSON;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	file => '',
	data => '{}',
	append => 'no'
};

my $opt_file = $defaults->{file};
my $opt_data = $defaults->{data};
my $opt_append = false;

# -------------------------------------------------------------------------------------------------
# write the data into the file

sub doWriteJson {
	msgOut( "writing JSON data into $opt_file..." );
	my @to = split( /,/, $opt_to );
	my $res = false;
	my $json = JSON->new;
	my $data = $json->decode( $opt_data );
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
	"help!"				=> \$ttp->{run}{help},
	"colored!"			=> \$ttp->{run}{colored},
	"dummy!"			=> \$ttp->{run}{dummy},
	"verbose!"			=> \$ttp->{run}{verbose},
	"file=s"			=> \$opt_file,
	"data=s"			=> \$opt_data,
	"append!"			=> \$opt_append )){

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
msgVerbose( "found file='$opt_file'" );
msgVerbose( "found data='$opt_data'" );
msgVerbose( "found append='".( defined $opt_append ? ( $opt_append ? 'true':'false' ) : '(undef)' )."'" );

# all data are mandatory, and we must provide some content, either text or html
msgErr( "file is mandatory, not specified" ) if !$opt_file;
msgErr( "data is mandatory, not specified" ) if !$opt_data;

if( !TTP::errs()){
	doWriteJson();
}

TTP::exit();
