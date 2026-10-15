# SPDX-License-Identifier: Apache-2.0
# Thin wrappers. The logic lives in scripts/ so CI and humans run the same thing.

default:
    @just --list

# Verify and install the toolchain
setup:
    scripts/setup.sh

# Format, lint, license headers, build, tests
check:
    scripts/check.sh

# Build the dev app bundle and launch it
dev:
    scripts/bundle-app.sh
    open build/Warren.app
