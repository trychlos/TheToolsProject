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
# Text-based telemetry.

package TTP::Telemetry::Text;
die __PACKAGE__ . " must be loaded as TTP::Telemetry::Text\n" unless __PACKAGE__ eq 'TTP::Telemetry::Text';

use strict;
use utf8;
use warnings;

use Data::Dumper;

use TTP::Constants qw( :all );
use TTP::Message qw( :all );
use TTP::Telemetry;

use constant {
	# the publication error codes
	TEXT_DISABLED_BY_CONFIGURATION => 1,
	VALUE_UNSUITED => 2,
	TEXT_NODROPDIR => 3
};

my $Const = {
	# by convention all Prometheus (so http-based and text-based metrics) have this same prefix
	prefix => 'ttp_',
	# the error codes as labels
	errorLabels => [
		'OK',
		'TEXT_DISABLED_BY_CONFIGURATION',
		'VALUE_UNSUITED',
		'TEXT_NODROPDIR'
	]
};

# -------------------------------------------------------------------------------------------------
# Determines if Text-based telemetry is a site default, defaulting to false
# (I):
# - none
# (O):
# - whether Text-based telemetry is a default of the site

sub getDefault {
	my ( $class ) = @_;

	my $default = TTP::Telemetry::var([ 'withText', 'default' ]);
	$default = false if !defined $default;

	return $default;
}

# -------------------------------------------------------------------------------------------------
# Whether Text-based telemetry is allowed in the site, defaulting to true
# (I):
# - none
# (O):
# - whether Text-based telemetry is allowed in the site

sub isEnabled {
	my ( $class ) = @_;

	my $enabled = TTP::Telemetry::var([ 'withText', 'enabled' ]);
	$enabled = true if !defined $enabled;

	return $enabled;
}

# -------------------------------------------------------------------------------------------------
# publish a metric to Text-based PushGateway
# Publishing to Prometheus:
# - the value must be numeric
# - the name is prefixed by 'ttp_'
# (I):
# - the metric
# - an optional options hash with following keys:
#   > prefix: a prefix to the metric name, defaulting to none
# (O):
# - returns either zero if the metric has been actually and successfully published, or the reason code

sub publish {
	my ( $metric, $opts ) = @_;
	$opts //= {};
	my $res = 0;

	if( isEnabled()){
		my $dropdir = TTP::Telemetry::var([ 'withText', 'dropDir' ]);
		if( $dropdir ){
			# get and maybe prefix the name
			# final metric name will "'ttp_'+<provided_prefix>+<metric_name>"
			my $name = $metric->name();
			my $prefix = $opts->{prefix};
			if( $prefix ){
				$name = "$prefix$name";
			}
			# pwi 2024- 5- 1 do not remember the reason why ?
			#$name =~ s/\./_/g;
			$name = "$Const->{prefix}$name" if $Const->{prefix} && $name !~ m/^$Const->{prefix}/;
			my $value = $metric->value();
			if( looks_like_number( $value )){
				# do we run in dummy mode ?
				my $dummy = $metric->ep()->runner()->dummy();
				# and so...??
			} else {
				$res = VALUE_UNSUITED;
			}
		} else {
			$res = TEXT_NODROPDIR;
		}
	} else {
		$res = TEXT_DISABLED_BY_CONFIGURATION;
	}

	msgVerbose( __PACKAGE__."::publish() returning res='$res' ($Const->{errorLabels}[$res])" );
	return $res;
}

1;

__END__
