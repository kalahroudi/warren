#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Usage: check-dco.sh <revision-range>   e.g. origin/main..HEAD
# Fails if any non-merge commit in the range lacks a Signed-off-by trailer.
set -euo pipefail

range="${1:?usage: check-dco.sh <revision-range>}"
bad=0
for sha in $(git rev-list --no-merges "$range"); do
  if ! git show -s --format=%B "$sha" | grep -qE '^Signed-off-by: .+ <.+>$'; then
    echo "missing Signed-off-by: $(git show -s --format='%h %s' "$sha")"
    bad=1
  fi
done
exit "$bad"
