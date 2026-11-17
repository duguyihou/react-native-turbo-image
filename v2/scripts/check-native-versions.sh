#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
#
# Asserts every manifest pins the same native dependency versions as
# scripts/native-versions.env (RFC rules 6 and 7). Runs first in CI so a
# half-updated bump fails in seconds instead of after a 20-minute build.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
v2_root="$(cd "${script_dir}/.." && pwd)"
pkg="${v2_root}/packages/react-native-turbo-image"
source "${script_dir}/native-versions.env"

failures=0

# expect <file> <fixed-string> <description>
expect() {
  local file="$1" needle="$2" what="$3"
  if grep -qF -- "${needle}" "${file}"; then
    echo "ok   ${what}"
  else
    echo "FAIL ${what}: expected '${needle}' in ${file#"${v2_root}"/}"
    failures=$((failures + 1))
  fi
}

expect "${pkg}/Package.swift" "?? \"${NUKE_VERSION}\"" "Package.swift Nuke ${NUKE_VERSION}"
expect "${pkg}/android/build.gradle" "def coilVersion = \"${COIL_VERSION}\"" "build.gradle Coil ${COIL_VERSION}"
expect "${pkg}/android/build.gradle" "def apngDrawableVersion = \"${APNG_DRAWABLE_VERSION}\"" "build.gradle apng-drawable ${APNG_DRAWABLE_VERSION}"
expect "${pkg}/android/build.gradle" "kotlinVersion    : \"${KOTLIN_VERSION}\"" "build.gradle default Kotlin ${KOTLIN_VERSION}"
expect "${pkg}/android/build.gradle" "ndkVersion       : \"${ANDROID_NDK_VERSION}\"" "build.gradle default NDK ${ANDROID_NDK_VERSION}"
expect "${pkg}/cpp/CMakeLists.txt" "googletest/archive/refs/tags/v${GOOGLETEST_VERSION}.tar.gz" "CMake GoogleTest ${GOOGLETEST_VERSION}"
expect "${v2_root}/apps/example/package.json" "\"react-native\": \"${REACT_NATIVE_VERSION}\"" "example react-native ${REACT_NATIVE_VERSION}"
expect "${v2_root}/apps/example/android/build.gradle" "kotlinVersion = \"${KOTLIN_VERSION}\"" "example Kotlin ${KOTLIN_VERSION}"

# The CocoaPods path vendors an xcframework; if one is present locally it
# must have been built from the pinned tag.
vendored="${pkg}/ios/vendor/Nuke.version"
if [[ -f "${vendored}" ]]; then
  expect "${vendored}" "${NUKE_VERSION}" "vendored Nuke.xcframework ${NUKE_VERSION}"
fi

if (( failures > 0 )); then
  echo "${failures} version mismatch(es)." >&2
  exit 1
fi
