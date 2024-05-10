# @(#) display a configuration variable on stdout
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --service=<name>        display informations about the named service [${service}]
# @(-) --key=<name[,...]>      a comma-separated list of keys to reach the desired value, may be specified several times [${key}]
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

use TTP::Service;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	service => '',
	key => ''
};

my $opt_service = $defaults->{service};
my @opt_keys = ();

# -------------------------------------------------------------------------------------------------

sub displayVar {
	msgOut( "displaying '".join( ',', @opt_keys )."' variable..." );
	#print Dumper( $opt_keys );
	my @initialKeys = @opt_keys;
	my $service = TTP::Service->new( $ep, { service => $opt_service });
	if( !TTP::errs()){
		TTP::print( ' '.join( ',', @opt_keys ), $service->var( \@opt_keys ));
	}
	if( !TTP::errs()){
		msgOut( "done" );
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
	"service=s"			=> \$opt_service,
	"key=s@"			=> \@opt_keys )){

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
msgVerbose( "found service='$opt_service'" );
@opt_keys = split( /,/, join( ',', @opt_keys ));
msgVerbose( "found keys='".join( ',', @opt_keys )."'" );

msgErr( "a service is required, but not found" ) if !$opt_service;
msgErr( "at least a key is required, but none found" ) if !scalar( @opt_keys );

if( !TTP::errs()){
	displayVar() if $opt_service && scalar( @opt_keys );
}

TTP::exit();
