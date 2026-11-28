#!/usr/bin/env bash
# Runs a build and, on success, writes <artifact-path>.sources-sha256 with
# the sources' fingerprint for assert-fresh-build.sh. The fingerprint is
# taken before the build, so edits made during it are not credited.
#
# Usage: scripts/build-stamped.sh <ios|android> <artifact-path> -- <build command...>
# Exit: 2 on bad usage, else the build's status.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./assert-fresh-build.sh source-path=SCRIPTDIR
source "${script_dir}/assert-fresh-build.sh"

platform="$1"
artifact="$2"
if [[ "${3:-}" != "--" || $# -lt 4 ]]; then
  echo "usage: build-stamped.sh <ios|android> <artifact-path> -- <build command...>" >&2
  exit 2
fi
shift 3

stamp="${artifact}.sources-sha256"
# A failed build must not leave the previous build's stamp behind.
rm -f "${stamp}"
fingerprint="$(source_fingerprint "${platform}")"

"$@"

echo "${fingerprint}" > "${stamp}"
