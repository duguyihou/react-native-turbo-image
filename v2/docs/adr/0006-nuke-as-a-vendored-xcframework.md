# 0006: CocoaPods gets Nuke as a vendored xcframework; CocoaPods stays the default

Status: accepted

## Context

Nuke's last release on CocoaPods trunk is 9.5.0. React Native's SwiftPM
integration works with a hand-written `Package.swift` but is marked preview
and needs paths relative to the app's build directory.

## Decision

CocoaPods builds link an xcframework built reproducibly from the same Nuke
tag SwiftPM resolves (`scripts/build-nuke-xcframework.sh`), shipped in the
npm tarball. CocoaPods is the default integration for 2.0.0; SwiftPM is a
supported opt-in with its own CI job.

## Consequences

- Both paths use the same Nuke, checked by `scripts/check-native-versions.sh`.
- The tarball carries the framework: about 9.7 MB with dSYMs and the tvOS slices.
- Nuke ships no privacy manifest, so the vendored framework has none.
- Nuke 14 raises the iOS floor to 16.0, above React Native's 15.1, so it is evaluated in CI and not adopted.

More: RFC §6.1, §6.3, §7; `docs/spm-assessment.md`.
