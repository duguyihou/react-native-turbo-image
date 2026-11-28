// JS-layer tests only; native is covered by cpp/tests and scripts/smoke-*.sh.
module.exports = {
  preset: '@react-native/jest-preset',
  // Native build outputs hold package.json copies that collide in the module map.
  modulePathIgnorePatterns: ['<rootDir>/build/', '<rootDir>/android/build/', '<rootDir>/.build/'],
};
