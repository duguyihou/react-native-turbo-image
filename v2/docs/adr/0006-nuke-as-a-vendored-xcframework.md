# 0006: CocoaPods gets Nuke as a vendored xcframework; CocoaPods stays the default

Status: accepted

## Context

Nuke's last release on CocoaPods trunk is 9.5.0. React Native's SwiftPM
integration works with a hand-written `Package.swift` but is marked preview
and needs paths relative to the app's build directory.

## Decision

CocoaPods builds link xcframeworks (Nuke, and NukeUI since
[ADR 0012](0012-nuke-plays-animations-on-ios.md)) built reproducibly from the same Nuke
tag SwiftPM resolves (`scripts/build-nuke-xcframework.sh`), shipped in the
npm tarball. CocoaPods is the default integration for 2.0.0; SwiftPM is a
supported opt-in with its own CI job.

## Consequences

- Both paths use the same Nuke, checked by `scripts/check-native-versions.sh`.
- The tarball carries the frameworks: about 21 MB with dSYMs and the tvOS slices (Nuke 14.0.0 with NukeUI; 14.2 MB without NukeUI, 9.7 MB with 13.2.3).
- The dSYMs are three quarters of that (about 4.8 MB without them) and are kept on purpose (2026-11-23): CocoaPods copies them into the app's archive, so a crash inside Nuke symbolicates with no extra step. Shipping them as a release asset instead was considered and declined. The tvOS slices stay too; without them Apple TV apps cannot use the CocoaPods path.
- The vendored Nuke framework carries Nuke's privacy manifest, which Nuke ships from 14.0 on (no tracking, no collected data, no required-reason APIs).
- Nuke 14 needs iOS and tvOS 16.0, so TurboImage does too: above React Native's 15.1, and an app has to raise its deployment target. Accepted on 2026-11-23, while 2.0 is an alpha, over staying on 13.x.
- Nuke 14 needs Swift 6.4, so building TurboImage needs Xcode 27 on either path.

More: RFC §6.1, §6.3, §7; `docs/spm-assessment.md`.
