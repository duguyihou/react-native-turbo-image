#!/usr/bin/env bash
# Runs the Nuke adapter's tests (ios/Tests) on an iPhone simulator. The
# package builds standalone, without an app or the Fabric view.
#
# Usage: scripts/test-ios-adapter.sh [simulator-udid]
# Exit:  xcodebuild's; 1 when there is no simulator to run on.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pkg="$(cd "${script_dir}/../packages/react-native-turbo-image" && pwd)"

# Default to the first available iPhone simulator.
# `|| true` so a no-match grep doesn't exit before the message below.
udid="${1:-$(xcrun simctl list devices available | grep -m1 -oE 'iPhone[^(]*\(([0-9A-F-]{36})\)' | grep -oE '[0-9A-F-]{36}' || true)}"
if [[ -z "${udid}" ]]; then
  echo "FAIL: no available iPhone simulator" >&2
  exit 1
fi

cd "${pkg}"
# Built standalone: an app build dir nearby would switch Package.swift to its
# in-app form, which has no tests.
xcodebuild test -scheme TurboImage -destination "id=${udid}"
