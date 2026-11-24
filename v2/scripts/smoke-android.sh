#!/usr/bin/env bash
# On-device smoke test for the Android example (release / R8 build).
# Reinstalls the APK (cold caches), serves fixtures via fixture-server.py and
# `adb reverse`, and waits for the `TURBOIMAGE_SMOKE {...}` line from App.tsx.
#
# Usage: scripts/smoke-android.sh [path/to/app.apk]
# Env: SMOKE_SCREENSHOT=<png path> saves a screenshot after the run.
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
# Uninstall rather than `install -r`: it also frees the old APK first, so a
# nearly full emulator /data doesn't fail the install or evict app caches.
# `|| true`: nothing to uninstall on a fresh device.
"${adb}" uninstall "${package}" > /dev/null 2>&1 || true
"${adb}" install "${apk}" > /dev/null
"${adb}" logcat -c
# The app opens on its Home screen; this link opens the smoke test instead
# (the intent filter in AndroidManifest.xml, read by App.tsx).
"${adb}" shell am start -a android.intent.action.VIEW \
  -d "turboimageexample://smoke" -n "${package}/.MainActivity" > /dev/null

# Saves the device log and free space on failure, since the next run's
# `logcat -c` erases it (low /data makes Android evict app caches).
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
# Optional screenshot (placeholders should show on the failing scenarios).
if [[ -n "${SMOKE_SCREENSHOT:-}" ]]; then
  "${adb}" exec-out screencap -p > "${SMOKE_SCREENSHOT}" || true
fi
if [[ "${line}" == *'"pass":true'* ]]; then
  echo "PASS (android)"
else
  echo "FAIL (android)" >&2
  # Show what reached the fixture server (only if this run started it).
  if [[ -n "${fixture_server_log}" ]]; then
    echo "last requests seen by the fixture server (${fixture_server_log}):" >&2
    tail -n 25 "${fixture_server_log}" >&2 || true
  fi
  save_failure_log
  exit 1
fi
