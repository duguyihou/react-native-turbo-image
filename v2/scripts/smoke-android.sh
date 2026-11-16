#!/usr/bin/env bash
# On-device smoke test for the Android example (release / R8 build).
#
# Installs the APK on the connected device or emulator with cleared app
# data (so caches start cold), launches it, and waits for the single
# `TURBOIMAGE_SMOKE {...}` line App.tsx logs once every scenario settles.
#
# Usage: scripts/smoke-android.sh [path/to/app.apk]
# Exit: 0 when the app reports pass=true, 1 otherwise (including timeout).

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
v2_root="$(cd "${script_dir}/.." && pwd)"
apk="${1:-${v2_root}/apps/example/android/app/build/outputs/apk/release/app-release.apk}"
package="com.turboimageexample"
timeout_s=120

# shellcheck source=./assert-fresh-build.sh source-path=SCRIPTDIR
source "${script_dir}/assert-fresh-build.sh"
assert_fresh_build "${apk}"

adb="${ANDROID_HOME:-${HOME}/Library/Android/sdk}/platform-tools/adb"
if [[ ! -x "${adb}" ]]; then
  adb="adb"
fi

"${adb}" wait-for-device
"${adb}" install -r "${apk}" > /dev/null
# Cold caches every run: the cacheMiss scenario depends on it.
"${adb}" shell pm clear "${package}" > /dev/null
"${adb}" logcat -c
"${adb}" shell am start -n "${package}/.MainActivity" > /dev/null

line=""
for ((elapsed = 0; elapsed < timeout_s; elapsed += 2)); do
  line="$("${adb}" logcat -d -s ReactNativeJS:V | grep -o 'TURBOIMAGE_SMOKE .*' || true)"
  if [[ -n "${line}" ]]; then
    break
  fi
  sleep 2
done

if [[ -z "${line}" ]]; then
  echo "FAIL: no TURBOIMAGE_SMOKE line within ${timeout_s}s" >&2
  "${adb}" logcat -d | grep -E 'FATAL|AndroidRuntime|turboimage' | tail -20 >&2 || true
  exit 1
fi

echo "${line}"
if [[ "${line}" == *'"pass":true'* ]]; then
  echo "PASS (android)"
else
  echo "FAIL (android)" >&2
  exit 1
fi
