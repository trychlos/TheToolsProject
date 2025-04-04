# Copyright (@) 2023-2025 PWI Consulting
#
# OS commands

package TTP::Ports;

use strict;
use utf8;
use warnings;

use Config;
use Data::Dumper;
use File::Spec;
use vars::global qw( $ep );

use TTP::Constants qw( :all );
use TTP::Message qw( :all );

my $Commands = {
	mountPoints => {
		aix => {
			command => 'mount | awk \'{ print $2 }\''
		},
		linux => {
			command => 'mount | awk \'{ print $3 }\''
		}
	}
};

# -------------------------------------------------------------------------------------------------
# List the root mount points
# We are only interested (and only return) with mounts at first level
# (I):
#  -
# (O):
#  - the mount points as an array ref

sub rootMountPoints {
	my $list = [];
	$ENV{TTP_DEBUG} && print STDERR __PACKAGE__."::rootMountPoints() osname '".$Config{osname}."'".EOL;
	my $command = $Commands->{mountPoints}{$Config{osname}}{command};
	$ENV{TTP_DEBUG} && print STDERR __PACKAGE__."::rootMountPoints() command \"".$command."\"".EOL;
	if( $command ){
		my @out = `$command`;
		foreach my $path ( @out ){
			chomp $path;
			my ( $volume, $directories, $file ) = File::Spec->splitpath( $path, true );
			my @dirs = File::Spec->splitdir( $directories );
			# as mount points are always returned as absolute paths, the first element of @dirs is always empty
			# so we must restrict our list to paths which only two elements, second being not empty
			#print STDERR "path=$path directories='$directories' dirs=[ ".join( ', ', @dirs )." ] scalar=".(scalar( @dirs )).EOL;
			if( scalar( @dirs ) == 2 && !$dirs[0] && $dirs[1] ){
				$ENV{TTP_DEBUG} && print STDERR __PACKAGE__."::rootMountPoints() found '".$path."'".EOL;
				push( @{$list}, $path ) ;
			}
		}
	}
	return $list;
}

1;
