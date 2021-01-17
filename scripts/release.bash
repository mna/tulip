#!/usr/bin/env bash

set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "missing the new version argument"
  exit 1
fi

NEW_VERSION="$1"

if [[ ! "$(echo "${NEW_VERSION}" | grep -P "^\d\.\d\.\d$")" ]]; then
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
echo $PREV_VERSION
#luarocks new_version ./rockspecs/tulip-0.0.10-2.rockspec
