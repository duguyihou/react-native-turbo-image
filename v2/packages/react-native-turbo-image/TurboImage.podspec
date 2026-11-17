require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

# CocoaPods path for TurboImage 2.0, kept during the SwiftPM migration.
#
# Behaviour must match Package.swift (RFC rule 6):
#   * same source trees (cpp/, ios/LoaderAPI, ios/Nuke, ios/Fabric),
#   * same public headers (ios/LoaderAPI/include only; C++ stays private so
#     the module stays importable from Swift),
#   * same Nuke tag (scripts/native-versions.env), delivered as a vendored
#     xcframework because Nuke is not on CocoaPods trunk after 9.5,
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
  s.platforms    = { :ios => min_ios_version_supported }
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
  # Live Text (ios/LiveText). VisionKit exists on every supported iOS; its
  # image-analysis classes are iOS 16+ and gated at runtime.
  s.frameworks = "VisionKit"
  s.public_header_files = "ios/LoaderAPI/include/*.h"
  s.private_header_files = ["cpp/include/**/*.h", "ios/Fabric/**/*.h"]

  nuke_xcframework = File.join(__dir__, "ios/vendor/Nuke.xcframework")
  unless File.exist?(nuke_xcframework)
    raise "TurboImage: #{nuke_xcframework} is missing. Run `bun run vendor:nuke` " \
          "in packages/react-native-turbo-image (published packages ship it prebuilt)."
  end
  s.vendored_frameworks = "ios/vendor/Nuke.xcframework"

  s.pod_target_xcconfig = {
    "CLANG_CXX_LANGUAGE_STANDARD" => "c++20",
    "HEADER_SEARCH_PATHS" => [
      "\"$(PODS_TARGET_SRCROOT)/cpp/include\"",
      "\"$(PODS_TARGET_SRCROOT)/ios/LoaderAPI/include\"",
    ].join(" "),
  }

  install_modules_dependencies(s)
end
