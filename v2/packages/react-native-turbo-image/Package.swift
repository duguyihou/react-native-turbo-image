// swift-tools-version: 6.4
//
// One target per language (SwiftPM can't mix them):
//   (Fabric view, ObjC++: podspec only)
//     ├─ TurboImageCore (C++20)
//     ├─ TurboImageLoaderAPI (ObjC seam)
//     └─ TurboImageNuke (Swift) → LoaderAPI, Nuke, NukeUI
//
// Only for adapter tests and tvOS; apps use CocoaPods (ADR 0015).
// TODO: support apps once React Native's SwiftPM leaves preview.

import Foundation
import PackageDescription

// MARK: - Pinned versions (RFC rule 7)
//
// Must match scripts/native-versions.env. Pre-releases only via env (rule 8).
let nukeVersion: Version = Context.environment["TURBOIMAGE_EVAL_NUKE_VERSION"]
  .flatMap { Version($0) } ?? "14.0.0"
// Nuke 14's floor (above React Native's 15.1). Must match the podspec.
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
      // Animated-image player.
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
    // tvOS has no VisionKit; the source compiles to nothing there.
    linkerSettings: [.linkedFramework("VisionKit", .when(platforms: [.iOS]))]
  ),
]

let dependencies: [Package.Dependency] = [
  .package(url: "https://github.com/kean/Nuke.git", exact: nukeVersion),
]

let productTargets = ["TurboImageCore", "TurboImageLoaderAPI", "TurboImageNuke", "TurboImageLiveText"]

// Covers what the smoke suite can't see, e.g. animation.
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
