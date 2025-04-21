#!/bin/ksh
# @(#) The Tools Project (TTP) management
#
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
# pwi 2012- 7-12 creation
# pwi 2017- 6-21 publish the release at last
# pwi 2021- 5-25 get rid of TTP_SHDIR variable
# pwi 2021-12-16 consider running from a crontab where shell is fully addressed

# In order to be able to honor the 'logical machine' paradigm (which
# let the administrator have several execution nodes in the same machine),
# we have to manage the in-process command ". ttp.sh switch --node <name>".
# The run of this command depends of the FPATH variable having been
# previously set.
#
# When run in-process, the '$0' first argument is not the 'ttp.sh'
# command, but the running shell which is something like: '[-]<shell>'.
# Whether there is a leading dash ('-') or not indicates the presence
# of a login shell.
#
# If first character is '-',
#   - then we are in a login shell, which makes sure the command is
#     actually ". ttp.sh ..."
# else
#   - we are in a non-login shell, which does not say anything about
#     whether we have run ". ttp.sh .." or "ttp.sh ..."
#
# If running shell is Korn,
#   - this does not say anything about whether we have run
#     ". ttp.sh .." or "ttp.sh ..."
#   - FPATH will be honored, we so can call ttpf_main() as usual
# else
#   - we are in the user shell, which makes sure the command is actually
#     ". ttp.sh ..."
#   - we have to pre-load the function in a sub-environment.
#
# As a particular case, the ${0} argument is the full path of the current shell
# when the environment is initialized from a crontab.

#set -x
#echo "ttp.sh: 0=$0 #=$# *=$*" >&2

# The only allowed in-process invocation is the ". ttp.sh switch" command.
# Other in-process invocations may fall in error if FPATH is not honored
# (ksh being the only known shell to be able to autoload its functions,
#  typical sh-like shells, e.g. bash, would else fail)

if [ "${0:0:1}" == "-" -o "${0}" == "${SHELL}" -o "${0##*/}" == "${SHELL##*/}" -o "${0#${0%??????????????????????????}}" == "test/t-sh-bootstrap/run.sh" ]; then
	[ "${1}" == "switch" ] && {
		. $(echo "${FPATH}" | tr ':' '\n' | while read _dir; do [[ -f "${_dir}/switch" ]] && echo "${_dir}" && break; done)/switch "$(which ttp.sh 2>/dev/null)" "${@}";
		return $?;
	}
fi

ttpf_main "${0}" "${@}"
