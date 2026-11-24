#!/usr/bin/env bash
# Benchmarks TurboImage against expo-image (and optionally RN <Image>) on
# Android with the apps/bench release build. Each preset runs cold (`pm
# clear`: no disk cache) and warm (relaunch: disk cache kept, memory empty),
# RUNS times, libraries alternating. Use a physical device, screen on and
# unlocked, not charging if possible. Methodology:
# docs/benchmark/BENCHMARK_METHODOLOGY.md.
#
# Usage: scripts/bench-android.sh [path/to/app-release.apk]
# Env:
#   LIBS     libraries (default: "turbo expo expoMem"; add "rn" for RN <Image>).
#            expoMem is expo-image with cachePolicy="memory-disk" (see adapters.tsx)
#   PRESETS  presets from bench-common.sh (default: all)
#   RUNS     iterations (default: 5)
#   CACHES   cache states (default: "cold warm")
# Output: tmp/bench/android-<timestamp>.jsonl (one line per run), then
# bench-summary.py's tables.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
v2_root="$(cd "${script_dir}/.." && pwd)"
apk="${1:-${v2_root}/apps/bench/android/app/build/outputs/apk/release/app-release.apk}"
package="com.turboimagebench"
read -r -a libs <<< "${LIBS:-turbo expo expoMem}"
presets="${PRESETS:-}"
runs="${RUNS:-5}"
caches="${CACHES:-cold warm}"
timeout_s=120

if [[ ! -f "${apk}" ]]; then
  echo "FAIL: no APK at ${apk}; build it with: bun run --filter turbo-image-bench build:android:release" >&2
  exit 1
fi

adb="${ANDROID_HOME:-${HOME}/Library/Android/sdk}/platform-tools/adb"
if [[ ! -x "${adb}" ]]; then
  adb="adb"
fi

# shellcheck source=./bench-common.sh source-path=SCRIPTDIR
source "${script_dir}/bench-common.sh"
presets="${presets:-${BENCH_ALL_PRESETS}}"
sampler_pid=""
trap 'kill ${fixture_server_pid} ${sampler_pid} 2> /dev/null || true' EXIT
start_fixture_server

"${adb}" wait-for-device
"${adb}" reverse "tcp:${fixture_server_port}" "tcp:${fixture_server_port}" > /dev/null
"${adb}" uninstall "${package}" > /dev/null 2>&1 || true
"${adb}" install "${apk}" > /dev/null

# What the results were measured on, recorded with every row.
device_json="$(printf '{"model":"%s","android":"%s","sdk":"%s","emulator":%s}' \
  "$("${adb}" shell getprop ro.product.model | tr -d '\r')" \
  "$("${adb}" shell getprop ro.build.version.release | tr -d '\r')" \
  "$("${adb}" shell getprop ro.build.version.sdk | tr -d '\r')" \
  "$([[ "$("${adb}" shell getprop ro.kernel.qemu | tr -d '\r')" == "1" ]] && echo true || echo false)")"

out_dir="${v2_root}/tmp/bench"
mkdir -p "${out_dir}"
out="${out_dir}/android-$(date +%Y%m%d-%H%M%S).jsonl"
samples="$(mktemp "${out_dir}/pss-samples.XXXXXX")"

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

# Frame stats since the last `gfxinfo reset`, as JSON. Only the first
# (app-wide) block of `dumpsys gfxinfo` is read.
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

# The app's total PSS in KB ("TOTAL PSS: n" on newer Android, "TOTAL n" on older).
pss_kb() {
  "${adb}" shell dumpsys meminfo "${package}" 2> /dev/null | awk '
    /TOTAL PSS:/ { print $3; found = 1; exit }
    /^ *TOTAL +[0-9]/ && !found { print $2; exit }'
}

# Samples PSS into ${samples} until killed. One `dumpsys meminfo` takes
# 0.3-1 s, so this is about one sample a second; the peak is the highest
# sample, not the true peak between samples.
start_memory_sampler() {
  : > "${samples}"
  (
    while true; do
      pss_kb >> "${samples}" || true
    done
  ) &
  sampler_pid=$!
}

stop_memory_sampler() {
  kill "${sampler_pid}" 2> /dev/null || true
  wait "${sampler_pid}" 2> /dev/null || true
  sampler_pid=""
  local end_kb
  end_kb="$(pss_kb)"
  awk -v end="${end_kb:-0}" '
    $1 ~ /^[0-9]+$/ { n++; if ($1 > peak) peak = $1 }
    END { printf "{\"kind\":\"pss\",\"peakKb\":%s,\"endKb\":%s,\"samples\":%d}",
      (n ? peak : "null"), (end ? end : "null"), n }' "${samples}"
}

run_once() {
  local lib="$1" preset="$2" cache="$3" iteration="$4"
  local query result gfx="null" memory before after offline=false

  query="$(bench_preset_query "${preset}")"
  if [[ "${preset}" == "offline" ]]; then
    if ! bench_can_stop_server; then
      echo "SKIP: offline needs a fixture server this script started; stop the running one" >&2
      return 1
    fi
    offline=true
  fi

  "${adb}" shell am force-stop "${package}"
  if [[ "${cache}" == "cold" ]]; then
    "${adb}" shell pm clear "${package}" > /dev/null
  fi
  "${adb}" logcat -c

  if [[ "${offline}" == true ]]; then
    bench_stop_server
    before='{"count":0,"conditional":0,"aborted":0}'
  else
    before="$(bench_server_hits)"
  fi

  "${adb}" shell am start -a android.intent.action.VIEW \
    -d "'turboimagebench://run?lib=${lib}&${query}'" "${package}" > /dev/null
  start_memory_sampler

  if ! wait_for_log 'TURBOIMAGE_BENCH_READY' > /dev/null; then
    stop_memory_sampler > /dev/null
    echo "FAIL: ${lib} ${preset} ${cache} never became ready" >&2
    [[ "${offline}" == true ]] && start_fixture_server
    return 1
  fi
  "${adb}" shell dumpsys gfxinfo "${package}" reset > /dev/null

  if [[ "${offline}" == true ]]; then
    if ! wait_for_log 'TURBOIMAGE_BENCH_OFFLINE' > /dev/null; then
      stop_memory_sampler > /dev/null
      echo "FAIL: ${lib} offline ${cache}: the images never all failed" >&2
      start_fixture_server
      return 1
    fi
    start_fixture_server
    "${adb}" reverse "tcp:${fixture_server_port}" "tcp:${fixture_server_port}" > /dev/null
  fi

  if ! result="$(wait_for_log 'TURBOIMAGE_BENCH {')"; then
    stop_memory_sampler > /dev/null
    echo "FAIL: ${lib} ${preset} ${cache} logged no result within ${timeout_s}s" >&2
    return 1
  fi
  gfx="$(gfx_json)"
  memory="$(stop_memory_sampler)"
  after="$(bench_server_hits)"

  printf '{"platform":"android","device":%s,"preset":"%s","lib":"%s","cache":"%s","iteration":%s,"memory":%s,"gfx":%s,"serverBefore":%s,"serverAfter":%s,"app":%s}\n' \
    "${device_json}" "${preset}" "${lib}" "${cache}" "${iteration}" "${memory}" "${gfx}" \
    "${before}" "${after}" "${result#TURBOIMAGE_BENCH }" >> "${out}"
  echo "  ${preset} ${lib} ${cache}: done"
}

echo "device ${device_json}"
echo "writing ${out}"
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
        # A failed run is skipped so the other libraries' results are kept.
        run_once "${lib}" "${preset}" "${cache}" "${iteration}" || true
      done
    done
  done
done
"${adb}" shell am force-stop "${package}"
rm -f "${samples}"

python3 "${script_dir}/bench-summary.py" "${out}"
