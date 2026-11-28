require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

# Oldest supported React Native. Must match native-versions.env and
# android/build.gradle.
minimum_react_native = "0.88"

# Checked here because the peer range must be `*`: react-native-tvos
# versions are pre-releases no `>=0.88.0` range accepts.
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
  # Nightlies (0.0.0-...) count as newest.
  if !react_native_version.start_with?("0.0.0") &&
     (major_minor.(react_native_version) <=> major_minor.(minimum_react_native)) < 0
    raise "TurboImage 2.x requires React Native >= #{minimum_react_native} (New Architecture), " \
          "but this app uses #{react_native_version}. Upgrade React Native, or stay on " \
          "react-native-turbo-image 1.x."
  end
end

# How apps install TurboImage on iOS. Must build the same as Package.swift
# (RFC rule 6): same sources (plus ios/Fabric here), public headers, Nuke tag
# and language levels. Nuke is vendored since it left CocoaPods after 9.5.
# One module here vs one target per language in SwiftPM.
Pod::Spec.new do |s|
  s.name         = "TurboImage"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = "https://github.com/duguyihou/react-native-turbo-image"
  s.license      = package["license"]
  s.authors      = package["author"]
  # Nuke 14's floor. Must match Package.swift.
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
  # Network: the path monitor that retries a load failed offline.
  s.frameworks = "Network"
  # Live Text; tvOS has no VisionKit.
  s.ios.frameworks = "VisionKit"
  s.public_header_files = "ios/LoaderAPI/include/*.h"
  s.private_header_files = ["cpp/include/**/*.h", "ios/Fabric/**/*.h"]

  # Nuke pipeline, and NukeUI for animation.
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
