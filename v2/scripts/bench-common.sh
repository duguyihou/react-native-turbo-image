#!/usr/bin/env bash
# Shared by bench-android.sh and bench-ios.sh: the scenario presets, the
# fixture server's request counts and its stop/start for `offline`, and the
# order of runs. Sourced, not run.
#
# Methodology: docs/benchmark/BENCHMARK_METHODOLOGY.md.

# shellcheck source=./fixture-server.sh source-path=SCRIPTDIR
source "$(dirname "${BASH_SOURCE[0]}")/fixture-server.sh"

# Every preset, in run order. A preset is one scenario with fixed
# parameters, runnable on its own (PRESETS="cancel offline").
# shellcheck disable=SC2034 # read by the scripts that source this file
BENCH_ALL_PRESETS="load-100 load-500 load-1000 grid-paced grid-fast repeated remount cancel pressure offline"

# Prints a preset's deep-link query, without `lib`. Unknown preset: exit 1.
bench_preset_query() {
  case "$1" in
    # N images mounted at once.
    load-100) echo "scenario=load&n=100&source=photo" ;;
    load-500) echo "scenario=load&n=500&source=photo" ;;
    load-1000) echo "scenario=load&n=1000&source=photo" ;;
    # A 900-image FlashList grid scrolled by the app: a screen per 300 ms
    # (animated), or a screen per frame.
    grid-paced) echo "scenario=grid&n=900&speed=paced&source=photo" ;;
    grid-fast) echo "scenario=grid&n=900&speed=fast&source=photo" ;;
    # The fast grid over 12 URLs repeated: request reuse.
    repeated) echo "scenario=grid&n=900&speed=fast&source=photo&urls=repeated" ;;
    # One screen mounted and unmounted 20 times, then mounted for good.
    remount) echo "scenario=remount&source=photo" ;;
    # A screen of 2 s downloads abandoned by a jump to the list's end.
    cancel) echo "scenario=cancel&source=slow" ;;
    # The fast grid over 900 distinct 3000×2000 JPEGs: memory pressure.
    pressure) echo "scenario=grid&n=900&speed=fast&source=large" ;;
    # The server down at launch, started again once every image failed.
    offline) echo "scenario=offline&source=photo" ;;
    *) return 1 ;;
  esac
}

# The fixture server's request counts summed over every path, as JSON.
# Each run records the counts before and after; the summary takes the
# difference. Only the app under test talks to the server during a run.
bench_server_hits() {
  curl -s -m 5 "http://127.0.0.1:${fixture_server_port}/__hits?prefix=/" ||
    echo '{"count":null,"conditional":null,"aborted":null}'
}

# `offline` needs a server this script started, so it can stop it.
bench_can_stop_server() {
  [[ -n "${fixture_server_pid}" ]]
}

bench_stop_server() {
  kill "${fixture_server_pid}" 2> /dev/null || true
  local attempt
  for ((attempt = 0; attempt < 50; attempt++)); do
    curl -s -o /dev/null -m 1 "http://127.0.0.1:${fixture_server_port}/__ping" || return 0
    sleep 0.1
  done
  echo "FAIL: the fixture server did not stop" >&2
  return 1
}

# Libraries in alternating order per iteration (ABAB, then BABA), so a
# device warming up or throttling over the session affects each alike.
bench_lib_order() {
  local iteration="$1"
  shift
  local -a libs=("$@")
  if ((iteration % 2 == 0)); then
    local -a reversed=()
    local i
    for ((i = ${#libs[@]} - 1; i >= 0; i--)); do
      reversed+=("${libs[i]}")
    done
    libs=("${reversed[@]}")
  fi
  echo "${libs[*]}"
}
