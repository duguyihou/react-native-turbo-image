#!/usr/bin/env bash
# On-device smoke test for the Android example (release / R8 build).
#
# Installs the APK on the connected device or emulator with cleared app
# data (so caches start cold), launches it, and waits for the single
# `TURBOIMAGE_SMOKE {...}` line App.tsx logs once every scenario settles.
#
# The app loads its fixtures from scripts/fixture-server.py, started here on
# the host. `adb reverse` maps the device's localhost port to the host's, so
# the app uses the same URLs as on the iOS simulator.
#
# Env: SMOKE_SCREENSHOT=<png path> saves a screenshot after the run.
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
assert_fresh_build "${apk}" android "${apk}.sources-sha256"

adb="${ANDROID_HOME:-${HOME}/Library/Android/sdk}/platform-tools/adb"
if [[ ! -x "${adb}" ]]; then
  adb="adb"
fi

# shellcheck source=./fixture-server.sh source-path=SCRIPTDIR
source "${script_dir}/fixture-server.sh"
trap 'kill ${fixture_server_pid} 2> /dev/null || true' EXIT
start_fixture_server

"${adb}" wait-for-device
"${adb}" reverse "tcp:${fixture_server_port}" "tcp:${fixture_server_port}" > /dev/null
"${adb}" install -r "${apk}" > /dev/null
# Cold caches every run: the cacheMiss scenario depends on it.
"${adb}" shell pm clear "${package}" > /dev/null
"${adb}" logcat -c
"${adb}" shell am start -n "${package}/.MainActivity" > /dev/null

# Keeps what a failed run leaves on the device. The suite fails now and then
# for reasons outside the app (once: cache files vanishing under it on an
# emulator at 94% of /data), and `logcat -c` at the next run erases the
# evidence. Free space is recorded because Android empties app caches when
# /data runs low.
save_failure_log() {
  local out
  out="${v2_root}/tmp/smoke-android-failure-$(date +%Y%m%d-%H%M%S).log"
  mkdir -p "${v2_root}/tmp"
  {
    echo "${line:-no TURBOIMAGE_SMOKE line}"
    "${adb}" shell df /data
    "${adb}" shell dumpsys devicestoragemonitor
    "${adb}" logcat -d
  } > "${out}" 2>&1 || true
  echo "device log saved to ${out}" >&2
}

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
  save_failure_log
  exit 1
fi

echo "${line}"
# Optional: capture what the smoke run left on screen (placeholders must
# still be visible on the failing scenarios).
if [[ -n "${SMOKE_SCREENSHOT:-}" ]]; then
  "${adb}" exec-out screencap -p > "${SMOKE_SCREENSHOT}" || true
fi
if [[ "${line}" == *'"pass":true'* ]]; then
  echo "PASS (android)"
else
  echo "FAIL (android)" >&2
  # What the fixture server received says whether a failing load reached the
  # host at all, and with which headers. A server that was already running
  # logs wherever it was told to, not here.
  if [[ -n "${fixture_server_log}" ]]; then
    echo "last requests seen by the fixture server (${fixture_server_log}):" >&2
    tail -n 25 "${fixture_server_log}" >&2 || true
  fi
  save_failure_log
  exit 1
fi
