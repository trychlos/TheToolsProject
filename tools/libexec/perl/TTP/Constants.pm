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

package TTP::Constants;
die __PACKAGE__ . " must be loaded as TTP::Constants\n" unless __PACKAGE__ eq 'TTP::Constants';

use strict;
use utf8;
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
