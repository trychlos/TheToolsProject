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
# whether the two provided URLs address the same host

sub same_host {
    my ( $abs, $host ) = @_;
    my $u = URI->new( $abs );
    return ( $u->scheme =~ /^https?$/ ) && ( lc( $u->host // '' ) eq lc( $host ));
}

# -------------------------------------------------------------------------------------------------
# (I):
# - a state key as computed by state_get_key()
# (O):
# - the extracted frames signature

sub state_key_to_frames_sig {
    my ( $state ) = @_;
    TTP::stackTrace() if !$state;

    my @w = split( /\|/, $state );
    shift @w;   # remove the top href first part
    my $sig = join( '|', @w );

    return $sig;
}

# -------------------------------------------------------------------------------------------------
# (I):
# - a state key as computed by state_get_key()
# (O):
# - the path extracted from the embedded top url

sub state_key_to_path {
    my ( $state ) = @_;
    TTP::stackTrace() if !$state;

    my @w = split( /\|/, $state );
    my $url = substr( $w[0], 4 );   # remove the 'top:' part
    my $uri = URI->new( $url );

    return $uri->path;
}

1;
