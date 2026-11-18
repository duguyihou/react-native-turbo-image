#!/usr/bin/env bash
# Fails if a build artifact was not built from the sources as they are now.
#
# The smoke scripts install whatever artifact is on disk. If the preceding
# build failed (or was skipped), they would happily test a stale binary and
# report a PASS that says nothing about the current sources. Sourced by
# smoke-{ios,android}.sh before installing, and by build-stamped.sh.
#
# Two ways to be current, either is enough:
#   * the artifact carries a stamp (written by build-stamped.sh) with the
#     fingerprint of the sources it was built from, and the sources still
#     have that fingerprint. Exact: it survives a checkout or a restored
#     backup that rewrites files with the content they already had, which
#     leaves the artifact alone because the build tools compare content;
#   * no source is newer than the artifact. For builds that were not
#     stamped (Xcode, Android Studio, a bare `./gradlew` in CI).
#
# Usage: assert_fresh_build <artifact-path> <ios|android> [stamp-path]
#        source_fingerprint <ios|android>
# The platform selects which native sources count: an iOS-only change must
# not make an otherwise current APK look stale, and vice versa.

# Prints the paths of the sources that end up in the binary, NUL-separated:
# the library's JS and C++, this platform's native code, and the example
# app's JS. Build outputs and unit tests (src/__tests__, never bundled) are
# excluded. Extra arguments are appended to the `find` expression.
_fresh_build_sources() {
  local platform="$1"
  shift
  local v2_root platform_sources
  v2_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  case "${platform}" in
    ios) platform_sources="ios" ;;
    android) platform_sources="android/src" ;;
    *)
      echo "FAIL: assert_fresh_build: unknown platform '${platform}'" >&2
      return 1
      ;;
  esac
  find \
    "${v2_root}/packages/react-native-turbo-image/src" \
    "${v2_root}/packages/react-native-turbo-image/cpp/include" \
    "${v2_root}/packages/react-native-turbo-image/cpp/src" \
    "${v2_root}/packages/react-native-turbo-image/${platform_sources}" \
    "${v2_root}/apps/example/App.tsx" \
    -path '*/vendor' -prune -o -path '*/__tests__' -prune -o \
    -type f "$@"
}

# One hash over the names and contents of those sources.
source_fingerprint() {
  local platform="$1"
  _fresh_build_sources "${platform}" -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256 | shasum -a 256 | cut -d' ' -f1
}

assert_fresh_build() {
  local artifact="$1"
  local platform="$2"
  local stamp="${3:-}"
  local v2_root
  v2_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

  if [[ ! -e "${artifact}" ]]; then
    echo "FAIL: build artifact not found: ${artifact}" >&2
    return 1
  fi

  if [[ -n "${stamp}" && -f "${stamp}" ]]; then
    local built_from current
    built_from="$(< "${stamp}")"
    current="$(source_fingerprint "${platform}")" || return 1
    if [[ "${built_from}" == "${current}" ]]; then
      return 0
    fi
  fi

  local newer
  newer="$(_fresh_build_sources "${platform}" -newer "${artifact}" -print -quit)" || return 1
  if [[ -n "${newer}" ]]; then
    echo "FAIL: ${artifact} is older than ${newer#"${v2_root}"/}; rebuild before running the smoke test." >&2
    return 1
  fi
}
