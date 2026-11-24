require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

# The oldest React Native this library builds against. Must match
# scripts/native-versions.env (MIN_REACT_NATIVE_VERSION) and
# android/build.gradle.
minimum_react_native = "0.88"

# React Native's version, checked here because the npm peer range cannot: it
# is `*`, since every react-native-tvos version is a semver pre-release
# (`0.88.1-0`), which no range like `>=0.88.0` accepts. Read from the
# package.json Node's resolver would find, walking up from this library;
# react-native-tvos installs under the same name.
react_native_manifest = nil
dir = __dir__
loop do
  candidate = File.join(dir, "node_modules", "react-native", "package.json")
  if File.file?(candidate)
    react_native_manifest = candidate
    break
  end
  parent = File.dirname(dir)
  break if parent == dir
  dir = parent
end
if react_native_manifest.nil?
  Pod::UI.warn "TurboImage: could not find react-native's package.json above #{__dir__}; " \
               "skipping the React Native version check (>= #{minimum_react_native} is required)."
else
  react_native_version = JSON.parse(File.read(react_native_manifest))["version"].to_s
  major_minor = ->(version) { version.split(/[.-]/).first(2).map(&:to_i) }
  # A nightly (0.0.0-...) has no version to compare and is newer than any release.
  if !react_native_version.start_with?("0.0.0") &&
     (major_minor.(react_native_version) <=> major_minor.(minimum_react_native)) < 0
    raise "TurboImage 2.x requires React Native >= #{minimum_react_native} (New Architecture), " \
          "but this app uses #{react_native_version}. Upgrade React Native, or stay on " \
          "react-native-turbo-image 1.x."
  end
end

# How apps install TurboImage on iOS. Package.swift (tests only) must
# build the same thing (RFC rule 6):
#   * same source trees (cpp/, ios/LoaderAPI, ios/Nuke, ios/LiveText), plus
#     the Fabric view (ios/Fabric), which only this file builds,
#   * same public headers (ios/LoaderAPI/include only; C++ stays private so
#     the module stays importable from Swift),
#   * same Nuke tag (scripts/native-versions.env), delivered as vendored
#     xcframeworks (Nuke and NukeUI) because Nuke is not on CocoaPods trunk
#     after 9.5,
#   * same language levels (C++20, Swift 6 language mode).
#
# Structural difference, by necessity: CocoaPods compiles all of this into one
# module, whereas SwiftPM needs one target per language. The ObjC/Swift code
# is written to work under both (`#if canImport(TurboImageLoaderAPI)`,
# quoted includes for seam headers).
Pod::Spec.new do |s|
  s.name         = "TurboImage"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = "https://github.com/duguyihou/react-native-turbo-image"
  s.license      = package["license"]
  s.authors      = package["author"]
  # Nuke 14's floor, not React Native's `min_ios_version_supported` (15.1):
  # the vendored framework does not load below it. Must match Package.swift.
  # Under stock React Native the tvOS entry is inert: no tvOS target exists
  # to install into.
  s.platforms    = { :ios => "16.0", :tvos => "16.0" }
  s.source       = { :git => "https://github.com/duguyihou/react-native-turbo-image.git", :tag => "v#{s.version}" }
  s.swift_version = "6.0"

  s.source_files = [
    "cpp/include/**/*.h",
    "cpp/src/**/*.cpp",
    "ios/LoaderAPI/**/*.{h,m}",
    "ios/Nuke/**/*.swift",
    "ios/LiveText/**/*.swift",
    "ios/Fabric/**/*.{h,mm}",
  ]
  # Live Text (ios/LiveText). tvOS has no VisionKit, and the Live Text source
  # compiles to nothing there.
  s.ios.frameworks = "VisionKit"
  s.public_header_files = "ios/LoaderAPI/include/*.h"
  s.private_header_files = ["cpp/include/**/*.h", "ios/Fabric/**/*.h"]

  # Nuke's two products the adapter imports: the pipeline, and NukeUI for the
  # animated-image player.
  nuke_xcframeworks = ["Nuke", "NukeUI"].map { |name| "ios/vendor/#{name}.xcframework" }
  nuke_xcframeworks.each do |xcframework|
    unless File.exist?(File.join(__dir__, xcframework))
      raise "TurboImage: #{xcframework} is missing. Run `bun run vendor:nuke` " \
            "in packages/react-native-turbo-image (published packages ship it prebuilt)."
    end
  end
  s.vendored_frameworks = nuke_xcframeworks

  s.pod_target_xcconfig = {
    "CLANG_CXX_LANGUAGE_STANDARD" => "c++20",
    "HEADER_SEARCH_PATHS" => [
      "\"$(PODS_TARGET_SRCROOT)/cpp/include\"",
      "\"$(PODS_TARGET_SRCROOT)/ios/LoaderAPI/include\"",
    ].join(" "),
  }

  install_modules_dependencies(s)
end
