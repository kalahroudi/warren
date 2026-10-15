#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Builds build/Warren.app from the SwiftPM build. Development build, ad-hoc signed.
# Release builds (signing, notarization) are spec 003.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

swift build -c release --product WarrenApp
bin="$(swift build -c release --product WarrenApp --show-bin-path)/WarrenApp"

app=build/Warren.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Warren"
cp App/Info.plist "$app/Contents/Info.plist"
cp App/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app" >/dev/null
echo "$app"
