# 0005: The core lives inside the npm package

Status: accepted

## Context

A separate `@turbo-image/core` workspace would be the tidy layout. But
SwiftPM forbids target paths outside the package root, CocoaPods needs
sources under the podspec's directory, and the Android Gradle build compiles
from `node_modules`.

## Decision

`cpp/` sits inside `packages/react-native-turbo-image/` and ships in the
npm tarball. `cpp/CMakeLists.txt` is its only build description for the host
tests and Android; `Package.swift` and the podspec compile the same `src/`
and `include/` trees directly. The workspace uses Bun's hoisted linker,
because React Native's Gradle plugin, Metro, Codegen and CocoaPods assume a
flat `node_modules`.

## Consequences

- No copying or symlinking at publish time.
- A new compile definition must be mirrored by hand in `Package.swift` and the podspec. A new source file needs nothing on iOS, except `pod install` in an app that already has Pods.
- The core cannot be consumed without the React Native package.

More: RFC §4.9, §5.
