#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Regenerates App/AppIcon.icns from docs/assets/icon.png (macOS built-ins only).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

set_dir="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$set_dir"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" docs/assets/icon.png --out "$set_dir/icon_${size}x${size}.png" >/dev/null
  sips -z "$((size * 2))" "$((size * 2))" docs/assets/icon.png --out "$set_dir/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$set_dir" -o App/AppIcon.icns
echo "App/AppIcon.icns"
