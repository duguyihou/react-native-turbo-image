#!/usr/bin/env bash
# Starts fixture-server.py. Sourced by the smoke, bench and test scripts.
#
# Usage: start_fixture_server
# Sets:  fixture_server_pid  pid of the started server; empty if one was
#                            already running (it is reused)
#        fixture_server_log  its request log (empty with the pid)
# The caller kills ${fixture_server_pid} in its EXIT trap.

# Must match BASE in apps/example/src/fixtures.ts.
fixture_server_port=8765
fixture_server_pid=""
fixture_server_log=""

start_fixture_server() {
  local script_dir v2_root url
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  v2_root="$(cd "${script_dir}/.." && pwd)"
  url="http://127.0.0.1:${fixture_server_port}/__ping"

  # Only the fixture server answers /__ping with "ok"; fail on anything else.
  local reply
  reply="$(curl -s -m 2 "${url}" || true)"
  if [[ "${reply}" == "ok" ]]; then
    return 0
  fi
  if [[ -n "${reply}" ]] || curl -s -o /dev/null -m 2 "${url}"; then
    echo "FAIL: port ${fixture_server_port} is taken by something that is not the fixture server" >&2
    return 1
  fi

  fixture_server_log="${v2_root}/tmp/fixture-server.log"
  python3 "${script_dir}/fixture-server.py" \
    --port "${fixture_server_port}" --log "${fixture_server_log}" &
  fixture_server_pid=$!
  # So the caller's `kill` does not print "Terminated".
  disown "${fixture_server_pid}"

  local attempt
  for ((attempt = 0; attempt < 50; attempt++)); do
    if [[ "$(curl -s -m 2 "${url}" || true)" == "ok" ]]; then
      return 0
    fi
    # Stop waiting if the server already exited.
    kill -0 "${fixture_server_pid}" 2> /dev/null || break
    sleep 0.1
  done
  echo "FAIL: fixture server did not start on port ${fixture_server_port}" >&2
  return 1
}
