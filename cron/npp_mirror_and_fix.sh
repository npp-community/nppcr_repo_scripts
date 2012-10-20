#!/bin/bash

PATH=$PATH:/usr/local/bin:/usr/local/libexec/git-core
PUSH_REPO=/home/nppgit/repos/git/npp_svn_final_cleanup.git

update_script=/home/nppgit/scripts/git/npp_svn_mirror_update.sh
wsfix_script=/home/nppgit/scripts/git/npp_ws_fix_trunk.sh
final_cleanup_script=/home/nppgit/scripts/git/npp_final_cleanup.sh

if eval $update_script && eval $wsfix_script && eval $final_cleanup_script
then
	# Uncomment and change _USER_ to enable keychain to allow cron
	# to do password-less pushing.
	source /home/nppgit/.keychain/$HOSTNAME-sh

	cd "$PUSH_REPO"
	if ! git push nppcr_npp master
	then
		echo "*********************************"
	fi
fi

