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
# Check that all use'd standard Perl modules are installed#
# (I):
# - temp file where results counts are to be written
# - temp file where error messages are to be written


thisdir="$(cd "$(dirname "$0")"; pwd)"
thisbase="$(basename "${thisdir}")"
. "$(dirname "${thisdir}")/functions.sh"

# some modules depend of the running OS
MSWin32="Win32::Console::ANSI Win32::OLE Win32::SqlServer"

_toolsdir="$(dirname $(dirname "${thisdir}"))/tools"
color_blue "[${thisbase}] checking for standard Perl modules in '${_toolsdir}'"

for _mod in $(find "${_toolsdir}" -type f -name '*.p?' -exec grep -E '^use |^\s*require ' {} \; | awk '{ print $2 }' | grep -vE 'TTP|base|constant|if|open|overload|strict|utf8|warnings' | sed -e 's|;\s*$||' | sort -u); do
    echo -n "  [${thisbase}] testing ${_mod}... "
    perl -e "use ${_mod};" 1>/dev/null 2>&1
    _rc=$?
    (( _count_total+=1 ))

    if [ ${_rc} -eq 0 ]; then
        echo "OK"
        (( _count_ok+=1 ))

    else
        color_red "NOT OK"
        perl -e "use ${_mod};" 1>>"${_fic_errors}" 2>&1
        (( _count_notok+=1 ))
    fi
done

ender
