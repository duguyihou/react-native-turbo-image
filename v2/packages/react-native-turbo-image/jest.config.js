// Unit tests for the JS layer (src/index.tsx): everything it does before a
// prop reaches native. Native behaviour is covered by the C++ GoogleTests
// (cpp/tests) and the on-device smoke tests (scripts/smoke-*.sh).
module.exports = {
  preset: '@react-native/jest-preset',
  // Native build outputs contain copies of package.json and JS that would
  // otherwise be crawled (and can collide in Jest's module map).
  modulePathIgnorePatterns: ['<rootDir>/build/', '<rootDir>/android/build/', '<rootDir>/.build/'],
};
