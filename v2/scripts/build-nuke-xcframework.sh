#!/usr/bin/env bash
# Builds Nuke.xcframework and NukeUI.xcframework from a pinned Nuke tag for
# the CocoaPods path. The adapter imports both: Nuke is the pipeline, NukeUI
# the animated-image player.
#
# Why this exists: Nuke stopped publishing to CocoaPods trunk after 9.5, so
# `s.dependency "Nuke", "14.0.0"` cannot resolve. SwiftPM consumers get Nuke
# from Package.swift (`.package(url:exact:)`); CocoaPods consumers get the
# *same tag* as vendored xcframeworks built here. Both paths read the
# version from scripts/native-versions.env so they cannot drift (RFC rule 6).
#
# Output: packages/react-native-turbo-image/ios/vendor/{Nuke,NukeUI}.xcframework
# (gitignored; built in CI and before `npm publish`).
#
# Usage: scripts/build-nuke-xcframework.sh [nuke-tag]

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

# One slice per platform the podspec declares (iOS and tvOS), device and
# simulator each. visionOS is a TODO until the library targets it.
destinations=(
  "generic/platform=iOS"
  "generic/platform=iOS Simulator"
  "generic/platform=tvOS"
  "generic/platform=tvOS Simulator"
)
# One archive per destination holds both frameworks: the NukeUI scheme
# builds Nuke as its dependency, and SKIP_INSTALL=NO on the command line
# applies to every target, so both are installed into the archive.
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

# With debug symbols: these are dynamic frameworks inside the app, and
# without their dSYMs a crash in them cannot be symbolicated. They roughly
# triple the size of the vendored directory.
for framework in Nuke NukeUI; do
  create_args=()
  for archive in "${archives[@]}"; do
    create_args+=(
      -framework "${archive}/Products/Library/Frameworks/${framework}.framework"
      -debug-symbols "${archive}/dSYMs/${framework}.framework.dSYM"
    )
  done
  rm -rf "${out_dir}/${framework}.xcframework"
  xcodebuild -create-xcframework "${create_args[@]}" -output "${out_dir}/${framework}.xcframework"
done

echo "${nuke_tag}" > "${out_dir}/Nuke.version"
echo "Built Nuke and NukeUI ${nuke_tag} → ${out_dir}"
