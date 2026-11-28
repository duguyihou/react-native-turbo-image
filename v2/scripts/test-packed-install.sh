#!/usr/bin/env bash
# Packs the npm tarball, installs it into a new app from the RN template
# (react-native-tvos for `tvos`), builds a release app, and waits for it to
# report an image loaded. Checks the *published* files are complete. The app
# lives outside the repo so the workspace's node_modules can't hide a gap.
#
# Needs network, and a booted simulator (ios), Apple TV simulator (tvos), or
# connected device (android).
#
# Usage: scripts/test-packed-install.sh <ios|tvos|android> [work-dir]
#        work-dir defaults to a new temp dir, kept for inspection.
# Exit:  0 on a loaded image, 1 on failure, 2 on bad usage; 3 (tvos) when it
#        built but no Apple TV simulator is booted.

set -euo pipefail

platform="${1:-}"
if [[ "${platform}" != "ios" && "${platform}" != "tvos" && "${platform}" != "android" ]]; then
  echo "usage: $0 <ios|tvos|android> [work-dir]" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
v2_root="$(cd "${script_dir}/.." && pwd)"
pkg="${v2_root}/packages/react-native-turbo-image"
# shellcheck source=./native-versions.env source-path=SCRIPTDIR
source "${script_dir}/native-versions.env"

# Fork versions are <RN version>-<revision>; its template lags behind RN.
tvos_fork_version="${REACT_NATIVE_VERSION}-0"
tvos_template_version="0.83.0-0"

work="${2:-$(mktemp -d "${TMPDIR:-/tmp}/turboimage-packed-install.XXXXXX")}"
mkdir -p "${work}"
work="$(cd "${work}" && pwd)"
case "${work}/" in
  "${v2_root}/"* | "$(cd "${v2_root}/.." && pwd)/"*)
    echo "FAIL: the work directory must be outside the repository (got ${work})" >&2
    exit 2
    ;;
esac
app="${work}/app"
echo "Working in ${work}"

# --- 1. the tarball ---------------------------------------------------------

rm -f "${work}"/react-native-turbo-image-*.tgz
(cd "${pkg}" && npm pack --silent --pack-destination "${work}" > /dev/null)
tarball="$(ls "${work}"/react-native-turbo-image-*.tgz)"
echo "Packed $(basename "${tarball}") ($(du -h "${tarball}" | cut -f1 | tr -d ' '))"

# --- 2. a new app from the template -----------------------------------------

rm -rf "${app}" "${work}/template"
mkdir -p "${work}/template"
(cd "${work}/template" \
  && npm pack --silent "@react-native-community/template@${REACT_NATIVE_VERSION}" > /dev/null \
  && tar -xzf ./*.tgz)
cp -R "${work}/template/package/template" "${app}"
# Rename the template's dot-files, as the CLI's `init` would.
mv "${app}/_gitignore" "${app}/.gitignore"
mv "${app}/_watchmanconfig" "${app}/.watchmanconfig"
mv "${app}/ios/_xcode.env" "${app}/ios/.xcode.env"

if [[ "${platform}" == "tvos" ]]; then
  # Take only the iOS project from the tvOS template; keep the RN template's
  # JS side so it matches the RN version under test.
  (cd "${work}/template" \
    && mkdir tv \
    && npm pack --silent --pack-destination tv "@react-native-tvos/template-tv@${tvos_template_version}" > /dev/null \
    && tar -xzf tv/*.tgz -C tv)
  rm -rf "${app}/ios"
  cp -R "${work}/template/tv/package/template/ios" "${app}/ios"
  mv "${app}/ios/_xcode.env" "${app}/ios/.xcode.env"
  # The tvOS SDK 27 traps apps without a scene lifecycle, which the tvOS
  # template lacks; borrow the RN template's delegates and scene manifest
  # (in AppDelegate.swift, the only file the tvOS project compiles).
  # TODO: drop once a tvOS template with a scene delegate is published.
  rn_template_app="${work}/template/package/template/ios/HelloWorld"
  cat "${rn_template_app}/AppDelegate.swift" "${rn_template_app}/SceneDelegate.swift" \
    > "${app}/ios/HelloWorld/AppDelegate.swift"
  scene_manifest="$(plutil -extract UIApplicationSceneManifest xml1 -o - "${rn_template_app}/Info.plist")"
  plutil -insert UIApplicationSceneManifest -xml "${scene_manifest}" "${app}/ios/HelloWorld/Info.plist"
  # Install the fork as `react-native`. Drop new-app-screen: it peers on the
  # exact upstream version, and the app below doesn't use it.
  sed -i.bak -E \
    -e "s|\"react-native\": \"${REACT_NATIVE_VERSION}\"|\"react-native\": \"npm:react-native-tvos@${tvos_fork_version}\"|" \
    -e '/@react-native\/new-app-screen/d' \
    "${app}/package.json"
  rm "${app}/package.json.bak"
  grep -q "npm:react-native-tvos@${tvos_fork_version}" "${app}/package.json"
  # A fork dependency peers on upstream RN, so npm nests a second RN copy,
  # which breaks Fabric components ("View config getter callback ... must be
  # a function"). `overrides` forces one copy; spelled out because npm can't
  # resolve `$react-native` to an alias.
  # shellcheck disable=SC2016 # JavaScript, not shell: nothing to expand.
  node -e '
    const fs = require("fs");
    const [file, spec] = process.argv.slice(1);
    const manifest = JSON.parse(fs.readFileSync(file, "utf8"));
    manifest.overrides = { ...manifest.overrides, "react-native": spec };
    fs.writeFileSync(file, JSON.stringify(manifest, null, 2) + "\n");
  ' "${app}/package.json" "npm:react-native-tvos@${tvos_fork_version}"
fi

# Migration-guide step: raise Kotlin for Coil. The plugin line needs the
# version too, or the compiler stays on the old Kotlin.
# shellcheck disable=SC2016 # `$kotlinVersion` is Gradle's variable, written literally.
sed -i.bak -E \
  -e "s/kotlinVersion = \"[^\"]+\"/kotlinVersion = \"${KOTLIN_VERSION}\"/" \
  -e 's/classpath\("org.jetbrains.kotlin:kotlin-gradle-plugin"\)/classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")/' \
  "${app}/android/build.gradle"
rm "${app}/android/build.gradle.bak"
grep -q "kotlinVersion = \"${KOTLIN_VERSION}\"" "${app}/android/build.gradle"
# shellcheck disable=SC2016 # as above
grep -qF 'kotlin-gradle-plugin:$kotlinVersion' "${app}/android/build.gradle"

# Migration-guide step: raise the iOS/tvOS target to 16.0 (Nuke 14), in both
# the Podfile and the Xcode project.
sed -i.bak -E \
  -e "s/^platform :(ios|tvos), .*/platform :\1, '16.0'/" \
  "${app}/ios/Podfile"
rm "${app}/ios/Podfile.bak"
grep -qE "^platform :(ios|tvos), '16.0'" "${app}/ios/Podfile"
sed -i.bak -E \
  -e 's/(IPHONEOS|TVOS)_DEPLOYMENT_TARGET = [0-9.]+;/\1_DEPLOYMENT_TARGET = 16.0;/' \
  "${app}/ios"/*.xcodeproj/project.pbxproj
rm "${app}/ios"/*.xcodeproj/project.pbxproj.bak

# A bundled image, so no server is needed; it uses the same native path.
cp "${v2_root}/apps/example/assets/local-fixture.png" "${app}/fixture.png"
cat > "${app}/App.tsx" <<'TSX'
// Written by scripts/test-packed-install.sh: loads one image through the
// installed package and reports the outcome in a single log line.
import { useEffect, useRef } from 'react';
import { TurboImage } from 'react-native-turbo-image';

const report = (result: object) =>
  // console.error: release builds on iOS drop anything quieter.
  console.error(`TURBOIMAGE_PACKED ${JSON.stringify(result)}`);

export default function App() {
  const reported = useRef(false);
  const once = (result: object) => {
    if (!reported.current) {
      reported.current = true;
      report(result);
    }
  };
  useEffect(() => {
    const timer = setTimeout(() => once({ ok: false, why: 'timeout' }), 30_000);
    return () => clearTimeout(timer);
    // oxlint-disable-next-line react/exhaustive-deps
  }, []);
  return (
    <TurboImage
      style={{ width: 240, height: 160, marginTop: 120, alignSelf: 'center' }}
      source={require('./fixture.png')}
      onSuccess={(e) =>
        // The module call proves the TurboModule is linked too.
        TurboImage.clearMemoryCache().then(
          () => once({ ok: true, width: e.nativeEvent.width, height: e.nativeEvent.height }),
          (error) => once({ ok: false, why: `module: ${error}` })
        )
      }
      onFailure={(e) => once({ ok: false, why: `${e.nativeEvent.code}: ${e.nativeEvent.error}` })}
    />
  );
}
TSX

(cd "${app}" && npm install --no-audit --no-fund --loglevel=error)
(cd "${app}" && npm install --no-audit --no-fund --loglevel=error "${tarball}")
# Type-check against the package's built declarations.
(cd "${app}" && npx tsc --noEmit)
if [[ "${platform}" == "tvos" ]]; then
  echo "Installed into a new react-native-tvos ${tvos_fork_version} app; types check"
else
  echo "Installed into a new React Native ${REACT_NATIVE_VERSION} app; types check"
fi

# --- 3. build, run, wait for the report -------------------------------------

timeout_s=90
line=""

if [[ "${platform}" == "android" ]]; then
  adb="${ANDROID_HOME:-${HOME}/Library/Android/sdk}/platform-tools/adb"
  [[ -x "${adb}" ]] || adb="adb"
  "${adb}" wait-for-device
  abi="$("${adb}" shell getprop ro.product.cpu.abi | tr -d '\r')"
  (cd "${app}/android" && ./gradlew assembleRelease --console=plain -q "-PreactNativeArchitectures=${abi}")
  # Uninstall rather than `install -r` (see smoke-android.sh).
  # `|| true`: normally there is nothing to uninstall.
  "${adb}" uninstall com.helloworld > /dev/null 2>&1 || true
  "${adb}" install "${app}/android/app/build/outputs/apk/release/app-release.apk" > /dev/null
  "${adb}" logcat -c
  "${adb}" shell am start -n com.helloworld/.MainActivity > /dev/null
  for ((elapsed = 0; elapsed < timeout_s; elapsed += 2)); do
    line="$("${adb}" logcat -d -s ReactNativeJS:V | grep -o 'TURBOIMAGE_PACKED .*' || true)"
    [[ -n "${line}" ]] && break
    sleep 2
  done
  "${adb}" uninstall com.helloworld > /dev/null || true
else
  # Pick a booted simulator of the right kind.
  if [[ "${platform}" == "tvos" ]]; then
    sdk="appletvsimulator"
    udid="$(xcrun simctl list devices booted | grep 'Apple TV' | grep -m1 -oE '[0-9A-F-]{36}' || true)"
    destination="${udid:+id=${udid}}"
    # Still build without a simulator: nothing else links the view against the fork.
    destination="${destination:-generic/platform=tvOS Simulator}"
  else
    sdk="iphonesimulator"
    udid="$(xcrun simctl list devices booted | grep -v 'Apple TV' | grep -m1 -oE '[0-9A-F-]{36}' || true)"
    if [[ -z "${udid}" ]]; then
      echo "FAIL: no booted simulator" >&2
      exit 1
    fi
    destination="id=${udid}"
  fi
  (cd "${app}/ios" && pod install > "${work}/pod-install.log" 2>&1) || {
    tail -n 20 "${work}/pod-install.log" >&2
    exit 1
  }
  xcodebuild -workspace "${app}/ios/HelloWorld.xcworkspace" -scheme HelloWorld \
    -configuration Release -sdk "${sdk}" -destination "${destination}" \
    -derivedDataPath "${app}/ios/build" build > "${work}/xcodebuild.log" 2>&1 || {
    grep -E "error:" "${work}/xcodebuild.log" | head -n 20 >&2
    exit 1
  }
  if [[ -z "${udid}" ]]; then
    echo "BUILT, NOT RUN (tvos, packed install): no booted Apple TV simulator" >&2
    exit 3
  fi
  built="${app}/ios/build/Build/Products/Release-${sdk}/HelloWorld.app"
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${built}/Info.plist")"
  xcrun simctl uninstall "${udid}" "${bundle_id}" 2> /dev/null || true
  xcrun simctl install "${udid}" "${built}"
  log_file="${work}/simulator.log"
  xcrun simctl spawn "${udid}" log stream --style compact \
    --predicate 'eventMessage CONTAINS "TURBOIMAGE_PACKED"' > "${log_file}" 2>&1 &
  log_pid=$!
  trap 'kill ${log_pid} 2> /dev/null || true' EXIT
  xcrun simctl launch "${udid}" "${bundle_id}" > /dev/null
  for ((elapsed = 0; elapsed < timeout_s; elapsed += 2)); do
    line="$(grep -o 'TURBOIMAGE_PACKED .*' "${log_file}" || true)"
    [[ -n "${line}" ]] && break
    sleep 2
  done
  xcrun simctl uninstall "${udid}" "${bundle_id}" 2> /dev/null || true
fi

if [[ -z "${line}" ]]; then
  echo "FAIL (${platform}): the app did not report within ${timeout_s}s" >&2
  exit 1
fi
echo "${line}"
if [[ "${line}" == *'"ok":true'* ]]; then
  echo "PASS (${platform}, packed install)"
else
  echo "FAIL (${platform}, packed install)" >&2
  exit 1
fi
