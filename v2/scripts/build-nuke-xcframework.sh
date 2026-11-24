#!/usr/bin/env bash
# Builds Nuke and NukeUI xcframeworks from the pinned Nuke tag for CocoaPods.
# Nuke stopped publishing to CocoaPods trunk after 9.5, so we vendor it;
# SwiftPM uses the same tag from native-versions.env (RFC rule 6).
#
# Usage: scripts/build-nuke-xcframework.sh [nuke-tag]
# Output: packages/react-native-turbo-image/ios/vendor/{Nuke,NukeUI}.xcframework
# (gitignored; built in CI and before publish).

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
v2_root="$(cd "${script_dir}/.." && pwd)"
# shellcheck source=./native-versions.env source-path=SCRIPTDIR
source "${script_dir}/native-versions.env"

nuke_tag="${1:-${NUKE_VERSION}}"
out_dir="${v2_root}/packages/react-native-turbo-image/ios/vendor"
work_dir="${v2_root}/tmp/nuke-xcframework"

rm -rf "${work_dir}"
mkdir -p "${work_dir}" "${out_dir}"

git clone --quiet --depth 1 --branch "${nuke_tag}" \
  https://github.com/kean/Nuke.git "${work_dir}/src"

# Device and simulator slices for each podspec platform.
# TODO: add visionOS once the library targets it.
destinations=(
  "generic/platform=iOS"
  "generic/platform=iOS Simulator"
  "generic/platform=tvOS"
  "generic/platform=tvOS Simulator"
)
# The NukeUI scheme builds Nuke too, and SKIP_INSTALL=NO installs both
# into each archive.
archives=()
for destination in "${destinations[@]}"; do
  archive="${work_dir}/${destination//[^A-Za-z]/_}.xcarchive"
  xcodebuild archive \
    -project "${work_dir}/src/Nuke.xcodeproj" \
    -scheme NukeUI \
    -configuration Release \
    -destination "${destination}" \
    -archivePath "${archive}" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    -quiet
  archives+=("${archive}")
done

# dSYMs for device slices only, so shipped crashes can be symbolicated.
# Simulator dSYMs would roughly double the tarball for no shipped benefit.
for framework in Nuke NukeUI; do
  create_args=()
  for archive in "${archives[@]}"; do
    create_args+=(-framework "${archive}/Products/Library/Frameworks/${framework}.framework")
    case "${archive}" in
      *Simulator*) ;;
      *) create_args+=(-debug-symbols "${archive}/dSYMs/${framework}.framework.dSYM") ;;
    esac
  done
  rm -rf "${out_dir}/${framework}.xcframework"
  xcodebuild -create-xcframework "${create_args[@]}" -output "${out_dir}/${framework}.xcframework"
done

echo "${nuke_tag}" > "${out_dir}/Nuke.version"
echo "Built Nuke and NukeUI ${nuke_tag} → ${out_dir}"
