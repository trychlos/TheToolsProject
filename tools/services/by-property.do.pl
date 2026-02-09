# @(#) identifies the node which exhibits the specified property
#
# @(-) --[no]help                   print this message, and exit [${help}]
# @(-) --[no]colored                color the output depending of the message level [${colored}]
# @(-) --[no]dummy                  dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose                run verbosely [${verbose}]
# @(-) --service=<name>             acts on the named service [${service}]
# @(-) --property=<name>=<value>    the searched property name and its value [${property}]
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

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	service => '',
	property => ''
};

my $opt_service = $defaults->{service};
my $opt_property = $defaults->{property};

my $property_name = undef;
my $property_value = undef;
my $service_obj = undef;

# -------------------------------------------------------------------------------------------------
# search the node which exhibits the requested property

sub doSearch {
	msgOut( "examining nodes to find '$property_name'='$property_value'..." );

	# build a sorted list of candidate nodes
	# we search first in our own environment, and then in other nodes
	my $this_env = $ep->node()->environment() // '';
	my $nodes_list = TTP::Node->list();
	my $candidate_nodes = [];
	foreach my $node_name ( @{$nodes_list} ){
		my $node_obj = TTP::Node->new( $ep, { node => $node_name });
		if( $node_obj->hasService( $opt_service )){
			my $env = $node_obj->environment() // '';
			if( $env && $env eq $this_env ){
				push( @{$candidate_nodes}, { rank => 0, node => $node_obj });
			} else {
				push( @{$candidate_nodes}, { rank => 1, node => $node_obj });
			}
		} else {
			msgVerbose( "node '$node_name' doesn't host the '$opt_service' service" );
		}
	}
	my $count = scalar( @{$candidate_nodes} );
	#print STDERR "count=$count\n";
	#print STDERR "candidates ".Dumper( $candidate_nodes );
	if( $count ){
		my @ordered_nodes = sort sort_fn @{$candidate_nodes};
		$candidate_nodes = [];
		my @names = split( /,/, $property_name );
		unshift( @names, 'properties' );
		for my $it ( @ordered_nodes ){
			#print STDERR $it->{node}->name().EOL;
			my $property = $service_obj->var([ @names ], $it->{node} );
			if( $property ){
				$property = property_value( $property, \@names, $it->{node} );
				if( $property eq $property_value ){
					push( @{$candidate_nodes}, $it->{node} );
					msgVerbose( "node='".$it->{node}->name()."' has '$property_name=$property_value'" ); 
				} else {
					msgVerbose( "node='".$it->{node}->name()."' has wrong '$property_name=$property' value" ); 
				}
			} else {
				msgVerbose( "node '".$it->{node}->name()."' doesn't exhibit '$property_name' property" );
			}
		}
		$count = scalar( @{$candidate_nodes} );
		if( $count == 1 ){
			print $candidate_nodes->[0]->name().EOL;
		} elsif( $count == 0 ){
			msgOut( "no node has been found which exhibits the '$property_name' property with a '$property_value' value" );
		} else {
			msgWarn( "$count nodes found with '$property_name=$property_value' which is not expected" );
			foreach my $it ( @{$candidate_nodes} ){
				print $it->name().EOL;
			}
		}
	} else {
		msgOut( "no node has been found to run the '$opt_service' service" );
	}
	msgOut( "got $count node(s)" );
}

# -------------------------------------------------------------------------------------------------
# returns the property value after all evaluations
# cannot be an array
# if a hash, is expected to have a command (or commands) key

sub property_value {
	my ( $property, $keys, $candidate ) = @_;
	my $ref = ref( $property );
	my $res = undef;
	if( $ref ){
		if( $ref eq 'HASH' ){
			if( $property->{command} || $property->{commands} ){
				my @locals = @{$keys};
				unshift( @locals, 'services', $opt_service );
				my $commands = TTP::commandByOS( \@locals, { jsonable => $candidate });
				if( scalar( @{$commands} )){
					my $result = TTP::commandExec( $commands );
					if( $result->{success} ){
						$res = $result->{stdouts}->[0];
					} else {
						msgErr( $result->{stderrs}->[0] );
					}
				} else {
					msgVerbose( "got an empty commands list" );
				}
			} else {
				msgErr( "cannot handle a non-commands object" );
			}
		} else {
			msgErr( "expect a hash, got $property" );
		}
	} else {
		$res = $property;
	}
	return $res;
}

# -------------------------------------------------------------------------------------------------
# sort the candidate nodes

sub sort_fn {
	my $ret = $a->{rank} <=> $b->{rank};
	$ret = $a->{node}->name() cmp $b->{node}->name() if !$ret;
	return $ret;
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> sub { $ep->runner()->help( @_ ); },
	"colored!"			=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"			=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"			=> sub { $ep->runner()->verbose( @_ ); },
	"service=s"			=> \$opt_service,
	"property=s"		=> \$opt_property )){

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
msgVerbose( "got service='$opt_service'" );
msgVerbose( "got property='$opt_property'" );

# service and property are mandatory
# property must be of the form 'name=value'
if( $opt_service ){
	$service_obj = TTP::Service->new( $ep, { service => $opt_service });
} else {
	msgErr( "'--service' option is mandatory, but is not specified" );
}

if( $opt_property ){
	( $property_name, $property_value ) = split( /=/, $opt_property );
	if( $property_name && $property_value ){
		msgVerbose( "found property_name='$property_name', property_value='$property_value'" );
	} else {
		msgErr( "unable to extract a name and an value from '$opt_property' property argument" );
	}
} else {
	msgErr( "'--property' option is required, but is not specified" );
}

if( !TTP::errs()){
	doSearch();
}

TTP::exit();
