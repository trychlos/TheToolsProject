#!/bin/sh
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
#
# Check daemon.pl (standard) vars
#
# (I):
# - temp file where results counts are to be written
# - temp file where error messages are to be written

thisdir="$(cd "$(dirname "$0")"; pwd)"
thisbase="$(basename "${thisdir}")"
. "$(dirname "${thisdir}")/functions.sh"

_toolsdir="$(toolsdir)"
color_blue "[${thisbase}] checking daemon.pl vars"

# error management
f_error(){
    color_red "${_res} - NOT OK"
    echo "$1" >> "${_fic_errors}"
    cat "${_fout}" >> "${_fic_errors}"
    cat "${_ferr}" >> "${_fic_errors}"
    echo -n "site: " >> "${_fic_errors}"
    cat "${_workdir}/etc/ttp/site.json" >> "${_fic_errors}"
    echo -n "node: " >> "${_fic_errors}"
    cat "${_workdir}/etc/nodes/$(hostname).json" >> "${_fic_errors}"
    echo -n "daemon: " >> "${_fic_errors}"
    cat "${_workdir}/etc/daemons/test.json" >> "${_fic_errors}"
    (( _count_notok += 1 ))
}

# dynamically build an empty working environment
_workdir="$(mktemp -d)"
rm -fr "${_workdir}"
mkdir -p "${_workdir}/etc/ttp"
mkdir -p "${_workdir}/etc/nodes"
mkdir -p "${_workdir}/etc/daemons"

export TTP_ROOTS="${_toolsdir}:${_workdir}"
export TTP_NODE=$(hostname)
export PATH="/bin:/sbin:/usr/bin:/usr/sbin:$HOME/bin:$HOME/local/bin:${_toolsdir}/bin:${_workdir}/bin"
export FPATH="${_toolsdir}/libexec/sh:${_workdir}/libexec/sh"
export PERL5LIB="${_toolsdir}/libexec/perl:${_workdir}/libexec/perl"

# test for standard options
echo "{}" > "${_workdir}/etc/ttp/site.json"
echo "{}" > "${_workdir}/etc/nodes/$(hostname).json"
echo "{}" > "${_workdir}/etc/daemons/test.json"

_fout="$(mktemp)"
_ferr="$(mktemp)"

for _keyword in $(daemon.pl  vars -help | grep -- '--' | grep -vE 'help|colored|dummy|verbose|key' | sed -e 's|^\s\+--\[no]||' | awk '{ print $1 }'); do
    (( _count_total += 1 ))
    _command="daemon.pl vars -${_keyword}"
    echo -n "  [${thisbase}] testing '${_command}'... "

    ${_command} 1>"${_fout}" 2>"${_ferr}"
    _rc=$?
    _counterr=$(cat "${_ferr}" | wc -l)
    _countout=$(cat "${_fout}" | grep -v WAR | wc -l)
    _res="$(grep -v WAR "${_fout}" | awk '{ print $2 }')"

    if [ ${_rc} -eq 0 -a ${_counterr} -eq 0 -a ${_countout} -eq 1 -a ! -z ${_res} ]; then
        echo "${_res} - OK"
        (( _count_ok += 1 ))
    else
        f_error "${_command}"
    fi
done

# test for an unknown key
_command="daemon.pl vars -name test -key not,exist"
echo -n "  [${thisbase}] testing an unknown key '${_command}'... "
(( _count_total += 1 ))
${_command} 1>"${_fout}" 2>"${_ferr}"
_rc=$?
_counterr=$(cat "${_ferr}" | wc -l)
_countout=$(cat "${_fout}" | grep -v WAR | wc -l)
_res="$(grep -v WAR "${_fout}" | awk '{ print $2 }')"
if [ ${_rc} -eq 0 -a ${_counterr} -eq 0 -a ${_countout} -eq 1 -a "${_res}" = "(undef)" ]; then
    echo "${_res} - OK"
    (( _count_ok += 1 ))
else
    f_error "${_command}"
fi

# test for an unknown name
_command="daemon.pl vars -name unknown -key anything"
echo -n "  [${thisbase}] testing an unknown name '${_command}'... "
(( _count_total += 1 ))
${_command} 1>"${_fout}" 2>"${_ferr}"
_rc=$?
_counterr=$(cat "${_ferr}" | wc -l)
_countout=$(cat "${_fout}" | grep -v WAR | wc -l)
_res="$(grep -v WAR "${_fout}" | awk '{ print $2 }')"
if [ ${_rc} -eq 1 -a ${_counterr} -eq 2 -a ${_countout} -eq 0 ]; then
    echo "$OK"
    (( _count_ok += 1 ))
else
    f_error "${_command}"
fi

# test for any key in the daemon config
echo "{ \"daemon_key\": \"daemon_value\" }" > "${_workdir}/etc/daemons/test.json"
_command="daemon.pl vars -name test -key daemon_key"
echo -n "  [${thisbase}] testing a daemon key '${_command}'... "
(( _count_total += 1 ))
${_command} 1>"${_fout}" 2>"${_ferr}"
_rc=$?
_counterr=$(cat "${_ferr}" | wc -l)
_countout=$(cat "${_fout}" | grep -v WAR | wc -l)
_res="$(grep -v WAR "${_fout}" | awk '{ print $2 }')"
if [ ${_rc} -eq 0 -a ${_counterr} -eq 0 -a ${_countout} -eq 1 -a "${_res}" = "daemon_value" ]; then
    echo "${_res} - OK"
    (( _count_ok += 1 ))
else
    f_error "${_command}"
fi

# verifying that keys can can be specified as several items
_command="daemon.pl vars -name test -key level1 -key level2 -key level3"
echo "{ \"level1\": { \"level2\": { \"level3\": \"level123_value\" }}}" > "${_workdir}/etc/daemons/test.json"
echo -n "  [${thisbase}] testing several specifications of keys '${_command}'... "
(( _count_total += 1 ))
${_command} 1>"${_fout}" 2>"${_ferr}"
_rc=$?
_counterr=$(cat "${_ferr}" | wc -l)
_countout=$(cat "${_fout}" | grep -v WAR | wc -l)
_res="$(grep -v WAR "${_fout}" | awk '{ print $2 }')"
if [ ${_rc} -eq 0 -a ${_counterr} -eq 0 -a ${_countout} -eq 1 -a "${_res}" = "level123_value" ]; then
    echo "${_res} - OK"
    (( _count_ok += 1 ))
else
    f_error "${_command}"
fi

# verifying that keys can can be specified as a comma-separated list
_command="daemon.pl vars -name test -key level1,level2,level3"
echo -n "  [${thisbase}] testing a comma-separated list of keys '${_command}'... "
(( _count_total += 1 ))
${_command} 1>"${_fout}" 2>"${_ferr}"
_rc=$?
_counterr=$(cat "${_ferr}" | wc -l)
_countout=$(cat "${_fout}" | grep -v WAR | wc -l)
_res="$(grep -v WAR "${_fout}" | awk '{ print $2 }')"
if [ ${_rc} -eq 0 -a ${_counterr} -eq 0 -a ${_countout} -eq 1 -a "${_res}" = "level123_value" ]; then
    echo "${_res} - OK"
    (( _count_ok += 1 ))
else
    f_error "${_command}"
fi

rm -f "${_fout}"
rm -f "${_ferr}"
rm -fr "${_workdir}"
ender
