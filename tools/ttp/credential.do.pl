# @(#) display a credential
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --node=<node>           the relevant node [${node}]
# @(-) --key=<name[,...]>      the key which addresses the desired value, may be specified several times or as a comma-separated list [${key}]
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

use TTP::Credentials;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	node => $ep->node()->name(),
	key => ''
};

my $opt_node = $defaults->{node};
my @opt_keys = ();

# -------------------------------------------------------------------------------------------------
# get and display a single credential

sub getCredential {
	my $node = TTP::Node->new( $ep, { node => $opt_node });
	my $o = TTP::Credentials::get( \@opt_keys, $node );
	# print the keys
	print " [".join( ',', @opt_keys )."]: ";
	# if the returned value is a scalar, unquote it
	if( $o && !ref( $o )){
		my $s = TTP::chompDumper( $o );
		$s =~ s/'//g;
		print "$s".EOL;
	} else {
		print TTP::chompDumper( $o ).EOL;
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> sub { $ep->runner()->help( @_ ); },
	"colored!"			=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"			=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"			=> sub { $ep->runner()->verbose( @_ ); },
	"node=s"			=> \$opt_node,
	"key=s"				=> \@opt_keys )){

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
msgVerbose( "got node='$opt_node'" );
@opt_keys= split( /,/, join( ',', @opt_keys ));
msgVerbose( "got keys=[".join( ',', @opt_keys )."]" );

# node must be set
msgErr( "'--node' option is mandatory" ) if !$opt_node;

# at least one key must be specified
msgErr( "at least one '--key' option must be specified, none found" ) if !scalar( @opt_keys );

if( !TTP::errs()){
	getCredential();
}

TTP::exit();
