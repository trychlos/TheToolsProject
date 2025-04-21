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
# Check that sh bootstrapping works
#
# (I):
# - temp file where results counts are to be written
# - temp file where error messages are to be written

thisdir="$(cd "$(dirname "$0")"; pwd)"
thisbase="$(basename "${thisdir}")"
. "$(dirname "${thisdir}")/functions.sh"

_toolsdir="$(dirname $(dirname "${thisdir}"))/tools"
color_blue "[${thisbase}] checking sh bootstrapping"

# dynamically build a working equivalent of /etc/profile.d/ttp.sh
_workdir="$(mktemp -d)"
rm -fr "${_workdir}"
mkdir "${_workdir}"
cat <<! >"${_workdir}/ttp.sh"
. "${_toolsdir}/libexec/sh/bootstrap" "${_workdir}"
!

# dynamically build a ttp.conf to address this TTP's project and a site configuration tree
cat <<! >"${_workdir}/ttp.conf"
# this is a comment - must be ignored by sh/bootstrap
${_toolsdir}
${_workdir}
!

# must have at least empty site.json and node.json
mkdir -p "${_workdir}/etc/ttp"
echo "{}" > "${_workdir}/etc/ttp/site.json"

mkdir -p "${_workdir}/etc/nodes"
echo "{}" > "${_workdir}/etc/nodes/$(hostname).json"

# after having sourced the dynamically built ttp.sh, we expect to have our environment variables set
unset TTP_ROOTS
unset TTP_NODE
export PATH="/bin:/sbin:/usr/bin:/usr/sbin:$HOME/bin:$HOME/local/bin"
initPath="${PATH}"
unset FPATH
unset PERL5LIB
. "${_workdir}/ttp.sh"
#set | grep -E '^TTP|^PATH|^FPATH|^PERL5'

# must have TTP_ROOTS=this_tools_dir:this_work_dir
echo -n "  [${thisbase}] got TTP_ROOTS=${TTP_ROOTS}... "
(( _count_total+=1 ))
if [ "${TTP_ROOTS}" = "${_toolsdir}:${_workdir}" ]; then
    echo "OK"
    (( _count_ok+=1 ))
else
    color_red "NOT OK"
    (( _count_notok+=1 ))
fi

# must have this TTP_ROOT bin appended to PATH
echo -n "  [${thisbase}] got PATH=${PATH}... "
(( _count_total+=1 ))
if [ "${PATH}" = "${initPath}:${_toolsdir}/bin:${_workdir}/bin" ]; then
    echo "OK"
    (( _count_ok+=1 ))
else
    color_red "NOT OK"
    (( _count_notok+=1 ))
fi

# must have FPATH set to libexec/sh functions
echo -n "  [${thisbase}] got FPATH=${FPATH}... "
(( _count_total+=1 ))
if [ "${FPATH}" = "${_toolsdir}/libexec/sh:${_workdir}/libexec/sh" ]; then
    echo "OK"
    (( _count_ok+=1 ))
else
    color_red "NOT OK"
    (( _count_notok+=1 ))
fi

# must have PERL5LIB set to libexec/perl modules
echo -n "  [${thisbase}] got PERL5LIB=${PERL5LIB}... "
(( _count_total+=1 ))
if [ "${PERL5LIB}" = "${_toolsdir}/libexec/perl:${_workdir}/libexec/perl" ]; then
    echo "OK"
    (( _count_ok+=1 ))
else
    color_red "NOT OK"
    (( _count_notok+=1 ))
fi

# must have a node set
echo -n "  [${thisbase}] got TTP_NODE=${TTP_NODE}... "
(( _count_total+=1 ))
if [ ! -z "${TTP_NODE}" ]; then
    echo "OK"
    (( _count_ok+=1 ))
else
    color_red "NOT OK"
    (( _count_notok+=1 ))
fi

rm -fr "${_workdir}"
ender
