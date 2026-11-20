#!/usr/bin/env bash
# Prepares a throwaway copy of the v2 workspace on another React Native
# version, for evaluating upcoming releases without touching production pins
# (RFC rule 8).
#
# The copy goes to v2/tmp/eval-rn-<version>/. It takes the target version's
# own app template (@react-native-community/template) and applies only what
# the example app depends on:
#   * every react / react-native / @react-native/* / CLI version from the
#     template's package.json, including dependencies the template adds,
#   * kotlinVersion and ndkVersion from the template's android/build.gradle,
#     but never a Kotlin below 2.3 (Coil 3.6.3 needs >= 2.3; see RFC §6.2),
#   * the template's MainActivity.kt.
# It then runs `bun install`. Building and smoke-testing are left to the
# caller, because CI runs them per platform.
#
# Usage: scripts/eval-rn-version.sh <react-native-version>
# Prints the prepared directory on the last line of stdout.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <react-native-version>" >&2
  exit 2
fi
rn_version="$1"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
v2_root="$(cd "${script_dir}/.." && pwd)"
out="${v2_root}/tmp/eval-rn-${rn_version}"
template_dir="${v2_root}/tmp/template-${rn_version}"

# Template versions for RCs carry a hash suffix (0.89.0-rc.1-8daacc8), so
# resolve the exact published version first.
# shellcheck disable=SC2016 # ${want} below is a JS template literal, not shell.
template_version="$(npm view @react-native-community/template versions --json \
  | node -e '
      const want = process.argv[1];
      const all = JSON.parse(require("fs").readFileSync(0, "utf8"));
      const hit = all.filter(v => v === want || v.startsWith(want + "-")).pop();
      if (!hit) { console.error(`no template for react-native ${want}`); process.exit(1); }
      console.log(hit);
    ' "${rn_version}")"
echo "Using @react-native-community/template@${template_version}" >&2

rm -rf "${template_dir}" "${out}"
mkdir -p "${template_dir}" "${out}"
(cd "${template_dir}" && npm pack --silent "@react-native-community/template@${template_version}" > /dev/null)
tar -xzf "${template_dir}"/*.tgz -C "${template_dir}"
template="${template_dir}/package/template"

rsync -a \
  --exclude node_modules --exclude tmp --exclude .spm-trial \
  --exclude 'build/' --exclude Pods --exclude .gradle --exclude .cxx \
  --exclude TurboImageExample.xcworkspace --exclude Podfile.lock --exclude bun.lock \
  "${v2_root}/" "${out}/"
# The vendored Nuke.xcframework is gitignored build output; reuse it if built.
if [[ -d "${v2_root}/packages/react-native-turbo-image/ios/vendor" ]]; then
  cp -R "${v2_root}/packages/react-native-turbo-image/ios/vendor" \
    "${out}/packages/react-native-turbo-image/ios/"
fi

node - "${template}" "${out}" <<'NODE'
const fs = require('fs');
const path = require('path');
const [template, out] = process.argv.slice(2);
const read = p => fs.readFileSync(p, 'utf8');
const isRnPackage = name =>
  name === 'react' || name === 'react-native' ||
  name.startsWith('@react-native/') || name.startsWith('@react-native-community/cli');

// package.json: align every RN-family version, adding new ones (e.g. RN 0.89
// moved `bundle` into @react-native/community-cli-plugin).
const tpl = JSON.parse(read(path.join(template, 'package.json')));
const appPkgPath = path.join(out, 'apps/example/package.json');
const app = JSON.parse(read(appPkgPath));
for (const field of ['dependencies', 'devDependencies']) {
  for (const [name, version] of Object.entries(tpl[field] ?? {})) {
    if (isRnPackage(name)) app[field][name] = version;
  }
}
fs.writeFileSync(appPkgPath, JSON.stringify(app, null, 2) + '\n');

const libPkgPath = path.join(out, 'packages/react-native-turbo-image/package.json');
const lib = JSON.parse(read(libPkgPath));
lib.devDependencies['react-native'] = tpl.dependencies['react-native'];
fs.writeFileSync(libPkgPath, JSON.stringify(lib, null, 2) + '\n');

// android/build.gradle: NDK as the template says; Kotlin never below 2.3.
const tplGradle = read(path.join(template, 'android/build.gradle'));
const pick = key => (tplGradle.match(new RegExp(`${key} = "([^"]+)"`)) ?? [])[1];
const ndk = pick('ndkVersion');
let kotlin = pick('kotlinVersion');
const [major, minor] = kotlin.split('.').map(Number);
if (major * 1000 + minor < 2003) {
  console.error(`template Kotlin ${kotlin} < 2.3; keeping the workspace's Kotlin`);
  kotlin = null;
}
const gradlePath = path.join(out, 'apps/example/android/build.gradle');
let gradle = read(gradlePath).replace(/ndkVersion = "[^"]+"/, `ndkVersion = "${ndk}"`);
if (kotlin) gradle = gradle.replace(/kotlinVersion = "[^"]+"/, `kotlinVersion = "${kotlin}"`);
fs.writeFileSync(gradlePath, gradle);

// MainActivity: templates change delegate wiring between versions.
const activity = 'android/app/src/main/java/com/helloworld/MainActivity.kt';
const src = read(path.join(template, activity))
  .replace(/package com\.helloworld/, 'package com.turboimageexample')
  .replace(/"HelloWorld"/, '"TurboImageExample"');
fs.writeFileSync(
  path.join(out, 'apps/example/android/app/src/main/java/com/turboimageexample/MainActivity.kt'),
  src,
);
console.error(`react-native ${tpl.dependencies['react-native']}, ndk ${ndk}, kotlin ${kotlin ?? '(kept)'}`);
NODE

(cd "${out}" && bun install > /dev/null)
echo "${out}"
