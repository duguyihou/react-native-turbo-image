const path = require('path');
const { getDefaultConfig, mergeConfig } = require('@react-native/metro-config');

// Monorepo wiring: Bun hoists every dependency to v2/node_modules, and the
// library is a workspace symlink under packages/. Metro has to watch both
// and resolve from the hoisted root.
const workspaceRoot = path.resolve(__dirname, '../..');

const config = {
  watchFolders: [workspaceRoot],
  resolver: {
    nodeModulesPaths: [
      path.resolve(__dirname, 'node_modules'),
      path.resolve(workspaceRoot, 'node_modules'),
    ],
  },
};

module.exports = mergeConfig(getDefaultConfig(__dirname), config);
