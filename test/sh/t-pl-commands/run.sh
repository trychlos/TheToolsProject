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
# Check for all commands and verbs standard options
#
# (I):
# - temp file where results counts are to be written
# - temp file where error messages are to be written

thisdir="$(cd "$(dirname "$0")"; pwd)"
thisbase="$(basename "${thisdir}")"
. "$(dirname "${thisdir}")/functions.sh"

_toolsdir="$(toolsdir)"
color_blue "[${thisbase}] checking TTP standard commands and verbs options"

# dynamically build a working environment
_workdir="$(mktemp -d)"
rm -fr "${_workdir}"
mkdir -p "${_workdir}/etc/ttp"
echo "{}" > "${_workdir}/etc/ttp/site.json"
mkdir -p "${_workdir}/etc/nodes"
echo "{}" > "${_workdir}/etc/nodes/$(hostname).json"

export TTP_ROOTS="${_toolsdir}:${_workdir}"
export TTP_NODE=$(hostname)
export PATH="/bin:/sbin:/usr/bin:/usr/sbin:$HOME/bin:$HOME/local/bin:${_toolsdir}/bin:${_workdir}/bin"
export FPATH="${_toolsdir}/libexec/sh:${_workdir}/libexec/sh"
export PERL5LIB="${_toolsdir}/libexec/perl:${_workdir}/libexec/perl"

_fout="$(mktemp)"
_ferr="$(mktemp)"

# we are going to explore all commands, and all verbs of each command
echo -n "  [${thisbase}] getting the list of commands... "
(( _count_total+=1 ))
ttp.pl list -commands 1>"${_fout}" 2>"${_ferr}"
_rc=$?
if [ ${_rc} -eq 0 -a -s "${_fout}" -a ! -s "${_ferr}" ]; then
    echo "OK"
    (( _count_ok += 1 ))
else
    color_red "NOTOK"
    (( _count_notok += 1 ))
    cat "${_fout}" >> ${_fic_errors}
    cat "${_ferr}" >> ${_fic_errors}
fi

echo -n "  [${thisbase}] verifying the count of commands... "
(( _count_total+=1 ))
let -i _count_lines=$(grep -v '^\[ttp.pl list] ' "${_fout}" | wc -l)
let -i _count_verb=$(grep 'found command' "${_fout}" | awk '{ print $3 }')
if [ ${_count_lines} -eq ${_count_verb} ]; then
    echo "found ${_count_lines} - OK"
    (( _count_ok += 1 ))
else
    color_red "NOTOK"
    (( _count_notok += 1 ))
    cat "${_fout}" >> ${_fic_errors}
    echo "count_lines=${_count_lines}" >> ${_fic_errors}
    echo "count_verb=${_count_verb}" >> ${_fic_errors}
fi

# iterate on every found command
(( _count_total+=1 ))
for _command in $(grep -v '^\[ttp.pl list] ' "${_fout}" | sed -e 's|^\s*||' -e 's|:.*$||'); do

    echo -n "  [${thisbase}] getting the list of '${_command}' available verbs... "
    (( _count_total+=1 ))
    ${_command} 1>"${_fout}" 2>"${_ferr}"
    _rc=$?
    if [ ${_rc} -eq 0 -a -s "${_fout}" -a ! -s "${_ferr}" ]; then
        echo "OK"
        (( _count_ok += 1 ))

        echo -n "  [${thisbase}] verifying the count of '${_command}' verbs... "
        (( _count_total+=1 ))
        let -i _count_lines=$(grep -v "${_command}" "${_fout}" | wc -l)
        let -i _count_verb=$(grep 'found verb' "${_fout}" | awk '{ print $2 }')
        if [ ${_count_lines} -eq ${_count_verb} ]; then
            echo "found ${_count_lines} - OK"
            (( _count_ok += 1 ))
        else
            color_red "NOTOK"
            (( _count_notok += 1 ))
            cat "${_fout}" >> ${_fic_errors}
            echo "count_lines=${_count_lines}" >> ${_fic_errors}
            echo "count_verb=${_count_verb}" >> ${_fic_errors}
        fi

        # and ask for help for each verb
        _fverb="$(mktemp)"
        for _verb in $(grep -v "${_command}" "${_fout}" | sed -e 's|^s*||' -e 's|:.*$||'); do

            echo -n "  [${thisbase}] checking that '${_command} ${_verb}' displays standard help... "
            (( _count_total+=1 ))
            ${_command} ${_verb} 1>"${_fverb}" 2>"${_ferr}"
            _rc=$?
            if [ ${_rc} -eq 0 -a -s "${_fverb}" -a ! -s "${_ferr}" ]; then
                echo "OK"
                (( _count_ok += 1 ))

            else
                color_red "NOTOK"
                (( _count_notok += 1 ))
                cat "${_fverb}" >> ${_fic_errors}
                cat "${_ferr}" >> ${_fic_errors}
            fi

            echo -n "  [${thisbase}] checking that '${_command} ${_verb}' accepts standard options... "
            (( _count_total+=1 ))
            ${_command} ${_verb} -help -dummy -verbose -colored 1>"${_fverb}" 2>"${_ferr}"
            _rc=$?
            if [ ${_rc} -eq 0 -a -s "${_fverb}" -a ! -s "${_ferr}" ]; then
                echo "OK"
                (( _count_ok += 1 ))

            else
                color_red "NOTOK"
                (( _count_notok += 1 ))
                cat "${_fverb}" >> ${_fic_errors}
                cat "${_ferr}" >> ${_fic_errors}
            fi

        done
        rm -f "${_fverb}"

    else
        color_red "NOTOK"
        (( _count_notok += 1 ))
        cat "${_fout}" >> ${_fic_errors}
        cat "${_ferr}" >> ${_fic_errors}
    fi
done

rm -f "${_fout}"
rm -f "${_ferr}"
rm -fr "${_workdir}"
ender
