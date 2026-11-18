#!/usr/bin/env bash
# Starts scripts/fixture-server.py for a smoke run. Sourced by
# smoke-{ios,android}.sh.
#
# Usage: start_fixture_server
# Sets:  fixture_server_pid  the server this call started. Empty if one was
#                            already listening: that one is left running, so
#                            two smoke runs can share it. The app keeps their
#                            request counts apart with a per-run path.
#        fixture_server_log  the request log of the server this call started
#                            (empty with the pid), for the caller to print
#                            when the run fails
#
# The caller owns the cleanup: kill ${fixture_server_pid} in its EXIT trap.

# Must match BASE in apps/example/App.tsx.
fixture_server_port=8765
fixture_server_pid=""
fixture_server_log=""

start_fixture_server() {
  local script_dir v2_root url
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  v2_root="$(cd "${script_dir}/.." && pwd)"
  url="http://127.0.0.1:${fixture_server_port}/__ping"

  # Only this server answers /__ping with "ok". Anything else on the port
  # would serve the app 404s, and every scenario would fail for a reason that
  # has nothing to do with the app.
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
  # Out of the job table, so the caller's `kill` at exit is not reported as
  # "Terminated" in the smoke output.
  disown "${fixture_server_pid}"

  local attempt
  for ((attempt = 0; attempt < 50; attempt++)); do
    if [[ "$(curl -s -m 2 "${url}" || true)" == "ok" ]]; then
      return 0
    fi
    # Exited already: the port is taken by something else, or python3 is
    # missing. Waiting longer would only hide the real message above.
    kill -0 "${fixture_server_pid}" 2> /dev/null || break
    sleep 0.1
  done
  echo "FAIL: fixture server did not start on port ${fixture_server_port}" >&2
  return 1
}
