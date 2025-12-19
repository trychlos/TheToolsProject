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
# Check that TTP Perl modules are there, not mispelled, loadable
#
# (I):
# - temp file where results counts are to be written
# - temp file where error messages are to be written

thisdir="$(cd "$(dirname "$0")"; pwd)"
thisbase="$(basename "${thisdir}")"
. "$(dirname "${thisdir}")/functions.sh"

_toolsdir="$(toolsdir)"
color_blue "[${thisbase}] checking that TTP Perl modules are rightly use'd or require'd"

_ftmp="$(mktemp)" || {
    (( _count_total += 1 ))
    echo -n "  [${thisbase}] creating a temporary file "
    color_red "NOT OK"
    echo "[${thisbase}] unable to create a temporary file" >> "${_fic_errors}"
    (( _count_notok += 1 ))
    ender
    exit
}
grep -RP '^\s*(use|require)\s+TTP' "${_toolsdir}" > "${_ftmp}"

while IFS= read -r _line; do
    _line="$(echo "${_line}" | sed -e 's|\s| |g')"
    (( _count_total += 1 ))
    _includer="$(echo "${_line}" | cut -d: -f1)"
    _rest="$(echo "${_line}" | cut -d: -f2- | sed -e 's|^\s*||' -e 's|#.*$||' -e 's|;\s*$||')"
    _used="$(echo "${_rest}" | awk '{ print $2 }')"
    _used_path="$(echo "${_toolsdir}/libexec/perl/$(echo "${_used}" | sed -e 's|::|/|g')".pm)"

    echo -n "  [${thisbase}] required from '${_includer}': ${_used}... "

    if [ -r "${_used_path}" ]; then
        echo "OK"
        (( _count_ok += 1 ))

    else
        color_red "NOT OK"
        echo "${_used_path} not readable" >> "${_fic_errors}"
        (( _count_notok += 1 ))
    fi
done < "${_ftmp}"

rm -f "${_ftmp}"

ender
