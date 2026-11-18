#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
#
# `prepack` guard for packages/react-native-turbo-image: refuses to build a
# tarball that CocoaPods users could not install.
#
# The podspec vendors ios/vendor/Nuke.xcframework, which is gitignored and
# built by scripts/build-nuke-xcframework.sh. A tarball packed from a fresh
# clone would therefore ship without it, and one packed after a Nuke bump
# could ship the previous version's binary next to a Package.swift that pins
# the new one (RFC rule 6: both iOS paths use the same Nuke).
#
# This checks; it does not build. Building needs Xcode and takes minutes,
# which is the wrong thing to start from inside `npm pack`.

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
if [[ ! -d "${vendor}/Nuke.xcframework" ]]; then
  fail "ios/vendor/Nuke.xcframework is missing."
fi
if [[ ! -f "${vendor}/Nuke.version" ]]; then
  fail "ios/vendor/Nuke.version is missing, so the xcframework's version is unknown."
fi
vendored_version="$(tr -d '[:space:]' < "${vendor}/Nuke.version")"
if [[ "${vendored_version}" != "${NUKE_VERSION}" ]]; then
  fail "vendored Nuke is ${vendored_version}, but native-versions.env pins ${NUKE_VERSION}."
fi

# npm only picks these up from the package directory itself.
for file in LICENSE README.md; do
  if [[ ! -f "${pkg}/${file}" ]]; then
    echo "check-pack: ${file} is missing from the package directory." >&2
    exit 1
  fi
done

echo "check-pack: ok (Nuke ${vendored_version})"
