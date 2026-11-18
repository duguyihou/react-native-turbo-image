#!/usr/bin/env bash
# Runs a build and, if it succeeds, records which sources it was built from.
#
# The stamp is what lets assert-fresh-build.sh recognise an artifact as
# current by content rather than by modification time. The fingerprint is
# taken before the build starts, so an edit made while it runs cannot be
# credited to an artifact that does not contain it.
#
# Usage: scripts/build-stamped.sh <ios|android> <artifact-path> -- <build command...>
# The stamp is written next to the artifact, as <artifact-path>.sources-sha256.

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
