#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Builds build/bin/warren from the SwiftPM build.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

swift build -c release --product warren
mkdir -p build/bin
cp "$(swift build -c release --product warren --show-bin-path)/warren" build/bin/warren
echo build/bin/warren
