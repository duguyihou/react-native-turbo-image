#!/usr/bin/env bash
# Runs the C++ core GoogleTest suite on the connected Android device, built
# with the pinned NDK for its ABI. Bionic's libm may differ from the host's,
# so this checks the placeholder goldens hold on Android too (RFC rule 3).
#
# Usage: scripts/test-core-android.sh
# Exit: 1 if the NDK is missing or a test fails.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
v2_root="$(cd "${script_dir}/.." && pwd)"
# shellcheck source=./native-versions.env source-path=SCRIPTDIR
source "${script_dir}/native-versions.env"

sdk="${ANDROID_HOME:-${HOME}/Library/Android/sdk}"
adb="${sdk}/platform-tools/adb"
ndk="${sdk}/ndk/${ANDROID_NDK_VERSION}"
if [[ ! -d "${ndk}" ]]; then
  echo "FAIL: NDK ${ANDROID_NDK_VERSION} not installed at ${ndk}" >&2
  exit 1
fi

"${adb}" wait-for-device
abi="$("${adb}" shell getprop ro.product.cpu.abi | tr -d '\r')"
build_dir="${v2_root}/tmp/core-android-${abi}"

cmake -S "${v2_root}/packages/react-native-turbo-image/cpp" -B "${build_dir}" \
  -DCMAKE_TOOLCHAIN_FILE="${ndk}/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI="${abi}" -DANDROID_PLATFORM=24 -DANDROID_STL=c++_static \
  -DTURBOIMAGE_BUILD_TESTS=ON -DTURBOIMAGE_WARNINGS_AS_ERRORS=ON > /dev/null
cmake --build "${build_dir}" -j > /dev/null

remote="/data/local/tmp/turboimage_core_tests"
"${adb}" push "${build_dir}/turboimage_core_tests" "${remote}" > /dev/null
# adb shell doesn't always propagate the exit status, so echo it.
output="$("${adb}" shell "${remote}; echo TURBOIMAGE_RC=\$?")"
echo "${output}" | tail -5
if [[ "${output}" != *"TURBOIMAGE_RC=0"* ]]; then
  echo "FAIL: core tests failed on ${abi}" >&2
  exit 1
fi
echo "PASS (core on ${abi})"
