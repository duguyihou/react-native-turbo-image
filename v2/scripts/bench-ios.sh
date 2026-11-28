#!/usr/bin/env bash
# Benchmarks TurboImage against expo-image (and optionally RN <Image>) on an
# iOS *simulator* with the apps/bench Release build: the iOS twin of
# bench-android.sh, with the same presets, run order and output format.
# Cold = reinstalled (no caches), warm = relaunched (disk cache kept).
#
# A simulator runs on the Mac's CPU, GPU and memory, with no device memory
# limit: its timings and memory are for spotting differences and
# regressions, not for claims about iPhones. Frame statistics are not
# collected here; on a device, use Instruments (see
# docs/benchmark/BENCHMARK_METHODOLOGY.md).
#
# Usage: scripts/bench-ios.sh [path/to/TurboImageBench.app] [simulator-udid]
# Env: LIBS, PRESETS, RUNS, CACHES as in bench-android.sh.
# Output: tmp/bench/ios-<timestamp>.jsonl, then bench-summary.py's tables.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
v2_root="$(cd "${script_dir}/.." && pwd)"
app="${1:-${v2_root}/apps/bench/ios/build/Build/Products/Release-iphonesimulator/TurboImageBench.app}"
bundle_id="com.turboimagebench"
read -r -a libs <<< "${LIBS:-turbo expo expoMem}"
presets="${PRESETS:-}"
runs="${RUNS:-5}"
caches="${CACHES:-cold warm}"
timeout_s=120

if [[ ! -d "${app}" ]]; then
  echo "FAIL: no app at ${app}; build it with: bun run --filter turbo-image-bench build:ios:release" >&2
  exit 1
fi

# The first booted iPhone simulator, unless one is given.
udid="${2:-$(xcrun simctl list devices booted | grep -m1 -oE 'iPhone[^(]*\(([0-9A-F-]{36})\)' | grep -oE '[0-9A-F-]{36}' || true)}"
if [[ -z "${udid}" ]]; then
  echo "FAIL: no booted iPhone simulator; boot one or pass its UDID" >&2
  exit 1
fi

# shellcheck source=./bench-common.sh source-path=SCRIPTDIR
source "${script_dir}/bench-common.sh"
presets="${presets:-${BENCH_ALL_PRESETS}}"
sampler_pid=""
log_pid=""
trap 'kill ${fixture_server_pid} ${sampler_pid} ${log_pid} 2> /dev/null || true' EXIT
start_fixture_server

device_json="$(xcrun simctl list devices -j | python3 -I -c '
import json, sys
udid = sys.argv[1]
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for d in devices:
        if d["udid"] == udid:
            os = runtime.rsplit(".", 1)[-1].replace("iOS-", "").replace("-", ".")
            print(json.dumps({"model": d["name"], "ios": os, "simulator": True}))
' "${udid}")"

out_dir="${v2_root}/tmp/bench"
mkdir -p "${out_dir}"
out="${out_dir}/ios-$(date +%Y%m%d-%H%M%S).jsonl"
samples="$(mktemp "${out_dir}/footprint-samples.XXXXXX")"
log_file="$(mktemp "${out_dir}/ios-log.XXXXXX")"

# Waits for the first app log line that contains $1 and prints it.
wait_for_log() {
  local marker="$1" line elapsed
  for ((elapsed = 0; elapsed < timeout_s * 4; elapsed++)); do
    line="$(grep -o "${marker}.*" "${log_file}" | head -n 1 || true)"
    if [[ -n "${line}" ]]; then
      echo "${line}"
      return 0
    fi
    sleep 0.25
  done
  return 1
}

app_pid() {
  xcrun simctl spawn "${udid}" launchctl list | awk -v id="${bundle_id}" '$3 ~ id { print $1; exit }'
}

# The app's phys_footprint in bytes (what jetsam counts on a device).
footprint_bytes() {
  footprint -p "$1" -f bytes --noCategories 2> /dev/null |
    awk '/Footprint:/ { for (i = 1; i <= NF; i++) if ($i == "Footprint:") { print $(i + 1); exit } }'
}

start_memory_sampler() {
  local pid="$1"
  : > "${samples}"
  (
    while kill -0 "${pid}" 2> /dev/null; do
      footprint_bytes "${pid}" >> "${samples}" || true
      sleep 0.5
    done
  ) &
  sampler_pid=$!
}

stop_memory_sampler() {
  local pid="$1" end_bytes
  end_bytes="$(footprint_bytes "${pid}" || true)"
  kill "${sampler_pid}" 2> /dev/null || true
  wait "${sampler_pid}" 2> /dev/null || true
  sampler_pid=""
  awk -v end="${end_bytes:-0}" '
    $1 ~ /^[0-9]+$/ { n++; if ($1 > peak) peak = $1 }
    END { printf "{\"kind\":\"footprint\",\"peakKb\":%s,\"endKb\":%s,\"samples\":%d}",
      (n ? int(peak / 1024) : "null"), (end ? int(end / 1024) : "null"), n }' "${samples}"
}

run_once() {
  local lib="$1" preset="$2" cache="$3" iteration="$4"
  local query result memory before after pid offline=false

  query="$(bench_preset_query "${preset}")"
  if [[ "${preset}" == "offline" ]]; then
    if ! bench_can_stop_server; then
      echo "SKIP: offline needs a fixture server this script started; stop the running one" >&2
      return 1
    fi
    offline=true
  fi

  xcrun simctl terminate "${udid}" "${bundle_id}" 2> /dev/null || true
  if [[ "${cache}" == "cold" ]]; then
    xcrun simctl uninstall "${udid}" "${bundle_id}" 2> /dev/null || true
    xcrun simctl install "${udid}" "${app}"
  fi

  if [[ "${offline}" == true ]]; then
    bench_stop_server
    before='{"count":0,"conditional":0,"aborted":0}'
  else
    before="$(bench_server_hits)"
  fi

  : > "${log_file}"
  xcrun simctl spawn "${udid}" log stream --style compact \
    --predicate 'eventMessage CONTAINS "TURBOIMAGE_BENCH"' > "${log_file}" 2>&1 &
  log_pid=$!
  # `-launchURL`: App.tsx reads it through RN's Settings (`simctl openurl`
  # would wait for a confirmation tap).
  xcrun simctl launch "${udid}" "${bundle_id}" -launchURL "turboimagebench://run?lib=${lib}&${query}" > /dev/null
  pid="$(app_pid)"
  start_memory_sampler "${pid}"

  local failed=""
  if ! wait_for_log 'TURBOIMAGE_BENCH_READY' > /dev/null; then
    failed="never became ready"
  elif [[ "${offline}" == true ]]; then
    if ! wait_for_log 'TURBOIMAGE_BENCH_OFFLINE' > /dev/null; then
      failed="the images never all failed"
    fi
    start_fixture_server
  fi
  if [[ -z "${failed}" ]] && ! result="$(wait_for_log 'TURBOIMAGE_BENCH {')"; then
    failed="logged no result within ${timeout_s}s"
  fi
  memory="$(stop_memory_sampler "${pid}")"
  kill "${log_pid}" 2> /dev/null || true
  log_pid=""
  if [[ -n "${failed}" ]]; then
    [[ "${offline}" == true ]] && ! curl -s -m 1 -o /dev/null "http://127.0.0.1:${fixture_server_port}/__ping" && start_fixture_server
    echo "FAIL: ${lib} ${preset} ${cache}: ${failed}" >&2
    return 1
  fi
  after="$(bench_server_hits)"

  printf '{"platform":"ios","device":%s,"preset":"%s","lib":"%s","cache":"%s","iteration":%s,"memory":%s,"gfx":null,"serverBefore":%s,"serverAfter":%s,"app":%s}\n' \
    "${device_json}" "${preset}" "${lib}" "${cache}" "${iteration}" "${memory}" \
    "${before}" "${after}" "${result#TURBOIMAGE_BENCH }" >> "${out}"
  echo "  ${preset} ${lib} ${cache}: done"
}

echo "device ${device_json}"
echo "writing ${out}"
xcrun simctl uninstall "${udid}" "${bundle_id}" 2> /dev/null || true
xcrun simctl install "${udid}" "${app}"
for ((iteration = 1; iteration <= runs; iteration++)); do
  echo "iteration ${iteration}/${runs}"
  for preset in ${presets}; do
    bench_preset_query "${preset}" > /dev/null || {
      echo "FAIL: unknown preset ${preset}" >&2
      exit 1
    }
    read -r -a order <<< "$(bench_lib_order "${iteration}" "${libs[@]}")"
    for lib in "${order[@]}"; do
      for cache in ${caches}; do
        run_once "${lib}" "${preset}" "${cache}" "${iteration}" || true
      done
    done
  done
done
xcrun simctl terminate "${udid}" "${bundle_id}" 2> /dev/null || true
rm -f "${samples}" "${log_file}"

python3 "${script_dir}/bench-summary.py" "${out}"
