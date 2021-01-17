#!/usr/bin/env bash

set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "missing the new version argument"
  echo "usage: ./scripts/release.bash NEW.NEW.NEW [OLD.OLD.OLD]"
  exit 1
fi

if [[ ! -s ./tulip/init.lua ]]; then
  echo "make sure you are running from the root of the repository"
  exit 1
fi

NEW_VERSION="$1"

if ! echo "${NEW_VERSION}" | grep -qP "^\d\.\d\.\d$"; then
  echo "invalid new version, N.N.N format is expected"
  exit 1
fi

# if there are any uncommitted changes, stop
if [[ -n "$(git status --porcelain)" ]]; then
  echo "git repository has uncommitted changes"
  exit 1
fi

# get the latest tag
if [[ $# -gt 1 ]]; then
  PREV_VERSION="$2"
else
  PREV_VERSION="$(git describe --tags --abbrev=0 | grep -P --only-matching "(\d\.\d\.\d)$")"-1
fi

# create the new rockspec
luarocks new_version ./rockspecs/"tulip-${PREV_VERSION}.rockspec" "${NEW_VERSION}"

"${EDITOR:-vim}" ./"tulip-${NEW_VERSION}-1.rockspec"

# if file is empty, stop the release and remove it
if [[ ! -s ./"tulip-${NEW_VERSION}-1.rockspec" ]]; then
  rm ./"tulip-${NEW_VERSION}-1.rockspec"
  echo "operation canceled by user"
  exit 2
fi

# move it to its proper destination
mv ./"tulip-${NEW_VERSION}-1.rockspec" ./rockspecs/

# update the version in the Lua code
sed -iE "s/^(\s+)(VERSION = '[^']+')/\\1VERSION = '${NEW_VERSION}'/" ./tulip/init.lua

git add -A
git commit -m "Create version ${NEW_VERSION}"
git tag "v${NEW_VERSION}"

# publish the new rock
luarocks upload ./rockspecs/"tulip-${NEW_VERSION}-1.rockspec"
