#!/usr/bin/env bash
# Runs the C++ core GoogleTest suite *on* the connected Android device or
# emulator, built with the pinned NDK.
#
# Why: the placeholder decoders are checked byte for byte against the JS
# references. Host runs prove that for Apple Clang / GCC, but Android uses
# NDK Clang and bionic's libm, whose cos()/pow() may differ in the last bit.
# Running the same goldens on-device is what backs the "identical pixels on
# iOS and Android" claim (RFC rule 3).
#
# Usage: scripts/test-core-android.sh
# Builds for the device's primary ABI (arm64-v8a locally on Apple Silicon,
# x86_64 on the CI emulator).

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
# adb shell does not propagate the exit status on every platform, so echo
# it and check explicitly.
output="$("${adb}" shell "${remote}; echo TURBOIMAGE_RC=\$?")"
echo "${output}" | tail -5
if [[ "${output}" != *"TURBOIMAGE_RC=0"* ]]; then
  echo "FAIL: core tests failed on ${abi}" >&2
  exit 1
fi
echo "PASS (core on ${abi})"
