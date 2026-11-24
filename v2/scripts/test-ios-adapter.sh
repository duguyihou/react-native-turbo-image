#!/usr/bin/env bash
# Runs the Nuke adapter's tests (packages/react-native-turbo-image/ios/Tests)
# on an iPhone simulator.
#
# They drive the adapter through the seam with local files: decode sizes,
# failure codes, the memory cache, SVG, and animated images, which no load
# event reports and the on-device smoke suite therefore cannot see. They need
# UIKit, hence a simulator, but no app: the package is built standalone,
# without the Fabric view.
#
# Usage: scripts/test-ios-adapter.sh [simulator-udid]
# Exit:  xcodebuild's; 1 when there is no simulator to run on.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pkg="$(cd "${script_dir}/../packages/react-native-turbo-image" && pwd)"

# Default to the first available iPhone simulator, as smoke-ios.sh does.
# `|| true`: with no match grep fails, and under `set -e -o pipefail` that
# would end the script here, before the message below.
udid="${1:-$(xcrun simctl list devices available | grep -m1 -oE 'iPhone[^(]*\(([0-9A-F-]{36})\)' | grep -oE '[0-9A-F-]{36}' || true)}"
if [[ -z "${udid}" ]]; then
  echo "FAIL: no available iPhone simulator" >&2
  exit 1
fi

cd "${pkg}"
# Standalone: without it, a React Native app's build directory next to the
# package would switch the manifest to its in-app form, which has no tests.
xcodebuild test -scheme TurboImage -destination "id=${udid}"
