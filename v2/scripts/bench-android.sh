#!/usr/bin/env bash
# Image library benchmark on Android: TurboImage vs expo-image
# vs React Native's <Image>, using the release build of apps/bench.
#
# For every iteration, scenario and library, this runs the app twice:
#   cold  app data cleared first (`pm clear`), so memory and disk caches
#         are empty and every image is downloaded
#   warm  relaunched without clearing: memory caches died with the process,
#         disk caches are as the cold run left them
# Libraries are interleaved within each iteration (turbo, expo, ... then
# again) rather than run in blocks, so a phone heating up over the session
# slows all of them alike instead of whichever went last.
#
# Each run records the app's TURBOIMAGE_BENCH line (load times from mount),
# the app's total PSS when the scenario ends, and, for `grid`, frame stats
# from `dumpsys gfxinfo` over the scrolling only.
#
# Run it on a physical device with the screen on and unlocked. Emulator
# frame times say little about phones.
#
# Env:
#   LIBS       libraries to compare (default: "turbo expo rn")
#   SCENARIOS  scenario:source pairs
#              (default: "load:photo load:large grid:photo grid:large")
#   RUNS       iterations (default: 5)
#   COUNT      images in the `load` scenario (default: the app's, 30)
# Usage: scripts/bench-android.sh [path/to/app-release.apk]
# Output: tmp/bench/android-<timestamp>.jsonl, then a summary table from
#         scripts/bench-summary.py.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
v2_root="$(cd "${script_dir}/.." && pwd)"
apk="${1:-${v2_root}/apps/bench/android/app/build/outputs/apk/release/app-release.apk}"
package="com.turboimagebench"
libs="${LIBS:-turbo expo rn}"
scenarios="${SCENARIOS:-load:photo load:large grid:photo grid:large}"
runs="${RUNS:-5}"
count_param="${COUNT:+&n=${COUNT}}"
timeout_s=120

if [[ ! -f "${apk}" ]]; then
  echo "FAIL: no APK at ${apk}; build it with: bun run --filter turbo-image-bench build:android:release" >&2
  exit 1
fi

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
"${adb}" uninstall "${package}" > /dev/null 2>&1 || true
"${adb}" install "${apk}" > /dev/null

out_dir="${v2_root}/tmp/bench"
mkdir -p "${out_dir}"
out="${out_dir}/android-$(date +%Y%m%d-%H%M%S).jsonl"

# Waits for the first app log line that contains $1 and prints it.
wait_for_log() {
  local marker="$1" line elapsed
  for ((elapsed = 0; elapsed < timeout_s * 4; elapsed++)); do
    line="$("${adb}" logcat -d -s ReactNativeJS:V | grep -o "${marker}.*" | head -n 1 || true)"
    if [[ -n "${line}" ]]; then
      echo "${line}"
      return 0
    fi
    sleep 0.25
  done
  return 1
}

# Frame stats of the app's window since the last `gfxinfo reset`, as JSON.
# The first block of `dumpsys gfxinfo` is the app-wide one; later blocks
# repeat the stats per window.
gfx_json() {
  "${adb}" shell dumpsys gfxinfo "${package}" | awk '
    function num(s) { gsub(/[^0-9.]/, "", s); return s }
    /Total frames rendered:/ && !f { f = num($4) }
    /Janky frames:/ && !j        { j = num($3) }
    /^50th percentile:/ && !p50  { p50 = num($3) }
    /^90th percentile:/ && !p90  { p90 = num($3) }
    /^95th percentile:/ && !p95  { p95 = num($3) }
    /^99th percentile:/ && !p99  { p99 = num($3) }
    END { printf "{\"frames\":%s,\"janky\":%s,\"p50Ms\":%s,\"p90Ms\":%s,\"p95Ms\":%s,\"p99Ms\":%s}",
      f + 0, j + 0, p50 + 0, p90 + 0, p95 + 0, p99 + 0 }'
}

# The app's total PSS in KB. Newer Android prints "TOTAL PSS: n" in the App
# Summary; older prints a "TOTAL n ..." row.
pss_kb() {
  "${adb}" shell dumpsys meminfo "${package}" | awk '
    /TOTAL PSS:/ { print $3; found = 1; exit }
    /^ *TOTAL +[0-9]/ && !found { print $2; exit }'
}

run_once() {
  local lib="$1" scenario="$2" source="$3" cache="$4" iteration="$5"
  local result gfx="null" pss

  "${adb}" shell am force-stop "${package}"
  if [[ "${cache}" == "cold" ]]; then
    "${adb}" shell pm clear "${package}" > /dev/null
  fi
  "${adb}" logcat -c
  "${adb}" shell am start -a android.intent.action.VIEW \
    -d "'turboimagebench://run?lib=${lib}&scenario=${scenario}&source=${source}${count_param}'" \
    "${package}" > /dev/null

  if [[ "${scenario}" == "grid" ]]; then
    if ! wait_for_log 'TURBOIMAGE_BENCH_READY' > /dev/null; then
      echo "FAIL: ${lib} ${scenario}:${source} ${cache} never became ready" >&2
      return 1
    fi
    "${adb}" shell dumpsys gfxinfo "${package}" reset > /dev/null
  fi

  if ! result="$(wait_for_log 'TURBOIMAGE_BENCH {')"; then
    echo "FAIL: ${lib} ${scenario}:${source} ${cache} logged no result within ${timeout_s}s" >&2
    return 1
  fi
  if [[ "${scenario}" == "grid" ]]; then
    gfx="$(gfx_json)"
  fi
  pss="$(pss_kb)"

  printf '{"platform":"android","cache":"%s","iteration":%s,"pssKb":%s,"gfx":%s,"app":%s}\n' \
    "${cache}" "${iteration}" "${pss:-null}" "${gfx}" "${result#TURBOIMAGE_BENCH }" >> "${out}"
  echo "  ${lib} ${scenario}:${source} ${cache}: ${result#TURBOIMAGE_BENCH }"
}

echo "writing ${out}"
for ((iteration = 1; iteration <= runs; iteration++)); do
  echo "iteration ${iteration}/${runs}"
  for pair in ${scenarios}; do
    for lib in ${libs}; do
      # A failed run is reported and skipped: one library failing a
      # scenario should not throw away the others' results.
      run_once "${lib}" "${pair%%:*}" "${pair##*:}" cold "${iteration}" || true
      run_once "${lib}" "${pair%%:*}" "${pair##*:}" warm "${iteration}" || true
    done
  done
done
"${adb}" shell am force-stop "${package}"

python3 "${script_dir}/bench-summary.py" "${out}"
