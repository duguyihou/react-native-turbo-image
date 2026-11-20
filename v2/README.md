# TurboImage 2.0 (in development)

New Architecture-only rewrite of `react-native-turbo-image`. 1.x continues at the repository root.

- Architecture: [`docs/architecture.md`](docs/architecture.md)
- Decisions and their reasons: [`docs/adr/`](docs/adr/README.md)
- Detailed behaviour: [`docs/rfc/0001-turbo-image-2-native-toolchain.md`](docs/rfc/0001-turbo-image-2-native-toolchain.md)
- Dependency matrix: [`docs/compatibility-matrix.md`](docs/compatibility-matrix.md)
- React Native SwiftPM assessment: [`docs/spm-assessment.md`](docs/spm-assessment.md)
- Migrating an app from 1.x: [`docs/migration-guide.md`](docs/migration-guide.md)
- Migration plan from 1.x: [`docs/migration-plan.md`](docs/migration-plan.md)

## Quick start

```sh
cd v2
bun install                         # hoisted node_modules (see bunfig.toml)
bun run check:versions              # manifests agree with scripts/native-versions.env
bun run test                        # JS unit tests (Jest) for src/index.tsx
bun run test:core                   # C++ core + GoogleTest

# iOS (CocoaPods)
bun run vendor:nuke                 # builds Nuke.xcframework from the pinned tag
(cd apps/example/ios && pod install)
bun run example:ios

# Android
bun run example:android             # debug
(cd apps/example && bun run build:android:release)   # R8 release build
```

After changing the Codegen spec (`src/TurboImageViewNativeComponent.ts`),
re-run `pod install`: iOS Codegen runs there, not during the Xcode build.

Run the app with `cd apps/example && npx react-native start`, then launch it
from Xcode or Android Studio, or with `npx react-native run-ios` / `run-android`.
