#!/bin/sh
# Release TheToolsProject from a maintainer workstation.
#
# The script prepares the release metadata on vnext, fast-forwards master,
# creates and pushes an annotated tag, and creates the GitHub release.  The
# release event starts .github/workflows/publish-release.yml, which attaches
# the tar.gz and zip archives.  Deployment to nodes/clients is intentionally
# not part of this script.
#
# Original release checklist:
#
# preparation:
# - setup .VERSION version number
# - setup ChangeLog.md version number
# - setup ChangeLog.md release date
# - setup TODO.md ChangeLog.md README.md last update date
#
# gh release create
# the action workflow will automatically create a tarball and a zip
#
# Deferred for now:
# - ask our Ansible role to distribute on all our nodes
# - ask other clients to update
#
# Git sequence described by the initial draft:
# - make sure we do not have any pending changes (untracked files are accepted)
# - make sure we are on vnext, then integrate vnext into master
# - update from origin before tagging
# - git tag -am "Releasing v4.1.0" 4.1.0
# - push master and tags
#
# GitHub release values described by the initial draft:
# - name: v4.1.0
# - from tag: 4.1.0
# - notes: ChangeLog for this version

# set -e: Exit on Error
# set -u: Treat Unset Variables as Errors
set -eu

# this script
me="${0}"

# command-line options
opt_dummy=false
opt_yes=false
opt_verbose=true
opt_date=

# global variables
check_errors=0
git_available=false
gh_available=false
awk_available=false
sed_available=false
date_available=false
repo_available=false
candidate_valid=false
candidate=
version=

# display the result of a failed check
check_fail()
{
	printf 'checking that %s: FAILED\n' "$*" >&2
	check_errors=$(( check_errors + 1 ))
}

# display the result of a passed check
check_pass()
{
	msgVerbose "checking that $*: OK"
}

# a check has been skipped
check_skip()
{
	msgVerbose "checking that $*: skipped"
}

# ends the script
die()
{
	echo "${me}: $*" >&2
	exit 1
}

# be verbose about an action which will be done
msgVerbose()
{
	if $opt_verbose; then
		printf '%s\n' "$*"
	fi
}

# run a command
run()
{
	msgVerbose "run() '$@'"
	#if $opt_verbose; then
	#	printf 'run() '
	#	printf "'%s' " "$@"
	#	printf '\n'
	#fi
	"$@"
}

# usage
usage()
{
	cat <<'EOF'
Usage: ${me} [-dummy] [-yes] [-date YYYY-MM-DD] [-verbose | -noverbose]

Options accept one or two dashes and any unambiguous abbreviation.

  -du,  --dummy      validate and display the release plan without changing anything
  -y,   --yes        do not ask for confirmation
  -da,  --date       release date (defaults to today)
  -v,   --verbose    detail every check and action (default)
  -n,   --noverbose  suppress successful-check and action-command messages
  -h,   --help       display this help
EOF
}

###
### MAIN
###

while [ "$#" -gt 0 ]; do
	case $1 in
		--*) opt_name=${1#--} ;;
		-*) opt_name=${1#-} ;;
		*) die "no positional parameter is accepted, found '$1'";;
	esac

	case $opt_name in
		du|dum|dumm|dummy) opt_dummy=true ;;
		y|ye|yes) opt_yes=true ;;
		v|ve|ver|verb|verbo|verbos|verbose) opt_verbose=true ;;
		nov|nove|nover|noverb|noverbo|noverbos|noverbose) opt_verbose=false ;;
		da|dat|date)
			[ "$#" -ge 2 ] || die "option '$1' requires a YYYY-MM-DD argument"
			opt_date=$2
			shift
			;;
		h|he|hel|help) usage; exit 0 ;;
		d) die "ambiguous option '$1': use 'da' for date or 'du' for dummy" ;;
		*) die "unknown option: $1" ;;
	esac
	shift
done

if [ -z "$opt_date" ]; then
	if command -v date >/dev/null 2>&1; then
		opt_date=$(date +%Y-%m-%d)
	else
		opt_date=unavailable
	fi
fi

for command in git gh awk sed date mktemp; do
	if command -v "$command" >/dev/null 2>&1; then
		check_pass "required command '$command' is available"
	else
		check_fail "required command '$command' is not available"
	fi
done
if command -v git >/dev/null 2>&1; then git_available=true; fi
if command -v gh >/dev/null 2>&1; then gh_available=true; fi
if command -v awk >/dev/null 2>&1; then awk_available=true; fi
if command -v sed >/dev/null 2>&1; then sed_available=true; fi
if command -v date >/dev/null 2>&1; then date_available=true; fi

if [ -d .git ]; then
	repo_available=true
	check_pass "running from the project repository root"
else
	check_fail "must be run from the root of the project"
fi

for file in .VERSION ChangeLog.md README.md TODO.md; do
	if [ -f "$file" ]; then
		check_pass "$file exists"
	else
		check_fail "$file is missing"
	fi
done

date_shape_valid=false
case $opt_date in
	????-??-??) date_shape_valid=true ;;
	*) check_fail "invalid date '$opt_date' (expected YYYY-MM-DD)" ;;
esac
if $date_available && $date_shape_valid; then
	if date -d "$opt_date" +%Y-%m-%d >/dev/null 2>&1; then
		check_pass "release date '$opt_date' is valid"
	else
		check_fail "release date '$opt_date' does not exist"
	fi
else
	check_skip "calendar validation requires a valid date shape and the date command"
fi

if [ -f .VERSION ] && $sed_available && $awk_available; then
	candidate=$(sed -n '1p' .VERSION)
	if printf '%s\n' "$candidate" | awk '
		/^[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$/ { valid=1 }
		END { exit !valid }
	'; then
		candidate_valid=true
		version=${candidate%-rc.*}
		check_pass ".VERSION contains release candidate '$candidate', release will be v$version"
	else
		check_fail ".VERSION must contain a release candidate (for example 4.32.2-rc.0), got '$candidate'"
	fi
else
	check_skip "release candidate validation requires .VERSION, sed, and awk"
fi

if $git_available && $repo_available; then
	branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)
	if [ "$branch" = vnext ]; then check_pass "current branch is vnext"; else check_fail "current branch is '$branch', expected vnext"; fi
	if git show-ref --verify --quiet refs/heads/master; then check_pass "local master branch exists"; else check_fail "local branch 'master' does not exist"; fi
	if git diff --quiet; then check_pass "tracked files have no unstaged changes"; else check_fail "tracked files have unstaged changes"; fi
	if git diff --cached --quiet; then check_pass "tracked files have no staged changes"; else check_fail "tracked files have staged changes"; fi
	#if git show-ref --verify --quiet refs/heads/master && git show-ref --verify --quiet refs/heads/vnext; then
	#	if git merge-base --is-ancestor master vnext; then check_pass "vnext is based on master"; else check_fail "vnext is not based on the local master branch"; fi
	#else
	#	check_skip "branch ancestry requires local master and vnext branches"
	#fi
	if $candidate_valid; then
		if git rev-parse -q --verify "refs/tags/$version" >/dev/null 2>&1; then check_fail "tag '$version' already exists"; else check_pass "tag '$version' is available"; fi
	else
		check_skip "tag availability requires a valid candidate"
	fi
else
	check_skip "Git repository checks require git and the repository root"
fi

if [ -f ChangeLog.md ] && $awk_available && $candidate_valid; then
	heading_count=$(awk -v heading="### $candidate" '$0 == heading { count++ } END { print count+0 }' ChangeLog.md)
	if [ "$heading_count" -eq 1 ]; then check_pass "ChangeLog.md contains one '$candidate' heading"; else check_fail "ChangeLog.md must contain exactly one '$candidate' heading (found $heading_count)"; fi
	notes_count=$(awk -v heading="### $candidate" '
		$0 == heading { found=1; next }
		found && /^### / { exit }
		found && /^[[:space:]]+-[[:space:]]+[^[:space:]]/ { count++ }
		END { print count+0 }
	' ChangeLog.md)
	if [ "$notes_count" -gt 0 ]; then check_pass "the $candidate ChangeLog entry contains $notes_count release note(s)"; else check_fail "the $candidate ChangeLog entry has no release notes"; fi
else
	check_skip "ChangeLog validation requires ChangeLog.md, awk, and a valid candidate"
fi

if $gh_available; then
	if gh auth status >/dev/null 2>&1; then check_pass "GitHub CLI is authenticated"; else check_fail "GitHub CLI is not authenticated; run 'gh auth login'"; fi
else
	check_skip "GitHub authentication requires gh"
fi

if $git_available && $repo_available; then
	if git remote get-url origin >/dev/null 2>&1; then
		check_pass "Git remote 'origin' exists"
		remote_ref_usable=false
		if $opt_dummy; then
			check_skip "origin/master refresh (dummy mode does not modify remote-tracking refs)"
			remote_ref_usable=true
		else
			msgVerbose "fetching origin/master"
			if git fetch origin master; then
				check_pass "origin/master was fetched"
				remote_ref_usable=true
			else
				check_fail "unable to fetch origin/master"
			fi
		fi
		#if $remote_ref_usable && git show-ref --verify --quiet refs/remotes/origin/master && git show-ref --verify --quiet refs/heads/vnext; then
		#	if git merge-base --is-ancestor origin/master vnext; then check_pass "vnext contains origin/master"; else check_fail "vnext does not contain origin/master; update it before releasing"; fi
		#else
		#	check_skip "remote ancestry requires a usable origin/master and vnext"
		#fi
	else
		check_fail "Git remote 'origin' does not exist"
	fi
else
	check_skip "remote checks require git and the repository root"
fi

[ "$check_errors" -eq 0 ] || die "$check_errors preflight check(s) failed"

year=$(date -d "$opt_date" +%Y)
month=$(date -d "$opt_date" +%B)
day=$(date -d "$opt_date" +%-d)
case $day in
	11|12|13) suffix=th ;;
	*1) suffix=st ;;
	*2) suffix=nd ;;
	*3) suffix=rd ;;
	*) suffix=th ;;
esac
footer_date="$year, $month $day$suffix"
changelog_date=$(date -d "$opt_date" +%Y-%-m-%-d)
next_version=$(printf '%s' "$version" | awk -F. '{ printf "%d.%d.%d-rc.0", $1, $2, $3+1 }')

cat <<EOF
Release plan:
  candidate: $candidate
  release:   $version
  date:      $opt_date
  branch:    vnext -> master (fast-forward only)
  tag:       $version
  publish:   GitHub release v$version
  next:      $next_version on local vnext
EOF

$opt_dummy && exit 0

if ! $opt_yes; then
	printf 'Continue with release %s? [y/N] ' "$version"
	read -r answer
	case $answer in y|Y|yes|YES) ;; *) die "release cancelled" ;; esac
fi

tmp_files=
cleanup()
{
	for file in $tmp_files; do
		[ ! -e "$file" ] || rm -f "$file"
	done
}
trap cleanup EXIT HUP INT TERM

replace_file()
{
	target=$1
	shift
	msgVerbose "updating $target"
	tmp=$(mktemp "./.${target##*/}.release.XXXXXX")
	tmp_files="$tmp_files $tmp"
	awk "$@" "$target" >"$tmp" || die "unable to update $target"
	chmod --reference="$target" "$tmp" 2>/dev/null || true
	mv "$tmp" "$target"
}

replace_file .VERSION -v value="$version" 'NR == 1 { print value; next } { print }'
replace_file ChangeLog.md -v old="### $candidate" -v new="### $version" -v released="$changelog_date" -v footer="$footer_date" '
	$0 == old { print new; section=1; next }
	section && /^[[:space:]]*Release date:/ { sub(/Release date:.*/, "Release date: " released); section=0 }
	/^- Last updated on / { print "- Last updated on " footer; next }
	{ print }
'
for document in README.md TODO.md; do
	replace_file "$document" -v footer="$footer_date" '
		/^- Last updated on / { print "- Last updated on " footer; next }
		{ print }
	'
done

run git add .VERSION ChangeLog.md README.md TODO.md
git diff --cached --quiet && die "release metadata did not change"
run git commit -m "Releasing v$version"

run git checkout master
run git pull --rebase
run git merge vnext
run git tag -am "Releasing v$version" "$version"
run git push
run git push --tags

notes_file=$(mktemp "./.release-notes.XXXXXX")
tmp_files="$tmp_files $notes_file"
awk -v heading="### $version" '
	$0 == heading { found=1; next }
	found && /^### / { exit }
	found && /^[[:space:]]*Release date:/ { next }
	found { sub(/^[[:space:]]{4}/, ""); print }
' ChangeLog.md >"$notes_file"
run gh release create "$version" --title "v$version" --notes-file "$notes_file" --verify-tag

run git checkout vnext
run git rebase master
replace_file .VERSION -v value="$next_version" 'NR == 1 { print value; next } { print }'
replace_file ChangeLog.md -v heading="### $next_version" '
	!inserted && /^### / {
		print heading "\n\n    Release date: \n\n    - \n"
		inserted=1
	}
	{ print }
'
run git add .VERSION ChangeLog.md
run git commit -m 'Post-release minimal version bump'

echo "Release v$version created successfully."
echo "The next candidate $next_version is committed locally on vnext."
