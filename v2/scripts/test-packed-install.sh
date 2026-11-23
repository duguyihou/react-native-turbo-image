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
# `tvos` does the same against react-native-tvos, the fork Apple TV apps
# use in place of React Native (see step 2 for how its app is put together).
#
# Needs network (the template and its dependencies come from npm), a booted
# simulator for ios, a booted Apple TV simulator for tvos, and a connected
# device or emulator for android.
#
# Usage: scripts/test-packed-install.sh <ios|tvos|android> [work-dir]
#        work-dir defaults to a new temporary directory; it is left in place
#        so a failed run can be inspected.
# Exit:  0 when the app reports a loaded image, 1 otherwise. tvos only: 3
#        when the app built but no Apple TV simulator is booted to run it on
#        (Xcode does not install the tvOS runtime by default).

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

# react-native-tvos numbers its releases <React Native version>-<revision>.
# Its app template is published less often than the fork itself, so the
# newest one is older than the React Native we test against.
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
# The template ships its dot-files under other names; the CLI's `init`
# renames them, and the iOS build needs `.xcode.env`.
mv "${app}/_gitignore" "${app}/.gitignore"
mv "${app}/_watchmanconfig" "${app}/.watchmanconfig"
mv "${app}/ios/_xcode.env" "${app}/ios/.xcode.env"

if [[ "${platform}" == "tvos" ]]; then
  # An Apple TV app is the same app with a tvOS Xcode project and Podfile,
  # and with `react-native` installed from the fork. Take the native project
  # from the tvOS template and keep everything else (dependency versions,
  # TypeScript and Babel setup) from the React Native template above, so the
  # JavaScript side matches the React Native version under test.
  (cd "${work}/template" \
    && mkdir tv \
    && npm pack --silent --pack-destination tv "@react-native-tvos/template-tv@${tvos_template_version}" > /dev/null \
    && tar -xzf tv/*.tgz -C tv)
  rm -rf "${app}/ios"
  cp -R "${work}/template/tv/package/template/ios" "${app}/ios"
  mv "${app}/ios/_xcode.env" "${app}/ios/.xcode.env"
  # The fork is installed under React Native's name, as its README directs.
  # `@react-native/new-app-screen` goes because it pins the exact upstream
  # version as a peer, which the fork's version can never equal; the app
  # written below does not use it.
  sed -i.bak -E \
    -e "s|\"react-native\": \"${REACT_NATIVE_VERSION}\"|\"react-native\": \"npm:react-native-tvos@${tvos_fork_version}\"|" \
    -e '/@react-native\/new-app-screen/d' \
    "${app}/package.json"
  rm "${app}/package.json.bak"
  grep -q "npm:react-native-tvos@${tvos_fork_version}" "${app}/package.json"
fi

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

# The one iOS change the migration guide asks of every app: the templates
# target React Native's floor (15.1), below the 16.0 TurboImage's pod
# declares for Nuke 14, and `pod install` refuses the lower target. The
# Podfile decides the pods' target, the project the app's own.
sed -i.bak -E \
  -e "s/^platform :(ios|tvos), .*/platform :\1, '16.0'/" \
  "${app}/ios/Podfile"
rm "${app}/ios/Podfile.bak"
grep -qE "^platform :(ios|tvos), '16.0'" "${app}/ios/Podfile"
sed -i.bak -E \
  -e 's/(IPHONEOS|TVOS)_DEPLOYMENT_TARGET = [0-9.]+;/\1_DEPLOYMENT_TARGET = 16.0;/' \
  "${app}/ios"/*.xcodeproj/project.pbxproj
rm "${app}/ios"/*.xcodeproj/project.pbxproj.bak

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
  # Uninstall first rather than `install -r`, as smoke-android.sh does: a
  # run that was interrupted before the uninstall below leaves the app
  # behind, and `install -r` then needs room for both APKs at once.
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
  # Both kinds of simulator can be booted at once; take one of the right kind.
  if [[ "${platform}" == "tvos" ]]; then
    sdk="appletvsimulator"
    udid="$(xcrun simctl list devices booted | grep 'Apple TV' | grep -m1 -oE '[0-9A-F-]{36}' || true)"
    destination="${udid:+id=${udid}}"
    # Without a simulator the build is still worth having: it compiles and
    # links the Fabric view against the fork, which nothing else does.
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
