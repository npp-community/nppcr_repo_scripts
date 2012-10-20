#!/bin/sh

# filter-branch script to rewrite-history for final cleanup before
# making pushing to public repo.
# It will remove some identified binaries from history, clean-up the
# git-svn-id numbers and ws-fix-id and reduce multiple blank lines to
# a single blank line

PATH=$PATH:/usr/local/bin:/usr/local/libexec/git-core

# Assumes 'fetch' will acquire the origin repo to rewrite
REPO_PATH=/home/nppgit/repos/git/npp_svn_final_cleanup.git

cd $REPO_PATH

echo "Remove binary files..."

remote_ref=$(git ls-remote origin refs/heads/master_clean | cut -f -1)

if [ -e "cached_prev_ref" ]
then
	prev_ref=$(cat cached_prev_ref)
fi

echo "Previously processed: $prev_ref"
echo "Current remote ref:   $remote_ref"
echo "$remote_ref" > "cached_prev_ref"

if [ "$remote_ref" != "$prev_ref" ]
then
	git fetch origin

	git filter-branch \
	--index-filter '
		git rm --cached --ignore-unmatch PowerEditor/bin/plugins\* >/dev/null

		for ext in aps bak dll ncb pdb zip
		do
			git rm --cached --ignore-unmatch ./\*."$ext" >/dev/null
		done' \
	--env-filter '
		n=$GIT_AUTHOR_NAME
		m=$GIT_AUTHOR_EMAIL

		case ${GIT_AUTHOR_NAME} in
		        "donho") n="Don Ho" ; m="don.h@free.fr" ;;
		        "yniq") n="Y N" ; m="yniq@users.sourceforge.net" ;;
		        "harrybharry") n="Harry" ; m="harrybharry@users.sourceforge.net" ;;
		        "aathell") n="Thell Fowler" ; m="git@tbfowler.name" ;;
		        *) n="unknown" ; m="don.h@free.fr" ;;
		esac

		export GIT_AUTHOR_NAME="$n"
		export GIT_AUTHOR_EMAIL="$m"
		export GIT_COMMITTER_NAME="$n"
		export GIT_COMMITTER_EMAIL="$m"
	' \
        --msg-filter '
                sed -e "s/^git-svn-id:.*@\([0-9]\+\) .*/- Notepad-plus svn trunk @ \1/" \
                -e "/^ws-fix-id:/d" \
		-e "2s/./\n&/" \
		-e "/./,/^$/!d"
	' -- --all >/dev/null

	rm -Rf $REPO_PATH/refs/original
	rm -Rf $REPO_PATH/logs/

	git gc
	git repack -a -d -f
	git update-ref refs/heads/master refs/remotes/origin/master
	echo "Current SHAs:"
	echo "$(git show-ref)"
else
	echo "No new commits to process."
	echo "Current SHAs:"
	echo "$(git show-ref)"
	exit 1
fi

exit 0

