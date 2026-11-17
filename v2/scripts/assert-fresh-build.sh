#!/usr/bin/env bash
# Fails if a build artifact is older than any source it was built from.
#
# The smoke scripts install whatever artifact is on disk. If the preceding
# build failed (or was skipped), they would happily test a stale binary and
# report a PASS that says nothing about the current sources. Sourced by
# smoke-{ios,android}.sh before installing.
#
# Usage: assert_fresh_build <artifact-path> <ios|android>
# The platform selects which native sources count: an iOS-only change must
# not make an otherwise current APK look stale, and vice versa.

assert_fresh_build() {
  local artifact="$1"
  local platform="$2"
  local v2_root
  v2_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

  if [[ ! -e "${artifact}" ]]; then
    echo "FAIL: build artifact not found: ${artifact}" >&2
    return 1
  fi

  local platform_sources
  case "${platform}" in
    ios) platform_sources="ios" ;;
    android) platform_sources="android/src" ;;
    *)
      echo "FAIL: assert_fresh_build: unknown platform '${platform}'" >&2
      return 1
      ;;
  esac

  # Sources that end up in the binary: the library's JS and C++, this
  # platform's native code, and the example app's JS. Build outputs and unit
  # tests (src/__tests__, never bundled) are excluded.
  #
  # The comparison is by modification time. A source rewritten with identical
  # content looks newer, but the build tools compare content and leave the
  # artifact alone, so the check then fails although the artifact is
  # current. That is the safe direction; rebuild or restore the timestamp.
  local newer
  newer="$(find \
    "${v2_root}/packages/react-native-turbo-image/src" \
    "${v2_root}/packages/react-native-turbo-image/cpp/include" \
    "${v2_root}/packages/react-native-turbo-image/cpp/src" \
    "${v2_root}/packages/react-native-turbo-image/${platform_sources}" \
    "${v2_root}/apps/example/App.tsx" \
    -path '*/vendor' -prune -o -path '*/__tests__' -prune -o \
    -type f -newer "${artifact}" -print -quit)"

  if [[ -n "${newer}" ]]; then
    echo "FAIL: ${artifact} is older than ${newer#"${v2_root}"/}; rebuild before running the smoke test." >&2
    return 1
  fi
}
