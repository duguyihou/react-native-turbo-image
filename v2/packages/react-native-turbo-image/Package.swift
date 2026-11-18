// swift-tools-version: 6.2
//
// TurboImage 2.0 — Swift Package Manager manifest.
//
// Module boundaries (RFC §iOS module layout). SwiftPM forbids mixing Swift
// and C-family sources in one target, so each language gets its own target
// and the dependency arrows only point downwards:
//
//   TurboImage (ObjC++, Fabric view)        owner: RN integration
//     ├─ TurboImageCore (C++20)             owner: core, shared with Android
//     ├─ TurboImageLoaderAPI (ObjC)         owner: core; the adapter seam
//     └─ TurboImageNuke (Swift)             owner: iOS adapter
//          ├─ TurboImageLoaderAPI
//          └─ Nuke (pinned)
//
// Two ways this manifest is consumed:
//
//   1. Standalone (`xcodebuild -scheme TurboImage` in this directory, CI).
//      There is no React Native app around it, so the Fabric target is
//      omitted and the `TurboImage` product contains only core + seam +
//      adapter. This is what lets the native layers build and test without
//      an app.
//
//   2. Inside an app using React Native 0.88's SwiftPM integration
//      (`npx react-native spm`). RN's autolinker treats a hand-written
//      Package.swift at the npm-package root as "self-managed" and
//      references it through a symlink at
//        <app>/build/generated/autolinking/libs/TurboImage
//      React Native itself is then a *local* package at a path relative to
//      that symlink. We detect it and add the Fabric target.
//
//      This coupling to the app's build layout is the main finding of
//      docs/spm-assessment.md: RN 0.88 gives self-managed packages no
//      layout-independent way to depend on React. Remote mode
//      (RN_SPM_REMOTE_URL) is a TODO here until RN 0.89 settles it.

import Foundation
import PackageDescription

// MARK: - Pinned versions (RFC rule 7)
//
// Must match scripts/native-versions.env; scripts/check-native-versions.sh
// enforces it. The beta/RC evaluation job overrides this through the
// environment so production builds never resolve a pre-release (rule 8).
let nukeVersion: Version = Context.environment["TURBOIMAGE_EVAL_NUKE_VERSION"]
  .flatMap { Version($0) } ?? "13.2.3"
// Nuke 14 raises its floor to iOS 16; 13.x supports React Native's 15.1.
// react-native-tvos uses the same floor for tvOS, and so does Nuke.
let iosDeploymentTarget = nukeVersion.major >= 14 ? "16.0" : "15.1"
let tvosDeploymentTarget = iosDeploymentTarget

// MARK: - React Native detection

// Paths relative to <app>/build/generated/autolinking/libs/TurboImage, the
// symlink RN 0.88 uses to reference this package. Derived from
// react-native/scripts/spm/scaffold-package-swift.js (relFromManifest).
let reactNativeXCFrameworksPath = "../../../../xcframeworks"
let reactNativeCodegenPath = "../../../ios"

let isInsideReactNativeApp: Bool = {
  if let forced = Context.environment["TURBOIMAGE_SPM_STANDALONE"], forced == "1" {
    return false
  }
  let manifest = URL(fileURLWithPath: Context.packageDirectory)
    .appendingPathComponent(reactNativeXCFrameworksPath)
    .appendingPathComponent("Package.swift")
    .standardizedFileURL.path
  return FileManager.default.fileExists(atPath: manifest)
}()

// MARK: - Targets

let reactDefines: [CXXSetting] = [
  // Must match the prebuilt React.xcframework's config-gated C++ ABI, or
  // Release links fail (see RN's REACT_CXX_CONFIG_DEFINES).
  .define("DEBUG", .when(configuration: .debug)),
  .define("NDEBUG", .when(configuration: .release)),
]

var targets: [Target] = [
  .target(
    name: "TurboImageCore",
    path: "cpp",
    exclude: ["tests", "CMakeLists.txt"],
    sources: ["src"],
    publicHeadersPath: "include"
  ),
  .target(
    name: "TurboImageLoaderAPI",
    path: "ios/LoaderAPI",
    publicHeadersPath: "include",
    linkerSettings: [.linkedFramework("UIKit")]
  ),
  .target(
    name: "TurboImageNuke",
    dependencies: [
      "TurboImageLoaderAPI",
      .product(name: "Nuke", package: "Nuke"),
    ],
    path: "ios/Nuke",
    swiftSettings: [.swiftLanguageMode(.v6)]
  ),
  .target(
    name: "TurboImageLiveText",
    dependencies: ["TurboImageLoaderAPI"],
    path: "ios/LiveText",
    swiftSettings: [.swiftLanguageMode(.v6)],
    // tvOS has no VisionKit; the target's one source file is empty there.
    linkerSettings: [.linkedFramework("VisionKit", .when(platforms: [.iOS]))]
  ),
]

var dependencies: [Package.Dependency] = [
  .package(url: "https://github.com/kean/Nuke.git", exact: nukeVersion),
]

var productTargets = ["TurboImageCore", "TurboImageLoaderAPI", "TurboImageNuke", "TurboImageLiveText"]

if isInsideReactNativeApp {
  dependencies += [
    .package(name: "ReactNative", path: reactNativeXCFrameworksPath),
    .package(name: "React-GeneratedCode", path: reactNativeCodegenPath),
  ]
  targets.append(
    .target(
      name: "TurboImage",
      dependencies: [
        "TurboImageCore",
        "TurboImageLoaderAPI",
        // Linked so the registry's runtime lookup of `TurboImageNukeLoader`
        // succeeds; Fabric code never imports it.
        "TurboImageNuke",
        // Same for `TurboImageLiveTextInteraction` (TIMakeLiveTextInteraction).
        "TurboImageLiveText",
        .product(name: "ReactHeaders", package: "ReactNative"),
        .product(name: "ReactNativeHeaders", package: "ReactNative"),
        .product(name: "ReactNativeDependenciesHeaders", package: "ReactNative"),
        .product(name: "ReactAppHeaders", package: "React-GeneratedCode"),
      ],
      path: "ios/Fabric",
      publicHeadersPath: ".",
      cxxSettings: reactDefines
    )
  )
  productTargets = ["TurboImage"]
}

let package = Package(
  name: "TurboImage",
  platforms: [.iOS(iosDeploymentTarget), .tvOS(tvosDeploymentTarget)],
  products: [
    // The autolinker links the product named after `swiftpmConfig.name`.
    .library(name: "TurboImage", targets: productTargets),
  ],
  dependencies: dependencies,
  targets: targets,
  cxxLanguageStandard: .cxx20
)
