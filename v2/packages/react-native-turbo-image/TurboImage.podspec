require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

# CocoaPods path for TurboImage 2.0, kept during the SwiftPM migration.
#
# Behaviour must match Package.swift (RFC rule 6):
#   * same source trees (cpp/, ios/LoaderAPI, ios/Nuke, ios/LiveText,
#     ios/Fabric),
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
