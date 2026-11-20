// swift-tools-version: 6.0

import PackageDescription

let reactNativeHeaders: [Target.Dependency] = [
  .product(name: "ReactHeaders", package: "ReactNative"),
  .product(name: "ReactNativeHeaders", package: "ReactNative"),
  .product(name: "ReactNativeDependenciesHeaders", package: "ReactNative"),
]

let package = Package(
  name: "react-native-turbo-image",
  platforms: [.iOS("15.1"), .tvOS("15.1")],
  products: [
    .library(name: "TurboImage", targets: ["TurboImage", "TurboImageObjC"]),
  ],
  dependencies: [
    .package(name: "ReactNative", path: "../../../../xcframeworks"),
    .package(url: "https://github.com/kean/Nuke.git", "12.8.0"..<"13.0.0"),
    .package(url: "https://github.com/kaishin/Gifu.git", "3.3.1"..<"4.0.0"),
    .package(url: "https://github.com/onevcat/APNGKit.git", from: "2.3.0"),
  ],
  targets: [
    .target(
      name: "TurboImageObjC",
      dependencies: reactNativeHeaders,
      path: "ios",
      sources: ["TurboImageViewManager.m"],
      publicHeadersPath: "Utilities",
      linkerSettings: [
        .linkedFramework("UIKit"),
      ]
    ),
    .target(
      name: "TurboImage",
      dependencies: reactNativeHeaders + [
        .product(name: "Nuke", package: "Nuke"),
        .product(name: "NukeUI", package: "Nuke"),
        .product(name: "Gifu", package: "Gifu"),
        .product(name: "APNGKit", package: "APNGKit"),
      ],
      path: "ios",
      sources: [
        "CoreSVG.swift",
        "Extensions/String+Extensions.swift",
        "Extensions/UIImage+Blurhash.swift",
        "Extensions/UIImage+BorderRadius.swift",
        "Extensions/UIImage+Thumbhash.swift",
        "TurboImageView.swift",
        "TurboImageViewManager.swift",
        "Utilities/CachePolicy.swift",
        "Utilities/ResizeMode.swift",
      ],
      swiftSettings: [.swiftLanguageMode(.v5)],
      linkerSettings: [
        .linkedFramework("UIKit"),
        .linkedFramework("VisionKit", .when(platforms: [.iOS])),
      ]
    ),
  ],
  cxxLanguageStandard: .cxx20
)
