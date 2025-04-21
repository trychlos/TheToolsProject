#!/bin/sh +x
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
# Just run:
#     $ test/run.sh
# or:
#     C:\> test\run.cmd
#
# Accepted command-line arguments:
# -noerrs: do not display the errors
#
# Tests are executed with the current git branch.
#
# have to test:
# - for Perl standard modules
# - for Perl TTP modules
# sh bootstrapping
# cmd bootstrapping
# we do not have a site.json
# we do not have a node.json
# $ ttp.pl: gives a list exit=0
# $ ttp.pl list: gives an help, exit=0
# $ ttp.pl list -commands, gives a list, exit=0
# $ ttp.pl push -noverb
# $ ttp.pl vars -logsRoot
# $ ttp.pl vars -key logs,rootDir
#
#   my %seen;
#   print Dumper( %INC );
#   for my $key ( sort keys %INC ){
#   	print "$key => $INC{$key}\n";
#       my $lc = lc $key;
#       if ($seen{$lc} && $seen{$lc} ne $key) {
#           warn "⚠️ Possible duplicate module load (case difference): $seen{$lc} vs $key\n";
#       }
#       $seen{$lc} = $key;
#   }
#
# tests for daemons

thisdir="$( cd "$(dirname "$0")"; pwd)"
let -i _count_total=0
let -i _count_ok=0
let -i _count_notok=0

_fcounts="$(mktemp)"
_ferrors="$(mktemp)"

    #t-perl \
    #t-ksh \
    #t-perl-std \
    #t-ttp-case \
    #t-ttp-load \
for _d in \
    t-ttp-load \
        ; do
    (( _count_total += 1 ))
    if [ -x "${thisdir}/${_d}/run.sh" ]; then
        "${thisdir}/${_d}/run.sh" "${_fcounts}" "${_ferrors}"
        _results="$(cat "${_fcounts}")"
        _total="$(echo "${_results}" | cut -d- -f1)"
        (( _count_total += ${_total} ))
        _ok="$(echo "${_results}" | cut -d- -f2)"
        (( _count_ok += ${_ok} ))
        _notok="$(echo "${_results}" | cut -d- -f3)"
        (( _count_notok += ${_notok} ))
    else
        echo "${_d}: no run.sh available, passing"
    fi
done

echo "[run.sh] counted ${_count_total} total tests, among them ${_count_notok} failed"

if [ ${_count_notok} -gt 0 ]; then
    echo "Error summary:"
    cat "${_ferrors}" | while read _l; do echo "  ${_l}"; done
fi

rm -f "${_fcounts}" "${_ferrors}"
