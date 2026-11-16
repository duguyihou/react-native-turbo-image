#!/usr/bin/env bash
# Fails if a build artifact is older than any source it was built from.
#
# The smoke scripts install whatever artifact is on disk. If the preceding
# build failed (or was skipped), they would happily test a stale binary and
# report a PASS that says nothing about the current sources. Sourced by
# smoke-{ios,android}.sh before installing.
#
# Usage: assert_fresh_build <artifact-path>

assert_fresh_build() {
  local artifact="$1"
  local v2_root
  v2_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

  if [[ ! -e "${artifact}" ]]; then
    echo "FAIL: build artifact not found: ${artifact}" >&2
    return 1
  fi

  # Sources that end up in the binary: the library (JS, C++, ObjC/Swift,
  # Kotlin) and the example app's JS. Build outputs are excluded.
  local newer
  newer="$(find \
    "${v2_root}/packages/react-native-turbo-image/src" \
    "${v2_root}/packages/react-native-turbo-image/cpp/include" \
    "${v2_root}/packages/react-native-turbo-image/cpp/src" \
    "${v2_root}/packages/react-native-turbo-image/ios" \
    "${v2_root}/packages/react-native-turbo-image/android/src" \
    "${v2_root}/apps/example/App.tsx" \
    -path '*/vendor' -prune -o -type f -newer "${artifact}" -print -quit)"

  if [[ -n "${newer}" ]]; then
    echo "FAIL: ${artifact} is older than ${newer#"${v2_root}"/}; rebuild before running the smoke test." >&2
    return 1
  fi
}
