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
# http.pl compare utilities.

package TTP::HTTP::Compare::Utils;
die __PACKAGE__ . " must be loaded as TTP::HTTP::Compare::Utils\n" unless __PACKAGE__ eq 'TTP::HTTP::Compare::Utils';

use strict;
use utf8;
use warnings;

use Data::Dumper;
use URI;

use TTP;
use vars::global qw( $ep );

use TTP::Constants qw( :all );
use TTP::Message qw( :all );

use constant {
};

my $Const = {
};

# -------------------------------------------------------------------------------------------------
# (I):
# - the page signature on a site
# - the page signature on another site
# (O):
# - true if the signatures are the same, but the URL

sub page_signature_are_same {
    my ( $signature1, $signature2 ) = @_;
    TTP::stackTrace() if !$signature1;
    TTP::stackTrace() if !$signature2;

    my $new1 = TTP::HTTP::Compare::Utils::page_signature_wo_url( $signature1 );
    my $new2 = TTP::HTTP::Compare::Utils::page_signature_wo_url( $signature2 );

    return $new1 eq $new2;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - a page signature as computed by Browser->signature()
# (O):
# - an array which contains the path from each iframes

sub page_signature_to_frames_path {
    my ( $state ) = @_;
    TTP::stackTrace() if !$state;

    my @w = split( /\|/, $state );
    shift @w; # remove the topdoc url
    shift @w; # remove the topdoc signature
    my @paths = ();
    foreach my $p ( @w ){
        my @ww = split( /#/, $p );
        push( @paths, pop( @ww ));
    }

    return \@paths;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - a page signature as computed by Browser->signature()
# (O):
# - the path extracted from the embedded top url

sub page_signature_to_path {
    my ( $state ) = @_;
    TTP::stackTrace() if !$state;

    my @w = split( /\|/, $state );
    my $url = substr( $w[0], 4 );   # remove the 'top:' part
    my $uri = URI->new( $url );

    return $uri->path;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - a page signature
# (O):
# - the same page signature without the URL part
#   i.e. 'top:https://tom59.ref.blingua.fr/fo|doc:132|268|if:0#content-frame#/bo/fo#/bo/person/home|if:1#details-frame##|if:2#ifDbox##'
#   returns: 'top:/fo|doc:132|268|if:0#content-frame#/bo/fo#/bo/person/home|if:1#details-frame##|if:2#ifDbox##'

sub page_signature_wo_url {
    my ( $signature ) = @_;
    TTP::stackTrace() if !$signature;

    # page signature is: 'top:https://tom59.ref.blingua.fr/fo|doc:132|268|if:0#content-frame#/bo/fo#/bo/person/home|if:1#details-frame##|if:2#ifDbox##'
    my @w = split( /\|/, $signature );
    my $first = shift @w;
    my $url = substr( $first, 4 );   # remove the 'top:' part
    my $uri = URI->new( $url );
    my $path = $uri->path_query;

    my $reduced = join( '|', "top:$path", @w );
    return $reduced;
}

# -------------------------------------------------------------------------------------------------
# whether the two provided URLs address the same host

sub same_host {
    my ( $abs, $host ) = @_;
    my $u = URI->new( $abs );
    return ( $u->scheme =~ /^https?$/ ) && ( lc( $u->host // '' ) eq lc( $host ));
}

1;
