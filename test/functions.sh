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
# Shell common functions

color_blue() {
    printf "\033[0;36m${1}\033[0m\n"
}

color_red() {
    printf "\033[0;31m${1}\033[0m\n"
}

ender(){
    color_blue "[${thisbase}] ${_count_total} total counted tests, among them ${_count_notok} failed"
    echo "${_count_total}-${_count_ok}-${_count_notok}" > "${_fic_results}"
}

_fic_results="${1}"
if [ -z "${_fic_results}" ]; then
    echo "[${thisbase}] expected results temporary file as arg 1, not found" 1>&2
    exit 1
fi

_fic_errors="${2}"
if [ -z "${_fic_errors}" ]; then
    echo "[${thisbase}] expected errors temporary file as arg 2, not found" 1>&2
    exit 1
fi

let -i _count_total=0
let -i _count_ok=0
let -i _count_notok=0
