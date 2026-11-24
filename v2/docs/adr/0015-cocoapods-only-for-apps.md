# 0015: Apps integrate through CocoaPods only; Package.swift is for tests

Status: accepted. Supersedes the SwiftPM opt-in in
[0006](0006-nuke-as-a-vendored-xcframework.md); its vendored-xcframework
decision stands.

## Context

`Package.swift` had two modes:

- **Standalone:** core, seam and Nuke adapter. It builds and tests them without an app, and builds them for tvOS.
- **In-app:** for React Native 0.88's SwiftPM integration. It added the Fabric target, and found React Native through paths relative to a symlink inside the app's build directory.

The in-app mode had problems:

- React Native marks that integration as a preview, and the in-app mode depends on the app's build layout (`docs/spm-assessment.md`).
- The project never recommended it for production.
- It had its own CI job (`ios-spm-app`), and it was a second app-integration path to support for every iOS change.

## Decision

- Apps use CocoaPods.
- `Package.swift` keeps only the standalone mode, for the adapter tests and the tvOS build.
- The npm package no longer ships `Package.swift`, and `swiftpmConfig` is gone from `package.json`, so React Native's SwiftPM autolinker does not pick up a package that has no Fabric target.
- The `ios-spm-app` CI job is removed.

## Consequences

- One iOS integration path to support, test and document.
- Rule 6 still holds, for the sources both manifests build: `Package.swift` still has to build the same native layers with the same Nuke, because the adapter tests run through it.
- An app converted with `npx react-native spm add` cannot use TurboImage 2.0.
- Revisit when React Native references library packages with `.package(url:)`, which `spm-assessment.md` names as the condition. The TODO is in `Package.swift`.

More: `docs/audit/V2_SIMPLIFICATION_PLAN.md` (S2); `docs/spm-assessment.md`.
