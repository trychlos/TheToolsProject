#!/bin/sh
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
# Check for perl, displaying the Perl version
#
# (I):
# - temp file where results counts are to be written
# - temp file where error messages are to be written

thisdir="$(cd "$(dirname "$0")"; pwd)"
thisbase="$(basename "${thisdir}")"
. "$(dirname "${thisdir}")/functions.sh"

color_blue "[${thisbase}] checking for perl binary"

echo -n "  [${thisbase}] checking that perl is addressable... "
perl_path=$(which perl 2>/dev/null)
(( _count_total += 1 ))

if [ -z "${perl_path}" ]; then
    perl_err=$(which perl 2>&1)
    color_red "${perl_err} - NOT OK"
    echo "${perl_err}" >> "${_fic_errors}"
    (( _count_notok += 1 ))

else
    echo "perl="${perl_path}" - OK"
    (( _count_ok += 1 ))

    echo -n "  [${thisbase}] checking for Perl version... "
    perl_version="$(perl -v 2>/dev/null | grep -ve '^$' | head -1 | cut -d' ' -f9 | sed -e 's|[\(\)]||g' 2>/dev/null)"
    (( _count_total += 1 ))

    if [ -z "${perl_version}" ]; then
        perl_err="$(perl -v 2>&1)"
        color_red "${perl_err} - NOT OK"
        echo "${perl_err}" >> "${_fic_errors}"
        (( _count_notok += 1 ))

    else
        echo "${perl_version} - OK"
        (( _count_ok += 1 ))
    fi
fi

ender
