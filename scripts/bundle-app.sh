#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Assembles a runnable, unsigned Warren.app from the SwiftPM build (development only).
# Signed and notarized bundles are produced by the release pipeline (spec 003).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

swift build --product WarrenApp
bin="$(swift build --product WarrenApp --show-bin-path)/WarrenApp"

app="build/Warren.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin" "$app/Contents/MacOS/Warren"
cp App/Info.plist "$app/Contents/Info.plist"
echo "$app"
