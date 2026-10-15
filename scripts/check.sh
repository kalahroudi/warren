#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The single gate: format, lint, license headers, build, tests.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

for tool in swiftlint swiftformat; do
  command -v "$tool" >/dev/null 2>&1 || { echo "$tool not found. Run: just setup"; exit 1; }
done

echo "== format";  swiftformat Sources Tests Package.swift --lint
echo "== lint";    swiftlint lint --strict
echo "== spdx";    scripts/check-spdx.sh
echo "== build";   swift build
echo "== test";    swift test
echo "All checks passed."
