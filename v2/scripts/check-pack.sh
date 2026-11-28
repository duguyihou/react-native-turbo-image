#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
#
# `prepack` guard: refuses to pack without the gitignored vendored Nuke
# xcframeworks at the pinned version (RFC rule 6). It only checks; building
# needs Xcode and is too slow to run inside `npm pack`.
#
# Usage: scripts/check-pack.sh
# Exit: 1 if anything is missing or stale.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
v2_root="$(cd "${script_dir}/.." && pwd)"
pkg="${v2_root}/packages/react-native-turbo-image"
source "${script_dir}/native-versions.env"

fail() {
  echo "check-pack: $1" >&2
  echo "check-pack: run \`bun run vendor:nuke\` in v2/ (macOS with Xcode), then pack again." >&2
  exit 1
}

vendor="${pkg}/ios/vendor"
for framework in Nuke NukeUI; do
  if [[ ! -d "${vendor}/${framework}.xcframework" ]]; then
    fail "ios/vendor/${framework}.xcframework is missing."
  fi
done
if [[ ! -f "${vendor}/Nuke.version" ]]; then
  fail "ios/vendor/Nuke.version is missing, so the xcframework's version is unknown."
fi
vendored_version="$(tr -d '[:space:]' < "${vendor}/Nuke.version")"
if [[ "${vendored_version}" != "${NUKE_VERSION}" ]]; then
  fail "vendored Nuke is ${vendored_version}, but native-versions.env pins ${NUKE_VERSION}."
fi

# npm only packs LICENSE/README from the package dir; the .d.ts is what
# `types` points at (built by `prepack` just before this).
for file in LICENSE README.md lib/typescript/index.d.ts; do
  if [[ ! -f "${pkg}/${file}" ]]; then
    echo "check-pack: ${file} is missing from the package directory." >&2
    exit 1
  fi
done

# LICENSE is a copy (npm won't follow a link out of the package), so check
# it matches the root one.
if ! cmp -s "${pkg}/LICENSE" "${v2_root}/../LICENSE"; then
  echo "check-pack: LICENSE differs from the repository's; copy the root LICENSE over it." >&2
  exit 1
fi

echo "check-pack: ok (Nuke ${vendored_version})"
