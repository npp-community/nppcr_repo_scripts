#!/bin/bash
# Script to keep an svn mirror repo up to date.
# Assumes git-svn mirror repo was created as a local bare repo.
# For testing the script will accepts arguments for specific fetching of revisions.
#   no arg == let git-svn determine the start and fetch to HEAD
#   one arg == +n revisions from the latest
#   two args == start:end range

# Environment setup
PATH=$PATH:/usr/local/bin:/usr/local/libexec/git-core
svn2git_repo=/home/nppgit/repos/svn2git/npp_svn_mirror.git
retry_limit=1
sleep_time="5s"

# Uncomment and change _USER_ to enable keychain to allow cron
# to do password-less pushing.
source /home/nppgit/.keychain/$HOSTNAME-sh

# Capture the last SVN revision that was fetched.  ( Thanks to doener on Freenode's #git )
cd $svn2git_repo
pre_fetch_svn_rev=$(git --bare for-each-ref --format='%(refname)' refs/remotes/svn |\
  xargs git --bare --no-pager log --no-walk | sed -ne 's/\s\+\git-svn-id:.*@\([0-9]\+\) .*/\1/p' |\
  sort -n -r | head -n1)
# Define the fetch revision range.
if [ -n "$2" ]
then 
  rev_range="-r $1:$2"
elif [ -n "$1" ]
  then
    rev_range="-r $[ $pre_fetch_svn_rev ]:$[ $pre_fetch_svn_rev + $1 ]"
else
  rev_range=
fi

# In case the fetch doesn't work because of network issues try 3 times.
i=0
fail_text=""
until [ $i -eq $retry_limit ] || ( git svn fetch --quiet ${rev_range} )
do

  if [ $i -lt $retry_limit ]
  then
    echo " The fetch failed!  Trying again..."
    sleep "$sleep_time"
  else
    echo " The fetch failed!  Giving up..."
    fail_text="fetch from SVN"
  fi
  let i=i+1

done

# Update mirror if a new svn rev has been fetched or if previous push didn't complete.
post_fetch_svn_rev=$(git --bare for-each-ref --format='%(refname)' refs/remotes/svn |\
  xargs git --bare --no-pager log --no-walk | sed -ne 's/\s\+\git-svn-id:.*@\([0-9]\+\) .*/\1/p' |\
  sort -n -r | head -n1)

pre_push_mirror_rev=$(git --bare for-each-ref --format='%(refname)' refs/remotes/mirror |\
  xargs git --bare --no-pager log --no-walk | sed -ne 's/\s\+\git-svn-id:.*@\([0-9]\+\) .*/\1/p' |\
  sort -n -r | head -n1)

if [ $pre_fetch_svn_rev -ne $post_fetch_svn_rev -o $post_fetch_svn_rev -ne $pre_push_mirror_rev ]
then
  prev_master_head=$(git rev-parse HEAD)
  git update-ref refs/heads/master refs/remotes/svn/trunk

  let i=0
  until [ $i -gt $retry_limit ] || ( git push mirror )
  do

    if [ $i -lt $retry_limit ]
    then
      echo "Push to mirror failed!  Trying again..."
      sleep "$sleep_time"
    else
      echo "The push failed!  Giving up..."
      git update-ref refs/heads/master $prev_master_head
      if [ -n "$fail_text" ]
      then
        fail_text=$fail_text"\n and while trying to push to the mirror"
      else
        fail_text="push to the mirror"
      fi
    fi
    let i=i+1

  done
fi

post_push_mirror_rev=$(git --bare for-each-ref --format='%(refname)' refs/remotes/mirror |\
  xargs git --bare --no-pager log --no-walk | sed -ne 's/\s\+\git-svn-id:.*@\([0-9]\+\) .*/\1/p' |\
  sort -n -r | head -n1)


# Output summary for cron email notification.
echo ""
echo "***************************************"
echo "**              Summary              **"
echo "***************************************"
echo 'Starting Revisions:'
echo "  svn    = $pre_fetch_svn_rev"
echo "  mirror = $pre_push_mirror_rev"
echo ""
echo "Ending Revisions:"
echo "  svn    = $post_fetch_svn_rev"
echo "  mirror = $post_push_mirror_rev"
echo ""
echo "Current SHAs::"
echo "$(git for-each-ref)"


if [ -n "$fail_text" ] 
then
  echo ""
  echo -e " WARNING::  The script failed to complete successfully when trying to $fail_text!"
  exit 1
fi
