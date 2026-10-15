#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Builds build/Warren.app with the Swift compiler alone, so it works with only the
# Xcode Command Line Tools. Development build, ad-hoc signed. Release builds are spec 003.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

source scripts/lib/sdk.sh

out=build
app="$out/Warren.app"
rm -rf "$app" "$out/obj"
mkdir -p "$out/obj" "$app/Contents/MacOS" "$app/Contents/Resources"

swiftc -sdk "$sdk" -target "$target" -swift-version 6 -O -wmo -parse-as-library \
  -module-name WarrenCore -emit-module -emit-module-path "$out/obj/WarrenCore.swiftmodule" \
  -c $(find Sources/WarrenCore -name "*.swift") -o "$out/obj/WarrenCore.o"

swiftc -sdk "$sdk" -target "$target" -swift-version 6 -O -parse-as-library \
  -module-name WarrenApp -I "$out/obj" \
  $(find Sources/WarrenApp -name "*.swift") "$out/obj/WarrenCore.o" -o "$app/Contents/MacOS/Warren"

cp App/Info.plist "$app/Contents/Info.plist"
cp App/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app" >/dev/null
echo "$app"
