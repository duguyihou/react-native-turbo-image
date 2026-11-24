#!/usr/bin/env bash
# Serves the example app's images (fixture-server.py) in the foreground, for
# running the example by hand. The smoke and bench scripts start their own.
# Also forwards the port to every attached Android device or emulator, so
# the app's http://localhost:8765 reaches this machine.
#
# Usage: scripts/serve-fixtures.sh [--host 0.0.0.0]
#   --host 0.0.0.0 also serves the LAN (a physical iPhone; see
#   apps/example/src/fixtures.ts). Stop with Ctrl-C.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./fixture-server.sh source-path=SCRIPTDIR
source "${script_dir}/fixture-server.sh"

adb="${ANDROID_HOME:-${HOME}/Library/Android/sdk}/platform-tools/adb"
if [[ ! -x "${adb}" ]]; then
  adb="$(command -v adb || true)"
fi
if [[ -n "${adb}" ]]; then
  # `adb devices` lists "<serial>\tdevice" for each usable one.
  while read -r serial state; do
    if [[ "${state}" == "device" ]]; then
      "${adb}" -s "${serial}" reverse "tcp:${fixture_server_port}" "tcp:${fixture_server_port}" > /dev/null
      echo "adb reverse tcp:${fixture_server_port} on ${serial}"
    fi
  done < <("${adb}" devices | tail -n +2)
fi

echo "serving fixtures on port ${fixture_server_port} (Ctrl-C to stop)"
exec python3 "${script_dir}/fixture-server.py" --port "${fixture_server_port}" "$@"
