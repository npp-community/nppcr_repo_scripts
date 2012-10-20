#!/bin/sh

# This script uses 'git filter-branch --index-filter' to rewrite a branch that
# does not comply with a whitespace policy into one that does.

# The following warning from GIT-FILTER-BRANCH(1) applies.

# WARNING! The rewritten history will have different object names for all the
# objects and will not converge with the original branch. You will not be able
# to easily push and distribute the rewritten branch on top of the original
# branch.  Please do not use this command if you do not know the full
# implications, and avoid using it anyway, if a simple single commit would
# suffice to fix your problem.

# The script works with only one branch which would typically be the master
# branch of an upstream repository, or the trunk if coming from SVN.
# The script will create the branches needed for conversion, then rewrite all
# of the dirty commits to match a whitespace policy that allows new blank lines
# at the end of the file.  A backup branch of the last run conversion is kept
# and restored when the expected last dirty or clean commit ref does not match
# the current state of the dirty or clean branch.
# Validation is done by verifying that there is a difference between the origin
# and the clean branch, but that there is no difference when ignoring
# whitespace change.

# Script will exit with an exit code of 1 if a problem is encountered.

# Major thanks to Bjorn Steinbrink for getting me started on this route and
# helping every step of the way!
# Junio Hamano for the extra work in the whitespace handling of git.

# TODO: add useful error output

# TODO:  diff: introduce --ignore-blank-at-eof
# While it would be nice to be able to also have the policy followed in regard
# to blank lines at the end of the file 'git diff' does not currently (that I
# know of) have an --ignore-blank-at-eof option.  So any diff between the
# original commit and the rewritten one would fail if the eof blank lines had
# been altered.

# Preparation:
# Clone the repository with the branch that will be converted.
# Ensure the following have been set:
#   git config core.whitespace -blank-at-eof
#   git config apply.whitespace fix
# Setup the script
# Run the script
# Publish the clean branch.

# Envorinment
PATH=$PATH:/usr/local/bin:/usr/local/libexec/git-core
# Repo
REPO=/home/nppgit/repos/git/npp_svn_wsfix

#  Assumes 'git fetch' will fetch the origin branch to convert.
ORIG_BRANCH=origin/master
DIRTY_BRANCH=master
CLEAN_BRANCH=master_clean

#------------------
# Filter scripts
#------------------
WS_FILTER='filter_from_base(){
	base=$(map $(git rev-parse --verify $GIT_COMMIT^)) ||
		base=4b825dc642cb6eb9a060e54bf8d69288fbee4904 # Empty tree
	if [ -n "$1" ] && [ -n "$2" ] && [ "$base" = "$1" ]
	then
		base="$2"
	fi
	git read-tree $base

	git diff --full-index -p $base $GIT_COMMIT | \
		git apply --cached > /dev/null 2>&1
}'

WS_MSG='
	cat && echo "ws-fix-id: whitespace fixed rewrite of: $GIT_COMMIT"
'

#------------------
# Functions
#------------------

warn(){
	echo "$*" >&2
}

die(){
	echo >&2
	echo "$*" >&2
	exit 1
}

# Cache stores the commit to begin processing from.
cache_get(){
	if [ -z $1 ]; then return 1; fi

	branch=$1
	cache_file=".git/cache_file.$branch"
	if [ -e "$cache_file" ]
	then
		read cached_rev < "$cache_file"
		echo $cached_rev
	else
		warn "Previously fixed commit for branch $branch not found"
		warn "in cache file: $cache_file"
		return 1
	fi
}

cache_set(){
	if [ -z $1 ] || [ -z $2 ]; then return 1; fi

	branch=$1
	commit=$2
	echo $commit> .git/cache_file.$branch
}

# Initialize setup of a branch.
initBranch(){
	branch=$1
	if ! git rev-parse -q --verify $branch >/dev/null
	then
		if ! git checkout -q -b $branch
		then
			die "Can not create branch: $branch"
		fi
	elif ! git checkout -q $branch
	then
		die "Branch $branch exists but can not be checked out!"
	fi
}

# Return matching original rev from a fixed rev 
map_ws_fixed(){
	if [ -z $1 ]; then return 1; fi

	clean_commit=$1
	orig_commit=$(git log -1 $clean_commit | \
		sed -ne 's/\s\+\ws-fix-id:.*: \([0-9 a-z]\+\).*/\1/p')
	if ! git rev-parse -q --verify $orig_commit >/dev/null
	then
		warn "Failed to map fixed rev to original rev"
		warn "clean rev: $clean_rev"
		echo
		return 1
	fi

	echo "$orig_commit"
}
	
# Validate conversion differences
validate_ws_fix(){
	# No commit between the previously validated commit and clean HEAD
	# should introduce a whitespace error on $CLEAN_BRANCH.
	# (each ref is checked for better validation)
	revs="$(git rev-parse -q --verify backup_$CLEAN_BRANCH)..$CLEAN_BRANCH"
	commits=$(git rev-list "$revs" | wc -l)
	git checkout -q $CLEAN_BRANCH

	git log --format=%H $revs |
	while read clean_rev
	do
		fixed_commit_count=$(($fixed_commit_count+1))
		printf "\rVerifying $clean_rev ($fixed_commit_count/$commits)"
		orig_rev=$(map_ws_fixed $clean_rev)

		if ! git diff -b --exit-code $clean_rev $orig_rev >/dev/null
		then
			warn
			warn "Error: non-whitespace content does not match!"
			warn " orig rev: $orig_rev"
			die "clean rev: $clean_rev"
		fi

		if ! git diff --check "$clean_rev^..$clean_rev" >/dev/null
		then
			warn
			warn "Error: whitespace error introduced!"
			die "clean_rev: $clean_rev"
		fi

		# There _should_ be a difference between the clean and origin
		# unless whitespace was fixed prior to being fetched.
		if git diff --exit-code $clean_rev $orig_rev >/dev/null
		then
			if git diff --check $clean_rev^ $orig_rev >dev/null
			then
				warn
				warn "********** ALERT ***********"
				warn "No Whitespace Fix Was Needed"
			else	
				warn
				warn "Whitespace fix needed but not applied."
				warn " orig rev: $orig_rev"
				die "clean rev: $clean_rev"
			fi
		fi
	done
	echo
}

#-----------------
# Initialization
#-----------------

if [ ! -e "$REPO" ]
then
	die "Repository and script need to be setup."
fi
cd $REPO

if ! git config --get core.whitespace|grep -q '\-blank\-at\-eof'
then
	die "core.whitespace -blank-at-eof needs to be defined."

elif ! git config --get apply.whitespace|grep -q 'fix'
then
	die "apply.whitespace fix needs to be defined."

elif ! git rev-parse --verify -q $ORIG_BRANCH >/dev/null
then
	die "Branch $ORIG_BRANCH is not available."
fi

# Verify branches are setup.
initBranch $CLEAN_BRANCH
initBranch $DIRTY_BRANCH
git checkout -q $DIRTY_BRANCH

# Pre-Fetch commits.
ORIG_HEAD_START=$(git rev-parse --verify $ORIG_BRANCH)
DIRTY_BASE=$(cache_get $DIRTY_BRANCH)
CLEAN_BASE=$(cache_get $CLEAN_BRANCH)
curr_clean=$(git rev-parse --verify $CLEAN_BRANCH)
expected_dirty=$(map_ws_fixed "$(git rev-parse $CLEAN_BRANCH)")

echo "Whitespace fixing of commits..."

git fetch
git reset -q --hard $ORIG_BRANCH

# Post-Fetch commits.
ORIG_HEAD_NEW=$(git rev-parse --verify $ORIG_BRANCH)
curr_dirty=$(git rev-parse --verify $DIRTY_BRANCH)

if [ "$ORIG_HEAD_START" = "$ORIG_HEAD_NEW" ] && \
	[ "$CLEAN_BASE" = "$curr_clean" ] && \
	[ "$DIRTY_BASE" = "$curr_dirty" ] && \
	[ "$curr_dirty" = "$expected_dirty" ]
then
	# Everything is up to date.
	process_commits="false"

elif [ -n "$CLEAN_BASE" ] || [ -n "$DIRTY_BASE" ]
then
	# Validate base commits.
	if [ "$CLEAN_BASE" != "$curr_clean" ] || \
		[ "$DIRTY_BASE" != "$ORIG_HEAD_START" ]
	then
		# Did the user reset $CLEAN_BRANCH back to the backup?
		if git rev-parse -q --verify backup_$CLEAN_BRANCH >/dev/null
		then
			backup_sha="$(git rev-parse backup_$CLEAN_BRANCH)"
			if [ "$curr_clean" = "$backup_sha" ]
			then
				# Reset to the previous run parameters.
				warn "Base commits don't match: using backup."
				git branch -D $CLEAN_BRANCH
				git checkout -b \
					$CLEAN_BRANCH backup_$CLEAN_BRANCH
				cache_set $CLEAN_BRANCH \
					$(git rev-parse $CLEAN_BRANCH)
				CLEAN_BASE=$(cache_get $CLEAN_BRANCH)

				dirty_sha=$(map_ws_fixed $CLEAN_BASE)
				cache_set $DIRTY_BRANCH $dirty_sha
				DIRTY_BASE=$(cache_get $DIRTY_BRANCH)
			else
				# Force processing of all commits.
				CLEAN_BASE=""
				DIRTY_BASE=""
			fi
		else
			# Force processing of all commits.
			CLEAN_BASE=""
			DIRTY_BASE=""
		fi
	fi
fi

#------------------
# Filter branch
#------------------
if [ "$process_commits" != "false" ]
then
	git checkout -q $CLEAN_BRANCH
	git reset -q --hard $ORIG_BRANCH
	git clean -fdx

	if [ -z "$CLEAN_BASE" ] || [ -z "$DIRTY_BASE" ]
	then
		# Process all commits.
		if [ -e "./ws_fix_index" ]; then rm -Rf "./ws_fix_index"; fi
		git filter-branch --original ws_fix_index \
			--index-filter "$WS_FILTER; filter_from_base " \
			--msg-filter "$WS_MSG" \
			-- $CLEAN_BRANCH
	else
		# Set the backup branch.
		if git rev-parse -q --verify backup_$CLEAN_BRANCH >/dev/null
		then
			git branch -D backup_$CLEAN_BRANCH >/dev/null
		fi
		git branch -v backup_$CLEAN_BRANCH $CLEAN_BASE

		git reset -q -- .

		# Process new commits.
		git filter-branch --original ws_fix_index \
			--index-filter "$WS_FILTER; filter_from_base \
				$DIRTY_BASE $CLEAN_BASE" \
			--parent-filter "sed s/$DIRTY_BASE/$CLEAN_BASE/" \
			--msg-filter "$WS_MSG" \
			-- $DIRTY_BASE..$CLEAN_BRANCH
	fi

	git reset -q --hard

	#------------------
	# Validate
	#------------------
	validate_ws_fix $CLEAN_BRANCH

	#------------------
	# Store State
	#------------------
	# Save the last converted commit for the next run.
	cache_set $CLEAN_BRANCH $(git rev-parse $CLEAN_BRANCH)
	if [ -z "$CLEAN_BASE" ]
	then
		if git rev-parse -q --verify backup_$CLEAN_BRANCH
		then
			git branch -D backup_$CLEAN_BRANCH
		fi
		git branch backup_$CLEAN_BRANCH $CLEAN_BRANCH
	fi
	cache_set $DIRTY_BRANCH $(git rev-parse $DIRTY_BRANCH)

	echo "**************************************************"
	echo "Whitespace has been converted and validated up to:"
	echo ""
	echo "$(git log -1 $CLEAN_BRANCH)"
	echo ""
	echo "Shortstat of the latest conversion:"
	if [ -z "$CLEAN_BASE" ] || [ -z "$DIRTY_BASE" ]
	then
		git checkout -q $CLEAN_BRANCH
		initial_rev=$(git log --format=%H|tail -n -1)
		echo "$(git diff --shortstat $initial_rev..$CLEAN_BRANCH)"
		echo ""
		echo "Shortstat of the original commit:"
		git checkout -q $DIRTY_BRANCH
		initial_rev=$(git log --format=%H|tail -n -1)
		echo "$(git diff --shortstat $initial_rev..$DIRTY_BRANCH)"
	else
		echo "$(git diff --shortstat $CLEAN_BASE..$CLEAN_BRANCH)"
		echo ""
		echo "Shortstat of the original commit:"
		echo "$(git diff --shortstat $DIRTY_BASE..$DIRTY_BRANCH)"
	fi
else
	echo "No new revisions found to process."
	echo "Current SHAs:"
	echo "$(git show-ref)"
fi

exit 0

