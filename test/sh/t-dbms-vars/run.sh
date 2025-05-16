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
# Check dbms.pl (standard) vars
#
# (I):
# - temp file where results counts are to be written
# - temp file where error messages are to be written

thisdir="$(cd "$(dirname "$0")"; pwd)"
thisbase="$(basename "${thisdir}")"
. "$(dirname "${thisdir}")/functions.sh"

_toolsdir="$(toolsdir)"
color_blue "[${thisbase}] checking dbms.pl vars"

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
    echo -n "service: " >> "${_fic_errors}"
    cat "${_workdir}/etc/services/test.json" >> "${_fic_errors}"
    (( _count_notok += 1 ))
}

# dynamically build an empty working environment
_workdir="$(mktemp -d)"
rm -fr "${_workdir}"
mkdir -p "${_workdir}/etc/ttp"
mkdir -p "${_workdir}/etc/nodes"
mkdir -p "${_workdir}/etc/services"

export TTP_ROOTS="${_toolsdir}:${_workdir}"
export TTP_NODE=$(hostname)
export PATH="/bin:/sbin:/usr/bin:/usr/sbin:$HOME/bin:$HOME/local/bin:${_toolsdir}/bin:${_workdir}/bin"
export FPATH="${_toolsdir}/libexec/sh:${_workdir}/libexec/sh"
export PERL5LIB="${_toolsdir}/libexec/perl:${_workdir}/libexec/perl"

# test for standard options
echo "{}" > "${_workdir}/etc/ttp/site.json"
echo "{ \"services\": { \"test\": {}}}" > "${_workdir}/etc/nodes/$(hostname).json"

_fout="$(mktemp)"
_ferr="$(mktemp)"

for _keyword in $(dbms.pl  vars -help | grep -- '--' | grep -vE 'help|colored|dummy|verbose|key' | sed -e 's|^\s\+--\[no]||' | awk '{ print $1 }'); do
    (( _count_total += 1 ))
    _command="dbms.pl vars -${_keyword}"
    echo -n "  [${thisbase}] testing '${_command}'... "

    ${_command} 1>"${_fout}" 2>"${_ferr}"
    _rc=$?
    _counterr=$(cat "${_ferr}" | wc -l)
    _countout=$(cat "${_fout}" | grep -v WAR | wc -l)
    _res="$(grep -v WAR "${_fout}" | awk '{ print $2 }')"

    if [ ${_rc} -eq 0 -a ${_counterr} -eq 0 -a ${_countout} -eq 1 -a ! -z ${_res} ]; then
        echo "${_res} OK"
        (( _count_ok += 1 ))
    else
        f_error "${_command}"
    fi
done

# test for an unknown key
_command="dbms.pl vars -key not,exist"
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

# test for a site-level key
echo "{ \"TTP\": { \"DBMS\": { \"dbms_key\": \"dbms_site_value\" }}}" > "${_workdir}/etc/ttp/site.json"
_command="dbms.pl vars -key dbms_key"
echo -n "  [${thisbase}] testing a site-level key '${_command}'... "
(( _count_total += 1 ))
${_command} 1>"${_fout}" 2>"${_ferr}"
_rc=$?
_counterr=$(cat "${_ferr}" | wc -l)
_countout=$(cat "${_fout}" | grep -v WAR | wc -l)
_res="$(grep -v WAR "${_fout}" | awk '{ print $2 }')"
if [ ${_rc} -eq 0 -a ${_counterr} -eq 0 -a ${_countout} -eq 1 -a "${_res}" = "dbms_site_value" ]; then
    echo "${_res} - OK"
    (( _count_ok += 1 ))
else
    f_error "${_command} (site-level)"
fi

# test for the site key, overriden at the service level
_command="dbms.pl vars -service test -key dbms_key"
echo "{ \"DBMS\": { \"dbms_key\": \"service_value\" }}" > "${_workdir}/etc/services/test.json"
echo -n "  [${thisbase}] testing a service-level key '${_command}'... "
(( _count_total += 1 ))
${_command} 1>"${_fout}" 2>"${_ferr}"
_rc=$?
_counterr=$(cat "${_ferr}" | wc -l)
_countout=$(cat "${_fout}" | grep -v WAR | wc -l)
_res="$(grep -v WAR "${_fout}" | awk '{ print $2 }')"
if [ ${_rc} -eq 0 -a ${_counterr} -eq 0 -a ${_countout} -eq 1 -a "${_res}" = "service_value" ]; then
    echo "${_res} - OK"
    (( _count_ok += 1 ))
else
    f_error "${_command} (service-level)"
fi

# test for the same previous key, overriden at the node level
_command="dbms.pl vars -key dbms_key"
echo "{ \"DBMS\": { \"dbms_key\": \"dbms_node_value\" }, \"services\": { \"test\": { \"DBMS\": { \"dbms_key\": \"dbms_node_service_value\" }}}}" > "${_workdir}/etc/nodes/$(hostname).json"
echo -n "  [${thisbase}] testing a node-overriden key '${_command}'... "
(( _count_total += 1 ))
${_command} 1>"${_fout}" 2>"${_ferr}"
_rc=$?
_counterr=$(cat "${_ferr}" | wc -l)
_countout=$(cat "${_fout}" | grep -v WAR | wc -l)
_res="$(grep -v WAR "${_fout}" | awk '{ print $2 }')"
if [ ${_rc} -eq 0 -a ${_counterr} -eq 0 -a ${_countout} -eq 1 -a "${_res}" = "dbms_node_value" ]; then
    echo "${_res} - OK"
    (( _count_ok += 1 ))
else
    f_error "${_command} (node-overriden)"
fi

# test for the same previous key, overriden at the node level for this service
_command="dbms.pl vars -service test -key dbms_key"
echo -n "  [${thisbase}] testing a node-service-overriden key '${_command}'... "
(( _count_total += 1 ))
${_command} 1>"${_fout}" 2>"${_ferr}"
_rc=$?
_counterr=$(cat "${_ferr}" | wc -l)
_countout=$(cat "${_fout}" | grep -v WAR | wc -l)
_res="$(grep -v WAR "${_fout}" | awk '{ print $2 }')"
if [ ${_rc} -eq 0 -a ${_counterr} -eq 0 -a ${_countout} -eq 1 -a "${_res}" = "dbms_node_service_value" ]; then
    echo "${_res} - OK"
    (( _count_ok += 1 ))
else
    f_error "${_command} (node-overriden for this service)"
fi

# verifying that keys can can be specified as several items
_command="dbms.pl vars -key dbms_key1 -key dbms_key2 -key dbms_key3"
echo "{ \"TTP\": { \"DBMS\": { \"dbms_key1\": { \"dbms_key2\": { \"dbms_key3\": \"dbms123_value\" }}}}}" > "${_workdir}/etc/ttp/site.json"
echo "{}" > "${_workdir}/etc/nodes/$(hostname).json"
echo "{}" > "${_workdir}/etc/services/test.json"
echo -n "  [${thisbase}] testing several specifications of keys '${_command}'... "
(( _count_total += 1 ))
${_command} 1>"${_fout}" 2>"${_ferr}"
_rc=$?
_counterr=$(cat "${_ferr}" | wc -l)
_countout=$(cat "${_fout}" | grep -v WAR | wc -l)
_res="$(grep -v WAR "${_fout}" | awk '{ print $2 }')"
if [ ${_rc} -eq 0 -a ${_counterr} -eq 0 -a ${_countout} -eq 1 -a "${_res}" = "dbms123_value" ]; then
    echo "${_res} - OK"
    (( _count_ok += 1 ))
else
    f_error "${_command}"
fi

# verifying that keys can can be specified as a comma-separated list
_command="dbms.pl vars -key dbms_key1,dbms_key2,dbms_key3"
echo -n "  [${thisbase}] testing a comma-separated list of keys '${_command}'... "
(( _count_total += 1 ))
${_command} 1>"${_fout}" 2>"${_ferr}"
_rc=$?
_counterr=$(cat "${_ferr}" | wc -l)
_countout=$(cat "${_fout}" | grep -v WAR | wc -l)
_res="$(grep -v WAR "${_fout}" | awk '{ print $2 }')"
if [ ${_rc} -eq 0 -a ${_counterr} -eq 0 -a ${_countout} -eq 1 -a "${_res}" = "dbms123_value" ]; then
    echo "${_res} - OK"
    (( _count_ok += 1 ))
else
    f_error "${_command}"
fi

rm -f "${_fout}"
rm -f "${_ferr}"
rm -fr "${_workdir}"
ender
