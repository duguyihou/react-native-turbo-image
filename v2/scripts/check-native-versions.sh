#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
#
# Checks every manifest pins the versions in native-versions.env
# (RFC rules 6 and 7). Runs first in CI so a partial bump fails fast.
#
# Usage: scripts/check-native-versions.sh
# Exit: 1 on any mismatch.

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
expect "${pkg}/android/build.gradle" "def androidxTestVersion = \"${ANDROIDX_TEST_VERSION}\"" "build.gradle androidx.test ${ANDROIDX_TEST_VERSION}"
expect "${pkg}/android/build.gradle" "def androidxTestJunitVersion = \"${ANDROIDX_TEST_JUNIT_VERSION}\"" "build.gradle androidx.test.ext:junit ${ANDROIDX_TEST_JUNIT_VERSION}"
expect "${pkg}/android/build.gradle" "def junitVersion = \"${JUNIT_VERSION}\"" "build.gradle JUnit ${JUNIT_VERSION}"
expect "${pkg}/android/build.gradle" "kotlinVersion    : \"${KOTLIN_VERSION}\"" "build.gradle default Kotlin ${KOTLIN_VERSION}"
expect "${pkg}/android/build.gradle" "def minimumReactNative = \"${MIN_REACT_NATIVE_VERSION}\"" "build.gradle minimum React Native ${MIN_REACT_NATIVE_VERSION}"
expect "${pkg}/TurboImage.podspec" "minimum_react_native = \"${MIN_REACT_NATIVE_VERSION}\"" "podspec minimum React Native ${MIN_REACT_NATIVE_VERSION}"
expect "${pkg}/android/build.gradle" "ndkVersion       : \"${ANDROID_NDK_VERSION}\"" "build.gradle default NDK ${ANDROID_NDK_VERSION}"
expect "${pkg}/cpp/CMakeLists.txt" "googletest/archive/refs/tags/v${GOOGLETEST_VERSION}.tar.gz" "CMake GoogleTest ${GOOGLETEST_VERSION}"
expect "${v2_root}/apps/example/package.json" "\"react-native\": \"${REACT_NATIVE_VERSION}\"" "example react-native ${REACT_NATIVE_VERSION}"
expect "${v2_root}/apps/example/android/build.gradle" "kotlinVersion = \"${KOTLIN_VERSION}\"" "example Kotlin ${KOTLIN_VERSION}"

# A locally vendored Nuke.xcframework must match the pinned tag.
vendored="${pkg}/ios/vendor/Nuke.version"
if [[ -f "${vendored}" ]]; then
  expect "${vendored}" "${NUKE_VERSION}" "vendored Nuke.xcframework ${NUKE_VERSION}"
fi

if (( failures > 0 )); then
  echo "${failures} version mismatch(es)." >&2
  exit 1
fi
