#!/usr/bin/env bash
# On-device smoke test for the iOS example (Release, simulator).
#
# Reinstalls the app (uninstalling first wipes its caches), launches it, and
# waits for the `TURBOIMAGE_SMOKE {...}` line App.tsx logs once every
# scenario settles. In Release, React Native forwards console.error to
# os_log, which is where we read it from.
#
# The app loads its fixtures from scripts/fixture-server.py, started here on
# the host; the simulator shares the host's loopback interface.
#
# Env: SMOKE_SCREENSHOT=<png path> saves a screenshot after the run.
# Usage: scripts/smoke-ios.sh [path/to/App.app] [simulator-udid]
# Exit: 0 when the app reports pass=true, 1 otherwise (including timeout).

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
v2_root="$(cd "${script_dir}/.." && pwd)"
app="${1:-${v2_root}/apps/example/ios/build/Build/Products/Release-iphonesimulator/TurboImageExample.app}"
bundle_id="org.reactjs.native.example.TurboImageExample"
timeout_s=120

# shellcheck source=./assert-fresh-build.sh source-path=SCRIPTDIR
source "${script_dir}/assert-fresh-build.sh"
# An .app directory's mtime does not change when Xcode rewrites files inside
# it, so compare against whichever of the executable and the JS bundle was
# written last (a JS-only change re-bundles without relinking, and vice versa).
newest_artifact="${app}/TurboImageExample"
if [[ "${app}/main.jsbundle" -nt "${newest_artifact}" ]]; then
  newest_artifact="${app}/main.jsbundle"
fi
assert_fresh_build "${newest_artifact}" ios "${app}.sources-sha256"

# shellcheck source=./fixture-server.sh source-path=SCRIPTDIR
source "${script_dir}/fixture-server.sh"
log_pid=""
trap 'kill ${log_pid} ${fixture_server_pid} 2> /dev/null || true' EXIT
start_fixture_server

# Default to the first available iPhone simulator.
# `|| true`: with no match grep fails, and under `set -e -o pipefail` that
# would end the script here, before the message below.
udid="${2:-$(xcrun simctl list devices available | grep -m1 -oE 'iPhone[^(]*\(([0-9A-F-]{36})\)' | grep -oE '[0-9A-F-]{36}' || true)}"
if [[ -z "${udid}" ]]; then
  echo "FAIL: no available iPhone simulator" >&2
  exit 1
fi

xcrun simctl boot "${udid}" 2> /dev/null || true
xcrun simctl bootstatus "${udid}" -b > /dev/null
xcrun simctl uninstall "${udid}" "${bundle_id}" 2> /dev/null || true
xcrun simctl install "${udid}" "${app}"

log_file="$(mktemp "${v2_root}/tmp-smoke-ios.XXXXXX")"
trap 'kill ${log_pid} ${fixture_server_pid} 2> /dev/null || true; rm -f "${log_file}"' EXIT
xcrun simctl spawn "${udid}" log stream --style compact \
  --predicate 'eventMessage CONTAINS "TURBOIMAGE_SMOKE"' > "${log_file}" 2>&1 &
log_pid=$!

xcrun simctl launch "${udid}" "${bundle_id}" > /dev/null

line=""
for ((elapsed = 0; elapsed < timeout_s; elapsed += 2)); do
  line="$(grep -o 'TURBOIMAGE_SMOKE .*' "${log_file}" || true)"
  if [[ -n "${line}" ]]; then
    break
  fi
  sleep 2
done

if [[ -z "${line}" ]]; then
  echo "FAIL: no TURBOIMAGE_SMOKE line within ${timeout_s}s" >&2
  exit 1
fi

echo "${line}"
# Optional: capture what the smoke run left on screen (placeholders must
# still be visible on the failing scenarios).
if [[ -n "${SMOKE_SCREENSHOT:-}" ]]; then
  xcrun simctl io "${udid}" screenshot "${SMOKE_SCREENSHOT}" > /dev/null 2>&1 || true
fi
if [[ "${line}" == *'"pass":true'* ]]; then
  echo "PASS (ios)"
else
  echo "FAIL (ios)" >&2
  # What the fixture server received says whether a failing load reached the
  # host at all, and with which headers. A server that was already running
  # logs wherever it was told to, not here.
  if [[ -n "${fixture_server_log}" ]]; then
    echo "last requests seen by the fixture server (${fixture_server_log}):" >&2
    tail -n 25 "${fixture_server_log}" >&2 || true
  fi
  # Keep the result: callers often filter this script's output, and the next
  # run reinstalls the app. (The log stream above is filtered to the result
  # line, so there is no wider device log to save, unlike on Android.)
  failure_log="${v2_root}/tmp/smoke-ios-failure-$(date +%Y%m%d-%H%M%S).log"
  mkdir -p "${v2_root}/tmp"
  echo "${line}" > "${failure_log}"
  echo "result saved to ${failure_log}" >&2
  exit 1
fi
