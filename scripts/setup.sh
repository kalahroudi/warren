#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Verifies and installs the toolchain needed to build Warren.
set -euo pipefail

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Xcode command line tools are missing. Run: xcode-select --install"
  exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required to install SwiftLint and SwiftFormat: https://brew.sh"
  exit 1
fi

for tool in swiftlint swiftformat; do
  command -v "$tool" >/dev/null 2>&1 || brew install "$tool"
done

swift --version
echo "Setup complete."
