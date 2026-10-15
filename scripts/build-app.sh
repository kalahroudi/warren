#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Builds build/Warren.app with the Swift compiler alone, so it works with only the
# Xcode Command Line Tools. Development build, ad-hoc signed. Release builds are spec 003.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

target="$(uname -m)-apple-macos14"

# The newest SDK is sometimes ahead of the installed compiler, so pick the first one it can read.
pick_sdk() {
  local candidates=("${SDKROOT:-}" "$(xcrun --show-sdk-path 2>/dev/null || true)")
  while IFS= read -r path; do candidates+=("$path"); done \
    < <(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk 2>/dev/null | sort -r)
  for sdk in "${candidates[@]}"; do
    [ -n "$sdk" ] && [ -d "$sdk" ] || continue
    if echo 'import AppKit' | swiftc -sdk "$sdk" -target "$target" -typecheck - >/dev/null 2>&1; then
      echo "$sdk"
      return 0
    fi
  done
  return 1
}
sdk="$(pick_sdk)" || { echo "No usable macOS SDK. Run: xcode-select --install" >&2; exit 1; }

out=build
app="$out/Warren.app"
rm -rf "$app" "$out/obj"
mkdir -p "$out/obj" "$app/Contents/MacOS" "$app/Contents/Resources"

swiftc -sdk "$sdk" -target "$target" -swift-version 6 -O -wmo -parse-as-library \
  -module-name WarrenCore -emit-module -emit-module-path "$out/obj/WarrenCore.swiftmodule" \
  -c Sources/WarrenCore/*.swift -o "$out/obj/WarrenCore.o"

swiftc -sdk "$sdk" -target "$target" -swift-version 6 -O -parse-as-library \
  -module-name WarrenApp -I "$out/obj" \
  Sources/WarrenApp/*.swift "$out/obj/WarrenCore.o" -o "$app/Contents/MacOS/Warren"

cp App/Info.plist "$app/Contents/Info.plist"
cp App/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app" >/dev/null
echo "$app"
