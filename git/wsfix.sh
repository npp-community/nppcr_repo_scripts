#!/bin/bash

# from doener (who else!)
# to be called as an index-filter

if git rev-parse --quiet --verify $GIT_COMMIT^ >/dev/null
then
  against=$(map $(git rev-parse $GIT_COMMIT^))
  git reset -q $against -- .
else
  # Initial commit: diff against an empty tree object
  against=4b825dc642cb6eb9a060e54bf8d69288fbee4904
  git rm --cached -rfq --ignore-unmatch '*'
fi

git diff --full-index $against $GIT_COMMIT | git apply --cached --whitespace=fix

