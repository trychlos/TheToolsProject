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
# Text-based telemetry.

package TTP::Telemetry::Text;
die __PACKAGE__ . " must be loaded as TTP::Telemetry::Text\n" unless __PACKAGE__ eq 'TTP::Telemetry::Text';

use strict;
use utf8;
use warnings;

use Data::Dumper;
use File::Path qw ( make_path );
use File::Spec;
use Path::Tiny;
use Scalar::Util qw( looks_like_number );

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
# Determines the dropDir directory for Text telemetries
# (I):
# - none
# (O):
# - the dropDir directory, making sure it exists

sub dropDir {
	my $dropDir = TTP::Telemetry::var([ 'withText', 'dropDir' ]) || File::Spec->catdir( TTP::tempDir(), 'TTP', 'collector' );
	make_path( $dropDir );
	return $dropDir;
}

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
		my $dropdir = TTP::Telemetry::Text::dropDir();
		if( $dropdir ){
			# get and maybe prefix the name
			# final metric name will "'ttp_'+<provided_prefix>+<metric_name>"
			my $name = $metric->name();
			my $prefix = $opts->{prefix};
			if( $prefix ){
				$name = "$prefix$name";
			}
			$name = "$Const->{prefix}$name" if $Const->{prefix} && $name !~ m/^$Const->{prefix}/;
			my $value = $metric->value();
			if( looks_like_number( $value )){
				# build the published text, updating or adding to the existing publication
				# rationale: the text file is dedicated to a metric, which can have multiple values depending of the defined labels
				my $line = $name;
				my $labels = $metric->labels();
				if( scalar( @{$labels} )){
					$line .= '{'.join( ',', sort @{$labels} ).'}';
				}
				$line = $metric->apply_macros( $line );
				# build the text fname
				my $fname = File::Spec->catfile( $dropdir, "$name.prom" );
				my $content = undef;
				# get previous content
				my $text = path( $fname )->slurp_utf8() // '';
				if( $text ){
					$content = $text;
					if( index( $text, $line ) != -1 ){
						my $searched = $line;
						$searched =~ s/\{/\\{/g;
						$content =~ s/$searched [^\n]*/$line $value/;
					} else {
						$content .= "$line $value\n";
					}
				} else {
					$content = "";
					my $help = $metric->help();
					$content .= "# HELP $name $help\n" if $help;
					my $type = $metric->type();
					$content .= "# TYPE $name $type\n" if $type;
					$content .= "$line $value\n";
				}
				# and try to publish
				my $dummy = $metric->ep()->runner()->dummy();
				if( $dummy ){
					msgDummy( "publishing '$content' to '$fname'" );
				} else {
					path( $fname )->spew_utf8( $content );
				}
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
