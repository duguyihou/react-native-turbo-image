#!/usr/bin/env bash
# Runs the Fabric view's tests (apps/example/ios/TurboImageExampleTests) on an
# iPhone simulator, hosted by the example app. Needs `pod install` first.
#
# Env:   CONFIGURATION  Debug (default) or Release (reuses the
#                       `build:ios:release` app, as CI does)
# Usage: scripts/test-ios-view.sh [simulator-udid]
# Exit:  xcodebuild's; 1 when there is no simulator to run on.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
example="$(cd "${script_dir}/../apps/example" && pwd)"

# Default to the first available iPhone simulator.
# `|| true` so a no-match grep doesn't exit before the message below.
udid="${1:-$(xcrun simctl list devices available | grep -m1 -oE 'iPhone[^(]*\(([0-9A-F-]{36})\)' | grep -oE '[0-9A-F-]{36}' || true)}"
if [[ -z "${udid}" ]]; then
  echo "FAIL: no available iPhone simulator" >&2
  exit 1
fi

cd "${example}"
# Xcode's "Generate Specs" phase misses library spec changes, so run Codegen.
bun run codegen:ios
xcodebuild test \
  -workspace ios/TurboImageExample.xcworkspace -scheme TurboImageExample \
  -configuration "${CONFIGURATION:-Debug}" -destination "id=${udid}" -derivedDataPath ios/build \
  -only-testing:TurboImageExampleTests
