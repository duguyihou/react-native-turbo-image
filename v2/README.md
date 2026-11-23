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
bun run test:ios                    # Nuke adapter tests on an iPhone simulator
bun run test:android                # Coil adapter tests on the connected device or emulator

# iOS (CocoaPods)
bun run vendor:nuke                 # builds Nuke.xcframework and NukeUI.xcframework from the pinned tag
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

## Releasing a pre-release

`.github/workflows/v2-publish.yml` publishes to npm under the `next` dist-tag,
so `npm install react-native-turbo-image` keeps giving 1.x.

1. Set the version in `packages/react-native-turbo-image/package.json`
   (a pre-release, such as `2.0.0-beta.1`; the workflow refuses a stable one)
   and get that commit through `v2 CI` (push it to the pull request).
2. Tag it and push the tag:

   ```sh
   git tag v2.0.0-beta.1 && git push origin v2.0.0-beta.1
   ```

The workflow checks the tag against `package.json` and that `v2 CI` passed on
the commit, builds the Nuke frameworks, and publishes with npm's trusted
publishing, which adds a provenance attestation. To rehearse, run the workflow
by hand from the Actions tab: that is a dry run unless told otherwise.

One-time setup on npmjs.com: react-native-turbo-image → Settings → Trusted
publisher → GitHub Actions, repository `duguyihou/react-native-turbo-image`,
workflow `v2-publish.yml`.
