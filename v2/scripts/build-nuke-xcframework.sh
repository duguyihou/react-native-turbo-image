#!/usr/bin/env bash
# Builds Nuke.xcframework from a pinned Nuke tag for the CocoaPods path.
#
# Why this exists: Nuke stopped publishing to CocoaPods trunk after 9.5, so
# `s.dependency "Nuke", "13.2.3"` cannot resolve. SwiftPM consumers get Nuke
# from Package.swift (`.package(url:exact:)`); CocoaPods consumers get the
# *same tag* as a vendored xcframework built here. Both paths read the
# version from scripts/native-versions.env so they cannot drift (RFC rule 6).
#
# Output: packages/react-native-turbo-image/ios/vendor/Nuke.xcframework
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

# iOS device + simulator only. tvOS/visionOS are TODO until the RN example
# targets them.
for destination in "generic/platform=iOS" "generic/platform=iOS Simulator"; do
  slug="${destination//[^A-Za-z]/_}"
  xcodebuild archive \
    -project "${work_dir}/src/Nuke.xcodeproj" \
    -scheme Nuke \
    -configuration Release \
    -destination "${destination}" \
    -archivePath "${work_dir}/${slug}.xcarchive" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    -quiet
done

rm -rf "${out_dir}/Nuke.xcframework"
# With debug symbols: Nuke is a dynamic framework inside the app, and without
# its dSYMs a crash in it cannot be symbolicated. They roughly triple the
# size of the vendored directory.
xcodebuild -create-xcframework \
  -framework "${work_dir}/generic_platform_iOS.xcarchive/Products/Library/Frameworks/Nuke.framework" \
  -debug-symbols "${work_dir}/generic_platform_iOS.xcarchive/dSYMs/Nuke.framework.dSYM" \
  -framework "${work_dir}/generic_platform_iOS_Simulator.xcarchive/Products/Library/Frameworks/Nuke.framework" \
  -debug-symbols "${work_dir}/generic_platform_iOS_Simulator.xcarchive/dSYMs/Nuke.framework.dSYM" \
  -output "${out_dir}/Nuke.xcframework"

echo "${nuke_tag}" > "${out_dir}/Nuke.version"
echo "Built Nuke ${nuke_tag} → ${out_dir}/Nuke.xcframework"
