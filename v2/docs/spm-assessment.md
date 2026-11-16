# React Native Swift Package Manager integration: assessment

Date: 2026-11-16. Based on React Native 0.88.1 and 0.89.0-rc.1, read from
source (`react-native/scripts/spm/*`) and tried on TurboImage's example app.

## Verdict

| Question | Answer |
|---|---|
| Can a library with a third-party SwiftPM dependency (Nuke) integrate today? | **Yes**, through a hand-written "self-managed" `Package.swift`. Verified end to end: Debug simulator build, app runs, images load. |
| Is it production-ready? | **Not yet.** It works (Debug and Release simulator builds pass the 7/7 smoke test alongside another self-managed package, `react-native-safe-area-context`). But the manifest depends on the app's build layout, the tooling is partly marked PREVIEW/UNSTABLE, and device builds are untested. |
| Default for TurboImage 2.0.0 | **CocoaPods.** SPM is an opt-in, tracked by a non-blocking CI job (`ios-spm-app`). |
| What would flip the default | RN shipping "V2" autolinking, where library manifests are referenced via `.package(url:)` with no app-relative paths, or a stable remote mode. Plus green Release and device builds in CI. |

## How RN 0.88 SPM works (relevant parts)

- `npx react-native spm add [--deintegrate]` (`scripts/setup-apple-spm.js`) runs Codegen, generates `build/generated/autolinking/Package.swift`, downloads prebuilt React xcframeworks into `build/xcframeworks`, and injects local package references into the `.xcodeproj`.
- Each autolinked library becomes one of two things:
  - **Synthesised from its podspec.** The autolinker writes a wrapper `Package.swift`. Podspec `s.dependency` entries that aren't other RN npm packages are **not wired** (`Unknown dependency "…" — not wired`), so a podspec-only TurboImage would lose Nuke. That rules this path out for us.
  - **Self-managed.** Any `Package.swift` at the npm package root (or `ios/`) without the autogen marker is used as is, through a symlink at `build/generated/autolinking/libs/<SwiftName>`. TurboImage takes this path.
- The Swift name comes from `swiftpmConfig.name` in `package.json`, then from the podspec. We set `"swiftpmConfig": { "name": "TurboImage" }` so the two can't diverge.

## The coupling problem

A self-managed package that compiles against React has to declare the RN
packages itself, and the only local spelling RN 0.88 supports is a path
relative to the **symlink location** inside the app:

```swift
.package(name: "ReactNative",         path: "../../../../xcframeworks"), // <app>/build/xcframeworks
.package(name: "React-GeneratedCode", path: "../../../ios"),             // <app>/build/generated/ios
```

RN's own scaffolder writes exactly these paths (`relFromManifest` in
`scaffold-package-swift.js`). The same version also states the intended fix as
future work: "V2 behavior (future): npm packages with their own Package.swift
use .package(url: ...)". 0.89.0-rc.1 has not changed this.

TurboImage's mitigation, in `Package.swift`:

- It detects whether `../../../../xcframeworks/Package.swift` exists relative to `Context.packageDirectory`.
  - **Present**: it adds the ObjC++ Fabric target and the React products.
  - **Absent**: it builds a standalone product (core, seam, Nuke adapter). CI uses this mode, and so does anyone running `xcodebuild` in the package directory.
- `TURBOIMAGE_SPM_STANDALONE=1` forces standalone mode.

## Risks

1. **Layout drift.** If a future RN moves `build/xcframeworks` or the `libs/` symlink, the Fabric target silently disappears. The app would then fail at runtime ("Unimplemented component"), not at build time. Mitigation: the `ios-spm-app` CI job; TODO: add a smoke test that asserts the component renders.
2. **Remote mode** (`RN_SPM_REMOTE_URL`) isn't handled. In that mode the RN package identity is the remote URL, so our local-path dependency would be wrong. TODO once RN documents the identity contract.
3. **Preview APIs.** Autolinking plugins are explicitly PREVIEW/UNSTABLE. We don't use them.
4. **Untested configurations.** Device builds, and coexistence with other self-managed packages that also depend on Nuke. SwiftPM unifies on one version, so our `exact:` pin could conflict with theirs. Release simulator builds are verified.
5. **Codegen headers.** The Fabric target gets `react/renderer/components/TurboImageSpec/*` from the app-level `ReactAppHeaders` product, the same as CocoaPods' `ReactCodegen`. This works but is another app-scoped dependency.

## Designing for 0.89+ (SPM-first)

The module boundaries are already SwiftPM-native: one language per target,
and no C++ in public headers. When RN supports `.package(url:)`-style library
references, the migration is:

1. Remove the path detection and depend on RN's published package by URL and version.
2. Make SwiftPM the default in the README, and keep the podspec through a deprecation window.
3. Promote `ios-spm-app` to blocking, and add Release and device variants.

## Reproduce

```sh
cd v2 && bun install
mkdir -p .spm-trial && rsync -a --exclude ios/Pods --exclude android apps/example/ .spm-trial/example/
cd .spm-trial/example && node ../../node_modules/react-native/scripts/setup-apple-spm.js add --deintegrate --yes
xcodebuild -project ios/TurboImageExample.xcodeproj -scheme TurboImageExample \
  -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
```

Look for `Self-managed: TurboImage → … (using its own Package.swift)` in the setup output.
