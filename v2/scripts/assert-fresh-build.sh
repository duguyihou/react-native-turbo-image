#!/usr/bin/env bash
# Fails if a build artifact is older than the current sources, so a smoke
# test never passes on a stale binary. Sourced by smoke-*.sh and
# build-stamped.sh.
#
# Current means either: the artifact's stamp (from build-stamped.sh) matches
# the sources' fingerprint, or no source is newer than the artifact (for
# unstamped builds: Xcode, Android Studio, CI).
#
# Usage: assert_fresh_build <artifact-path> <ios|android> [stamp-path]
#        source_fingerprint <ios|android>
# The platform picks which native sources count.

# Prints the bundled sources, NUL-separated (tests and vendor excluded).
# Extra arguments are appended to the `find` expression.
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

# One hash over those sources' names and contents.
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
