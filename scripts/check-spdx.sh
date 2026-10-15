#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Fails if a tracked source file lacks an SPDX license header.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

missing=0
# Includes untracked files so it also works before the first commit.
while IFS= read -r file; do
  case "$file" in
    services/relay/*) continue ;; # AGPL-3.0 tree checks its own header
  esac
  if ! head -n 5 "$file" | grep -q "SPDX-License-Identifier:"; then
    echo "missing SPDX header: $file"
    missing=1
  fi
done < <(git ls-files --cached --others --exclude-standard -- '*.swift' '*.sh')

exit "$missing"
