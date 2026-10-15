# SPDX-License-Identifier: Apache-2.0
# Sourced by the build scripts. Sets $target and $sdk.
#
# The newest SDK is sometimes ahead of the installed compiler, so pick the first one it can read.
target="$(uname -m)-apple-macos14"

pick_sdk() {
  local candidates=("${SDKROOT:-}" "$(xcrun --show-sdk-path 2>/dev/null || true)")
  while IFS= read -r path; do candidates+=("$path"); done \
    < <(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk 2>/dev/null | sort -r)
  for candidate in "${candidates[@]}"; do
    [ -n "$candidate" ] && [ -d "$candidate" ] || continue
    if echo 'import AppKit' | swiftc -sdk "$candidate" -target "$target" -typecheck - >/dev/null 2>&1; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

sdk="$(pick_sdk)" || { echo "No usable macOS SDK. Run: xcode-select --install" >&2; exit 1; }
