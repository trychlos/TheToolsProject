#!/bin/bash
# @(#) TTP workload execution
#
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
# this .sh is expected to be called with the workload name as unique argument, may have until 8 additional arguments to be passed to underlying commands
# e.g. "/myDir/TheToolsProject/tools/libexec/sh/workload.sh daily.morning -dummy"
# Note 1: this workload.sh adds itself the -nocolored option to every run command. You should take care that the run commands accept (if not honor) this command-line option.
#
# pwi 2025- 5-21 creation
# pwi 2025- 6-16 initialize the TTP environment
# pwi 2025-12-21 provide timestamps with milliseconds (as in CMD.EXE)

# counters
let -i i=0

# this function executes one task of the workload
# (I):
# - the task command-line and its arguments
f_command()
{
	f_logLine "executing $* ($#)"
	typeset _start="$(date '+%Y-%m-%d %H:%M:%S.%N' | cut -c1-23)"
	/bin/bash -c "$*"
	typeset -i _rc=$?
	f_logLine "got RC=${_rc}"
	typeset _end="$(date '+%Y-%m-%d %H:%M:%S.%N' | cut -c1-23)"
	export res_command_$i="$*"
	export res_start_$i="${_start}"
	export res_end_$i="${_end}"
	export res_rc_$i="${_rc}"
	(( i += 1 ))
}

# this function executes all the task of the specified workload
# (I):
# - script name
# - command-line arguments
f_execute()
{
	f_logLine "executing $*"

	# remove the script name from the list of arguments
	shift

	# get the workload name
	typeset _workload="$1"
	shift

	# first argument is now expected to be the workload name
	typeset _tmpfile="$(mktemp)"
	services.pl list -workload "${_workload}" -commands -hidden "$@" -nocolored | grep -vE 'services.pl' > "${_tmpfile}"
	while read _line; do
		f_command ${_line} "$@"
	done < "${_tmpfile}"
	rm -f "${_tmpfile}"

	# and run workload summary
	services.pl workload-summary -workload "${_workload}" -commands res_command -start res_start -end res_end -rc res_rc -count "$i" "$@"
}

# this function computes the log pathname as '/myDir/dailyLogs/250521/TTP/WS12DEV1-daily.morning-20250521-050002.log'
# (I):
# - the workload name
# (O):
# - outputs the result on stdout
f_logFile()
{
	typeset _workload="${1}"
	_logsdir=$(ttp.pl vars -logsCommands -nocolored | grep -vE 'ttp.pl' | awk '{ print $2 }')
	echo "${_logsdir}/${TTP_NODE}-${_workload}-$(date '+%y%m%d-%H%M%S').log"
}

# this function logs a line to the logfile
# (I):
# - the line to be logged
f_logLine()
{
	echo "$(date '+%Y-%m-%d %H:%M:%S') ${ME} $*" >> "${log_file}"
}

###
### MAIN
###

# setup the TTP environment so that we are able to use TTP
ttp_in=workload . $(dirname "${0}")/bootstrap ""

# compute the logfile
log_file="$(f_logFile "${1}")"

# auto-identify
ME="[$(basename "$0") $1]"

# execute the workload
f_execute "$0" "$@" 1>>${log_file} 2>&1
