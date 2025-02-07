# @(#) setup the execution node environment
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]default           whether to setup the first available node [${default}]
# @(-) --node=<name>           the node to be set as current [${node}]
#
# @(@) This command is needed because TheToolsProject supports the
# @(@)  'logical machine' paradigm.
# @(@) It has the unique particularity of having to be executed 'in-process'
# @(@)  i.e. with the dot notation: ". ttp.sh switch --node <name>".
# @(@) It should be run from the user profile as:
# @(@)  ". ttp.sh switch --default".
#
# The Tools Project: a Tools System and Paradigm for IT Production
# Copyright (©) 2003-2021 Pierre Wieser (see AUTHORS)
#
# The Tools Project is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version.
#
# The Tools Project is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with The Tools Project; see the file COPYING. If not,
# see <http://www.gnu.org/licenses/>.
#
# Synopsis:
#
#   When the user logs in, the first available execution node is setup.
#   This verb let the user select another node in the same host.
#
# pwi 1998-10-21 new production architecture definition - creation
# pwi 1999- 2-17 set LD_LIBRARY_PATH is GEDAA is set
# pwi 2001-10-17 remove GEDTOOL variable
# pwi 2002- 2-28 tools are moved to physical box
# pwi 2002- 6-24 consider site.ini configuration file
# gma 2004- 4-30 use bspNodeEnum function
# fsl 2005- 3-11 fix bug when determining if a logical exists
# pwi 2006-10-27 the tools become The Tools Project, released under GPL
# pwi 2017- 6-21 publish the release at last
# pwi 2025- 2- 7 merge shell-based and Perl-based flavors to make TheToolsProject available both on shell-based and cmd-based OSes

# set the default values
typeset default_help="no"
typeset default_colored="no"
typeset default_dummy="no"
typeset default_verbose="no"
typeset default_default="no"
typeset default_node=""

# ---------------------------------------------------------------------
# check arguments
#  all optional and positional arguments and their values have been set
#  default values have been applied if any

function verb_arg_check {
	typeset -i _ret=0

	# either 'default' or a target execution node must be specified
	typeset -i _action=0
	[ "${opt_default}" = "yes" ] && let _action+=1
	[ -z "${opt_node}" ] || let _action+=1
	if [ ${_action} -ne 1 ]; then
		msgErr "one of '--default' or '--node=<name>' option must be specified"
		let _ret+=1
	fi

	return ${_ret}
}

# ---------------------------------------------------------------------
# This verb is executed from bootstrap/sh_switch script
#  which expects the node to be printed on stdout

function verb_main {
	#set -x
	typeset -i _ret=0
	typeset _node=""

	if [ "${opt_default}" = "yes" ]; then
		_node="$(bspNodeFindCandidate)"
		if [ -z "${_node}" ]; then
			msgErr "no available execution node on this host"
			return 1
		fi

	else
		_node="$(bspNodeEnum | grep -w "${opt_node}" 2>/dev/null)"
		if [ -z "${_node}" ]; then
			msgErr "'${opt_node}': execution node not found or not available on this host"
			return 1
		fi
	fi

	echo "success: ${_node}"
	TTP_NODE="${_node}"
	msgLog "${ttp_cmdline}"

	return ${_ret}
}
