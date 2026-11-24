// swift-tools-version: 6.4
//
// TurboImage 2.0 — Swift Package Manager manifest.
//
// Module boundaries (RFC §iOS module layout). SwiftPM forbids mixing Swift
// and C-family sources in one target, so each language gets its own target
// and the dependency arrows only point downwards:
//
//   (Fabric view, ObjC++: podspec only)     owner: RN integration
//     ├─ TurboImageCore (C++20)             owner: core, shared with Android
//     ├─ TurboImageLoaderAPI (ObjC)         owner: core; the adapter seam
//     └─ TurboImageNuke (Swift)             owner: iOS adapter
//          ├─ TurboImageLoaderAPI
//          └─ Nuke, NukeUI (pinned)
//
// For the adapter tests and the tvOS build only. Apps use CocoaPods, so
// this file is not shipped and has no Fabric target (ADR 0015).
// TODO: support apps once React Native's SwiftPM leaves preview.

import Foundation
import PackageDescription

// MARK: - Pinned versions (RFC rule 7)
//
// Must match scripts/native-versions.env; scripts/check-native-versions.sh
// enforces it. Evaluating a beta/RC overrides this through the environment,
// so production builds never resolve a pre-release (rule 8).
let nukeVersion: Version = Context.environment["TURBOIMAGE_EVAL_NUKE_VERSION"]
  .flatMap { Version($0) } ?? "14.0.0"
// Nuke 14's floor, for iOS and tvOS alike. It is above React Native's own
// 15.1, so an app has to raise its deployment target to use TurboImage.
// Must match `s.platforms` in TurboImage.podspec.
let iosDeploymentTarget = "16.0"
let tvosDeploymentTarget = iosDeploymentTarget

// MARK: - Targets

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
      // The animated-image player (`AnimatedImageView` and its frame pool).
      .product(name: "NukeUI", package: "Nuke"),
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

let dependencies: [Package.Dependency] = [
  .package(url: "https://github.com/kean/Nuke.git", exact: nukeVersion),
]

let productTargets = ["TurboImageCore", "TurboImageLoaderAPI", "TurboImageNuke", "TurboImageLiveText"]

// What the smoke suite cannot see, such as whether an image animates.
targets.append(
  .testTarget(
    name: "TurboImageNukeTests",
    dependencies: [
      "TurboImageNuke",
      "TurboImageLoaderAPI",
      .product(name: "NukeUI", package: "Nuke"),
    ],
    path: "ios/Tests/NukeAdapterTests",
    swiftSettings: [.swiftLanguageMode(.v6)]
  )
)

let package = Package(
  name: "TurboImage",
  platforms: [.iOS(iosDeploymentTarget), .tvOS(tvosDeploymentTarget)],
  products: [
    .library(name: "TurboImage", targets: productTargets),
  ],
  dependencies: dependencies,
  targets: targets,
  cxxLanguageStandard: .cxx20
)
