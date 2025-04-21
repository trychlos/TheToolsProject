#!/bin/sh -x
# The Tools Project - Tools System and Working Paradigm for IT Production
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
# Check for TTP bootstrapping when site.json or node.json are not present
#
# (I):
# - temp file where results counts are to be written
# - temp file where error messages are to be written

thisdir="$(cd "$(dirname "$0")"; pwd)"
thisbase="$(basename "${thisdir}")"
. "$(dirname "${thisdir}")/functions.sh"

_toolsdir="$(dirname $(dirname "${thisdir}"))/tools"
color_blue "[${thisbase}] checking sh bootstrapping"

# dynamically build a working environment
rm -fr "${thisdir}/work"
mkdir -p "${thisdir}/work/etc/ttp"
mkdir -p "${thisdir}/work/etc/nodes"

export TTP_ROOTS="${_toolsdir}:${thisdir}/work"
export TTP_NODE=$(hostname)
export PATH="/bin:/sbin:/usr/bin:/usr/sbin:$HOME/bin:$HOME/local/bin:${_toolsdir}/bin:${thisdir}/work/bin"
export FPATH="${_toolsdir}/libexec/sh:${thisdir}/work/libexec/sh"
export PERL5LIB="${_toolsdir}/libexec/perl:${thisdir}/work/libexec/perl"

# without site.json, we expect an error message
ttp.pl

ender
