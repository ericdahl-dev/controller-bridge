#!/bin/sh
# Prints "true" when a release tag goes to external testers too, else "false" (#244). Only an annotated tag whose
# message contains [external] (any case) does; a lightweight tag, a missing one, or no marker is internal only.
#   scripts/tag-external.sh v1.0.2
set -eu
tag="$1"
if [ "$(git cat-file -t "refs/tags/$tag" 2>/dev/null)" = tag ] &&
   git for-each-ref "refs/tags/$tag" --format='%(contents)' | grep -qi '\[external\]'; then
  echo true
else
  echo false
fi
