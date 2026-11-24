#!/usr/bin/env bash
# Runs the Coil adapter's instrumented tests (android/src/androidTest) on the
# connected device, against fixture-server.py. Built through the example
# app's Gradle project, since the library only builds inside an app.
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
# Map the device's localhost port to the host's fixture server.
"${adb}" reverse "tcp:${fixture_server_port}" "tcp:${fixture_server_port}" > /dev/null

# Build only the device's ABI to keep the test APK small.
abi="$("${adb}" shell getprop ro.product.cpu.abi | tr -d '\r')"

cd "${v2_root}/apps/example/android"
./gradlew :react-native-turbo-image:connectedDebugAndroidTest \
  --console=plain -PreactNativeArchitectures="${abi}"
