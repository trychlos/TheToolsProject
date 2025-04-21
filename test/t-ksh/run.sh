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
# Check for ksh, displaying its version
#
# (I):
# - temp file where results counts are to be written
# - temp file where error messages are to be written

thisdir="$(cd "$(dirname "$0")"; pwd)"
thisbase="$(basename "${thisdir}")"
. "$(dirname "${thisdir}")/functions.sh"

echo -n "[${thisbase}] checking that ksh is addressable... "
ksh_path=$(which ksh 2>/dev/null)
(( _count_total += 1 ))

if [ -z "${ksh_path}" ]; then
    ksh_err=$(which ksh 2>&1)
    color_red "${ksh_err} - NOT OK"
    echo "${ksh_err}" >> "${_fic_errors}"
    (( _count_notok += 1 ))

else
    echo "ksh="${ksh_path}" - OK"
    (( _count_ok += 1 ))

    echo -n "[${thisbase}] checking for ksh version... "
    ksh_version="$(ksh --version 2>&1 | awk '{ for( i=3; i<=NF; ++i ) printf( "%s ", $i ); printf( "\n" )}' | sed -e 's|\([^\)]\)\+)\s*||')"
    (( _count_total += 1 ))

    if [ -z "${ksh_version}" ]; then
        color_red "unable to get ksh version - NOT OK"
        echo "unable to get ksh version" >> "${_fic_errors}"
        (( _count_notok += 1 ))

    else
        echo "${ksh_version} - OK"
        (( _count_ok += 1 ))
    fi
fi

ender
