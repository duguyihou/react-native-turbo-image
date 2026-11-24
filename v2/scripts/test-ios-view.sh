#!/usr/bin/env bash
# Runs the Fabric view's tests (apps/example/ios/TurboImageExampleTests) on an
# iPhone simulator.
#
# They drive the real `TurboImageComponentView` and core with a fake loader:
# when the view loads and what it asks the loader for, such as an upgrade
# after it outgrows its image, which no load event reports. The view only
# builds inside a React Native app, so the tests are a bundle hosted by the
# example app (the adapter tests, scripts/test-ios-adapter.sh, need no app).
#
# Needs `pod install` in apps/example/ios first.
#
# Usage: scripts/test-ios-view.sh [simulator-udid]
# Exit:  xcodebuild's; 1 when there is no simulator to run on.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
example="$(cd "${script_dir}/../apps/example" && pwd)"

# Default to the first available iPhone simulator, as smoke-ios.sh does.
# `|| true`: with no match grep fails, and under `set -e -o pipefail` that
# would end the script here, before the message below.
udid="${1:-$(xcrun simctl list devices available | grep -m1 -oE 'iPhone[^(]*\(([0-9A-F-]{36})\)' | grep -oE '[0-9A-F-]{36}' || true)}"
if [[ -z "${udid}" ]]; then
  echo "FAIL: no available iPhone simulator" >&2
  exit 1
fi

cd "${example}"
# React Native's "Generate Specs" phase does not re-run for a library's spec
# change, so Codegen runs first, as the example's build:ios scripts do.
bun run codegen:ios
xcodebuild test \
  -workspace ios/TurboImageExample.xcworkspace -scheme TurboImageExample \
  -configuration Debug -destination "id=${udid}" -derivedDataPath ios/build \
  -only-testing:TurboImageExampleTests
