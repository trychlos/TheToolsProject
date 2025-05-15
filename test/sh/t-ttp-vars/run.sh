#!/bin/sh
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
# Check ttp.pl (standard) vars
#
# (I):
# - temp file where results counts are to be written
# - temp file where error messages are to be written

thisdir="$(cd "$(dirname "$0")"; pwd)"
thisbase="$(basename "${thisdir}")"
. "$(dirname "${thisdir}")/functions.sh"

_toolsdir="$(toolsdir)"
color_blue "[${thisbase}] checking ttp.pl vars"

_fout="$(mktemp)"
_ferr="$(mktemp)"

for _keyword in $(ttp.pl  vars -help | grep -- '--' | grep -vE 'help|colored|dummy|verbose|key' | sed -e 's|^\s\+--\[no]||' | awk '{ print $1 }'); do
    (( _count_total += 1 ))
    echo -n "  [${thisbase}] testing 'ttp.pl vars -${_keyword}'... "

    ttp.pl vars -${_keyword} 1>"${_fout}" 2>"${_ferr}"
    _rc=$?
    _counterr=$(cat "${_ferr}" | wc -l)
    _countout=$(cat "${_fout}" | grep -v WAR | wc -l)
    _res="$(grep -v WAR "${_fout}" | awk '{ print $2 }')"

    if [ ${_rc} -eq 0 -a ${_counterr} -eq 0 -a ${_countout} -eq 1 -a ! -z ${_res} ]; then
        echo "${_res} OK"
        (( _count_ok += 1 ))
    else
        color_red "NOT OK"
        echo "ttp.pl vars -${_keyword}" >> "${_fic_errors}"
        cat "${_ferr}" >> "${_fic_errors}"
        (( _count_notok += 1 ))
    fi
done

rm -f "${_fout}"
rm -f "${_ferr}"
ender
