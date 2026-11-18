#!/usr/bin/env bash
# Installs the package the way an app developer gets it, and runs it.
#
# Everything else in this repository tests the workspace copy of the
# library: the example app resolves it through a symlink, with every file on
# disk. That cannot show whether the *published* files are complete. This
# packs the tarball `npm publish` would upload, installs it into a new app
# made from React Native's own template, builds a release app, runs it, and
# waits for the app to report that an image loaded through TurboImage.
#
# The app lives outside the repository on purpose: inside it, Node would
# resolve modules from the workspace's node_modules and hide a missing
# dependency.
#
# Needs network (the template and its dependencies come from npm), a booted
# simulator for ios, and a connected device or emulator for android.
#
# Usage: scripts/test-packed-install.sh <ios|android> [work-dir]
#        work-dir defaults to a new temporary directory; it is left in place
#        so a failed run can be inspected.
# Exit:  0 when the app reports a loaded image, 1 otherwise.

set -euo pipefail

platform="${1:-}"
if [[ "${platform}" != "ios" && "${platform}" != "android" ]]; then
  echo "usage: $0 <ios|android> [work-dir]" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
v2_root="$(cd "${script_dir}/.." && pwd)"
pkg="${v2_root}/packages/react-native-turbo-image"
# shellcheck source=./native-versions.env source-path=SCRIPTDIR
source "${script_dir}/native-versions.env"

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
# The template ships its dot-files under other names; the CLI's `init`
# renames them, and the iOS build needs `.xcode.env`.
mv "${app}/_gitignore" "${app}/.gitignore"
mv "${app}/_watchmanconfig" "${app}/.watchmanconfig"
mv "${app}/ios/_xcode.env" "${app}/ios/.xcode.env"

# The one Android change the migration guide asks of every app: the template
# ships a Kotlin older than Coil needs. Both lines matter. The template
# declares the Kotlin Gradle plugin without a version, so the `kotlinVersion`
# property alone does not change the compiler.
# shellcheck disable=SC2016 # `$kotlinVersion` is Gradle's variable, written literally.
sed -i.bak -E \
  -e "s/kotlinVersion = \"[^\"]+\"/kotlinVersion = \"${KOTLIN_VERSION}\"/" \
  -e 's/classpath\("org.jetbrains.kotlin:kotlin-gradle-plugin"\)/classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")/' \
  "${app}/android/build.gradle"
rm "${app}/android/build.gradle.bak"
grep -q "kotlinVersion = \"${KOTLIN_VERSION}\"" "${app}/android/build.gradle"
# shellcheck disable=SC2016 # as above
grep -qF 'kotlin-gradle-plugin:$kotlinVersion' "${app}/android/build.gradle"

# A bundled image, so the check needs no server: it goes through the same
# native view, core and loader as a remote one.
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
# Type-check the app against the package's built declarations, as a
# consumer's `tsc` would.
(cd "${app}" && npx tsc --noEmit)
echo "Installed into a new React Native ${REACT_NATIVE_VERSION} app; types check"

# --- 3. build, run, wait for the report -------------------------------------

timeout_s=90
line=""

if [[ "${platform}" == "android" ]]; then
  adb="${ANDROID_HOME:-${HOME}/Library/Android/sdk}/platform-tools/adb"
  [[ -x "${adb}" ]] || adb="adb"
  "${adb}" wait-for-device
  abi="$("${adb}" shell getprop ro.product.cpu.abi | tr -d '\r')"
  (cd "${app}/android" && ./gradlew assembleRelease --console=plain -q "-PreactNativeArchitectures=${abi}")
  "${adb}" install -r "${app}/android/app/build/outputs/apk/release/app-release.apk" > /dev/null
  "${adb}" logcat -c
  "${adb}" shell am start -n com.helloworld/.MainActivity > /dev/null
  for ((elapsed = 0; elapsed < timeout_s; elapsed += 2)); do
    line="$("${adb}" logcat -d -s ReactNativeJS:V | grep -o 'TURBOIMAGE_PACKED .*' || true)"
    [[ -n "${line}" ]] && break
    sleep 2
  done
  "${adb}" uninstall com.helloworld > /dev/null || true
else
  udid="$(xcrun simctl list devices booted | grep -m1 -oE '[0-9A-F-]{36}' || true)"
  if [[ -z "${udid}" ]]; then
    echo "FAIL: no booted simulator" >&2
    exit 1
  fi
  (cd "${app}/ios" && pod install > "${work}/pod-install.log" 2>&1) || {
    tail -n 20 "${work}/pod-install.log" >&2
    exit 1
  }
  xcodebuild -workspace "${app}/ios/HelloWorld.xcworkspace" -scheme HelloWorld \
    -configuration Release -sdk iphonesimulator -destination "id=${udid}" \
    -derivedDataPath "${app}/ios/build" build > "${work}/xcodebuild.log" 2>&1 || {
    grep -E "error:" "${work}/xcodebuild.log" | head -n 20 >&2
    exit 1
  }
  built="${app}/ios/build/Build/Products/Release-iphonesimulator/HelloWorld.app"
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
