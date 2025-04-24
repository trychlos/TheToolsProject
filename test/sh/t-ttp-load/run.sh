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
# Check that TTP Perl modules are each individually loadable
#
# (I):
# - temp file where results counts are to be written
# - temp file where error messages are to be written

thisdir="$(cd "$(dirname "$0")"; pwd)"
thisbase="$(basename "${thisdir}")"
. "$(dirname "${thisdir}")/functions.sh"

_toolsdir="$(toolsdir)"
color_blue "[${thisbase}] checking that TTP Perl modules are each individually loadable"

Node="TTP::IAcceptable TTP::IEnableable TTP::IFindable TTP::IJSONable"
SqlServer="TTP::SqlServer"

for _file in $(find "${_toolsdir}" -type f -name '*.pm' | sort -u); do
    _mod="$(echo "${_file}" | sed -e "s|${_toolsdir}/libexec/perl/||" -e 's|\.pm$||' -e 's|/|::|g')"
    echo -n "  [${thisbase}] use'ing ${_mod}... "

    if [ "${_mod}" = "TTP" -o "$(echo "${Node} ${SqlServer}" | grep -w "${_mod}")" = "" ]; then
        perl -e "use ${_mod};" 1>/dev/null 2>&1
        _rc=$?

        if [ ${_rc} -eq 0 ]; then
            echo "OK"
            (( _count_ok+=1 ))

        else
            color_red "NOT OK"
            #perl -e "use ${_mod};" 2>&1 | tee -a "${_fic_errors}"
            perl -e "use ${_mod};" 1>>"${_fic_errors}" 2>&1
            (( _count_notok+=1 ))
        fi

    elif [ "$(echo "${Node}" | grep -w "${_mod}")" != "" ]; then
        color_cyan "skipped as use'd by Node/Site"
        (( _count_skipped+=1 ))

    elif [ "$(echo "${SqlServer}" | grep -w "${_mod}")" != "" ]; then
        color_cyan "skipped as use'd by (Win32) SqlServer"
        (( _count_skipped+=1 ))
    fi

    (( _count_total+=1 ))
done

ender
