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
# Check for TTP bootstrapping when site.json or node.json are not present
#
# (I):
# - temp file where results counts are to be written
# - temp file where error messages are to be written

thisdir="$(cd "$(dirname "$0")"; pwd)"
thisbase="$(basename "${thisdir}")"
. "$(dirname "${thisdir}")/functions.sh"

_toolsdir="$(dirname $(dirname "${thisdir}"))/tools"
color_blue "[${thisbase}] checking TTP bootstrapping"

# dynamically build a working environment
rm -fr "${thisdir}/work"
mkdir -p "${thisdir}/work/etc/ttp"
mkdir -p "${thisdir}/work/etc/nodes"

export TTP_ROOTS="${_toolsdir}:${thisdir}/work"
export TTP_NODE=$(hostname)
export PATH="/bin:/sbin:/usr/bin:/usr/sbin:$HOME/bin:$HOME/local/bin:${_toolsdir}/bin:${thisdir}/work/bin"
export FPATH="${_toolsdir}/libexec/sh:${thisdir}/work/libexec/sh"
export PERL5LIB="${_toolsdir}/libexec/perl:${thisdir}/work/libexec/perl"

# without site.json, we expect an error message (and only that)
_fout="$(mktemp)"
_ferr="$(mktemp)"
ttp.pl 1>${_fout} 2>${_ferr}
_rc=$?
echo -n "  [${thisbase}] without any site.json, checking stdout is empty... "
(( _count_total+=1 ))
if [ -s "${_fout}" ]; then
    color_red "NOTOK"
    (( _count_notok += 1 ))
    cat "${_fout}" >> ${_fic_errors}
else
    echo "OK"
    (( _count_ok += 1 ))
fi
echo -n "  [${thisbase}] without any site.json, checking for expected error messages... "
(( _count_total+=1 ))
if [ $(grep '(ERR) ' "${_ferr}" | wc -l) -eq 3 ]; then
    echo "OK"
    (( _count_ok += 1 ))
else
    color_red "NOTOK"
    (( _count_notok += 1 ))
    cat "${_ferr}" >> ${_fic_errors}
fi
echo -n "  [${thisbase}] without any site.json, checking return code of the command... "
(( _count_total+=1 ))
if [ ${_rc} -eq 1 ]; then
    echo "OK"
    (( _count_ok += 1 ))
else
    color_red "NOTOK"
    (( _count_notok += 1 ))
    echo "got rc=${_rc}" >> ${_fic_errors}
fi

# create an empty site.json, and expect error message for absent node.json
echo "{}" > "${thisdir}/work/etc/ttp/site.json"
rm -f "${_fout}"
rm -f "${_ferr}"
ttp.pl 1>${_fout} 2>${_ferr}
_rc=$?
echo -n "  [${thisbase}] without any <node>.json, checking stdout is empty... "
(( _count_total+=1 ))
if [ -s "${_fout}" ]; then
    color_red "NOTOK"
    (( _count_notok += 1 ))
    cat "${_fout}" >> ${_fic_errors}
else
    echo "OK"
    (( _count_ok += 1 ))
fi
echo -n "  [${thisbase}] without any <node>.json, checking for expected error messages... "
(( _count_total+=1 ))
if [ $(grep '(ERR) ' "${_ferr}" | wc -l) -eq 2 ]; then
    echo "OK"
    (( _count_ok += 1 ))
else
    color_red "NOTOK"
    (( _count_notok += 1 ))
    cat "${_ferr}" >> ${_fic_errors}
fi
echo -n "  [${thisbase}] without any <node>.json, checking return code of the command... "
(( _count_total+=1 ))
if [ ${_rc} -eq 1 ]; then
    echo "OK"
    (( _count_ok += 1 ))
else
    color_red "NOTOK"
    (( _count_notok += 1 ))
    echo "got rc=${_rc}" >> ${_fic_errors}
fi

# create an empty site.json and node.json, and expect a standard output
echo "{}" > "${thisdir}/work/etc/nodes/$(hostname).json"
rm -f "${_fout}"
rm -f "${_ferr}"
ttp.pl 1>${_fout} 2>${_ferr}
_rc=$?
echo -n "  [${thisbase}] checking for a normal stdout... "
(( _count_total+=1 ))
if [ -s "${_fout}" ]; then
    echo "OK"
    (( _count_ok += 1 ))
else
    color_red "NOTOK"
    (( _count_notok += 1 ))
    cat "${_fout}" >> ${_fic_errors}
fi
echo -n "  [${thisbase}] checking for an empty stderr... "
(( _count_total+=1 ))
if [ -s "${_ferr}" ]; then
    color_red "NOTOK"
    (( _count_notok += 1 ))
    cat "${_fout}" >> ${_fic_errors}
else
    echo "OK"
    (( _count_ok += 1 ))
fi
echo -n "  [${thisbase}] checking return code of the command... "
(( _count_total+=1 ))
if [ ${_rc} -eq 0 ]; then
    echo "OK"
    (( _count_ok += 1 ))
else
    color_red "NOTOK"
    (( _count_notok += 1 ))
    echo "got rc=${_rc}" >> ${_fic_errors}
fi

# create a malformed site.json
echo "azerty" > "${thisdir}/work/etc/ttp/site.json"
rm -f "${_fout}"
rm -f "${_ferr}"
ttp.pl 1>${_fout} 2>${_ferr}
_rc=$?
echo -n "  [${thisbase}] with a malformed site.json, checking expected warning messages... "
(( _count_total+=1 ))
if [ $(grep '(WAR) ' "${_fout}" | wc -l) -eq 2 ]; then
    echo "OK"
    (( _count_ok += 1 ))
else
    color_red "NOTOK"
    (( _count_notok += 1 ))
    cat "${_fout}" >> ${_fic_errors}
fi
echo -n "  [${thisbase}] with a malformed site.json, checking for expected error messages... "
(( _count_total+=1 ))
if [ $(grep '(ERR) ' "${_ferr}" | wc -l) -eq 3 ]; then
    echo "OK"
    (( _count_ok += 1 ))
else
    color_red "NOTOK"
    (( _count_notok += 1 ))
    cat "${_ferr}" >> ${_fic_errors}
fi
echo -n "  [${thisbase}] with a malformed site.json, checking return code of the command... "
(( _count_total+=1 ))
if [ ${_rc} -eq 1 ]; then
    echo "OK"
    (( _count_ok += 1 ))
else
    color_red "NOTOK"
    (( _count_notok += 1 ))
    echo "got rc=${_rc}" >> ${_fic_errors}
fi

# create a wellformed site.json with unexpected keys
echo "{ \"key\": \"value\" }" > "${thisdir}/work/etc/ttp/site.json"
rm -f "${_fout}"
rm -f "${_ferr}"
ttp.pl 1>${_fout} 2>${_ferr}
_rc=$?
echo -n "  [${thisbase}] with unexpected keys, checking stdout is empty... "
(( _count_total+=1 ))
if [ -s "${_fout}" ]; then
    color_red "NOTOK"
    (( _count_notok += 1 ))
    cat "${_fout}" >> ${_fic_errors}
else
    echo "OK"
    (( _count_ok += 1 ))
fi
echo -n "  [${thisbase}] with unexpected keys, checking for expected error messages... "
(( _count_total+=1 ))
if [ $(grep '(ERR) ' "${_ferr}" | wc -l) -eq 3 ]; then
    echo "OK"
    (( _count_ok += 1 ))
else
    color_red "NOTOK"
    (( _count_notok += 1 ))
    cat "${_ferr}" >> ${_fic_errors}
fi
echo -n "  [${thisbase}] with unexpected keys, checking return code of the command... "
(( _count_total+=1 ))
if [ ${_rc} -eq 1 ]; then
    echo "OK"
    (( _count_ok += 1 ))
else
    color_red "NOTOK"
    (( _count_notok += 1 ))
    echo "got rc=${_rc}" >> ${_fic_errors}
fi

# create a malformed node.json
echo "{}" > "${thisdir}/work/etc/ttp/site.json"
echo "azerty" > "${thisdir}/work/etc/nodes/$(hostname).json"
rm -f "${_fout}"
rm -f "${_ferr}"
ttp.pl 1>${_fout} 2>${_ferr}
_rc=$?
echo -n "  [${thisbase}] with a malformed <node>.json, checking expected warning messages... "
(( _count_total+=1 ))
if [ $(grep '(WAR) ' "${_fout}" | wc -l) -eq 2 ]; then
    echo "OK"
    (( _count_ok += 1 ))
else
    color_red "NOTOK"
    (( _count_notok += 1 ))
    cat "${_fout}" >> ${_fic_errors}
fi
echo -n "  [${thisbase}] with a malformed <node>.json, checking for expected error messages... "
(( _count_total+=1 ))
if [ $(grep '(ERR) ' "${_ferr}" | wc -l) -eq 2 ]; then
    echo "OK"
    (( _count_ok += 1 ))
else
    color_red "NOTOK"
    (( _count_notok += 1 ))
    cat "${_ferr}" >> ${_fic_errors}
fi
echo -n "  [${thisbase}] with a malformed <node>.json, checking return code of the command... "
(( _count_total+=1 ))
if [ ${_rc} -eq 1 ]; then
    echo "OK"
    (( _count_ok += 1 ))
else
    color_red "NOTOK"
    (( _count_notok += 1 ))
    echo "got rc=${_rc}" >> ${_fic_errors}
fi

# check that all accepted site.json actually work
# list from TTP::Site::$Const->{finder}{dirs}
rm -f "${thisdir}/work/etc/ttp/site.json"
echo "{}" > "${thisdir}/work/etc/nodes/$(hostname).json"
for _site_json in etc/site.json etc/toops.json etc/ttp.json etc/toops/site.json etc/toops/toops.json etc/toops/ttp.json etc/ttp/toops.json etc/ttp/ttp.json; do
    mkdir -p "${thisdir}/work/$(dirname "${_site_json}")"
    echo "{}" > "${thisdir}/work/${_site_json}"
    rm -f "${_fout}"
    rm -f "${_ferr}"
    echo -n "  [${thisbase}] checking that '${_site_json}' is accepted... "
    (( _count_total+=1 ))
    ttp.pl 1>${_fout} 2>${_ferr}
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
done

rm -f "${_fout}"
rm -f "${_ferr}"
rm -fr "${thisdir}/work"
ender
