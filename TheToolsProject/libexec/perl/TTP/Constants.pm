# Copyright (@) 2023-2024 PWI Consulting

package TTP::Constants;

use utf8;
use strict;
use warnings;

use Sub::Exporter;

Sub::Exporter::setup_exporter({
	exports => [ qw(
		true
		false
		EOL
	)]
});

use constant {
	true => 1,
	false => 0,
	EOL => "\n",
};

1;
