#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Builds build/bin/warren with the Swift compiler alone (Command Line Tools only).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
source scripts/lib/sdk.sh

out=build
mkdir -p "$out/obj" "$out/bin"

swiftc -sdk "$sdk" -target "$target" -swift-version 6 -O -wmo -parse-as-library \
  -module-name WarrenCore -emit-module -emit-module-path "$out/obj/WarrenCore.swiftmodule" \
  -c $(find Sources/WarrenCore -name "*.swift") -o "$out/obj/WarrenCore.o"

swiftc -sdk "$sdk" -target "$target" -swift-version 6 -O \
  -module-name WarrenCLI -I "$out/obj" \
  Sources/WarrenCLI/main.swift "$out/obj/WarrenCore.o" -o "$out/bin/warren"
echo "$out/bin/warren"
