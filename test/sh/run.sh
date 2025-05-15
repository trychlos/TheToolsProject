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
# Just run:
#     $ test/sh/run.sh [testA [testB] ...]
# or:
#     C:\> test\cmd\run.cmd [testA [testB] ...]
#
# Tests are executed with the current git branch.

thisdir="$(cd "$(dirname "$0")"; pwd)"
let -i _count_total=0
let -i _count_ok=0
let -i _count_notok=0
let -i _count_skipped=0

_fcounts="$(mktemp)"
_ferrors="$(mktemp)"

if [ $# == 0 ]; then
    dirs="t-perl t-ksh t-perl-std t-ttp-case t-ttp-load t-sh-bootstrap t-ttp-bootstrap t-pl-commands t-ttp-vars t-daemon-vars t-dbms-vars"
else
    dirs=$*
fi

for _d in ${dirs}; do
    if [ -x "${thisdir}/${_d}/run.sh" ]; then
        "${thisdir}/${_d}/run.sh" "${_fcounts}" "${_ferrors}"
        _results="$(cat "${_fcounts}")"
        _total="$(echo "${_results}" | cut -d- -f1)"
        (( _count_total += ${_total} ))
        _ok="$(echo "${_results}" | cut -d- -f2)"
        (( _count_ok += ${_ok} ))
        _notok="$(echo "${_results}" | cut -d- -f3)"
        (( _count_notok += ${_notok} ))
        _skipped="$(echo "${_results}" | cut -d- -f4)"
        (( _count_skipped += ${_skipped} ))
    else
        (( _count_total += 1 ))
        (( _count_skipped += 1 ))
        echo "[run.sh] ${_d}: no run.sh available, passing"
    fi
done

echo "[run.sh] counted ${_count_total} total tests, among them ${_count_skipped} skipped, and ${_count_notok} failed"

if [ ${_count_notok} -gt 0 ]; then
    echo "Error summary:"
    cat "${_ferrors}" | while read _l; do echo "  ${_l}"; done
fi

rm -f "${_fcounts}" "${_ferrors}"
