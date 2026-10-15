#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# UI code must read state through StateProvider. Only the app delegate may create the fixture provider.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

bad=$(grep -rln "FixtureProvider" Sources/WarrenApp --include='*.swift' | grep -v 'Sources/WarrenApp/AppDelegate.swift' || true)
if [ -n "$bad" ]; then
  echo "FixtureProvider referenced outside AppDelegate.swift:"
  echo "$bad"
  exit 1
fi
