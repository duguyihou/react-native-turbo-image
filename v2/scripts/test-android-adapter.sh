#!/usr/bin/env bash
# Runs the Coil adapter's instrumented tests
# (packages/react-native-turbo-image/android/src/androidTest) on the connected
# device or emulator.
#
# They drive the real adapter through the seam, with requests resolved by the
# real core and images served over HTTP by scripts/fixture-server.py: decode
# sizes, failure codes, cancel, progress, and the cache tiers, including the
# disk and HTTP caches the iOS adapter tests cannot reach (they load local
# files). The fixture server counts requests, which is how a cache hit is
# told from a fetch.
#
# Built through the example app's Gradle project, because the library only
# builds inside an app (android/build.gradle takes AGP, Kotlin and React
# Native from the host).
#
# Usage: scripts/test-android-adapter.sh
# Exit:  Gradle's; the report is under
#        packages/react-native-turbo-image/android/build/reports/androidTests/.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
v2_root="$(cd "${script_dir}/.." && pwd)"

adb="${ANDROID_HOME:-${HOME}/Library/Android/sdk}/platform-tools/adb"
if [[ ! -x "${adb}" ]]; then
  adb="adb"
fi

# shellcheck source=./fixture-server.sh source-path=SCRIPTDIR
source "${script_dir}/fixture-server.sh"
trap 'kill ${fixture_server_pid} 2> /dev/null || true' EXIT
start_fixture_server

"${adb}" wait-for-device
# The tests use the same URLs as the example app: the device's localhost,
# mapped to the host's where the server listens.
"${adb}" reverse "tcp:${fixture_server_port}" "tcp:${fixture_server_port}" > /dev/null

# Only the device's primary ABI: the test APK carries React Native's native
# libraries, and every extra ABI makes it larger to build and to install.
abi="$("${adb}" shell getprop ro.product.cpu.abi | tr -d '\r')"

cd "${v2_root}/apps/example/android"
./gradlew :react-native-turbo-image:connectedDebugAndroidTest \
  --console=plain -PreactNativeArchitectures="${abi}"
