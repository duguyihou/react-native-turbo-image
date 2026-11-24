// Light and dark palettes, close to the platform's grouped-list colours, so
// the images are the only colourful thing on screen. Follows the system
// appearance; there is no in-app switch.
import { Platform, useColorScheme } from 'react-native';

export type Theme = {
  dark: boolean;
  background: string;
  card: string;
  text: string;
  secondaryText: string;
  separator: string;
  accent: string;
  // Behind every image, so letterboxing (contain, center) is visible.
  imageBackground: string;
  danger: string;
  success: string;
};

const LIGHT: Theme = {
  dark: false,
  background: '#f2f2f7',
  card: '#ffffff',
  text: '#000000',
  secondaryText: '#6c6c70',
  separator: '#c6c6c8',
  accent: '#007aff',
  imageBackground: '#e5e5ea',
  danger: '#d70015',
  success: '#248a3d',
};

const DARK: Theme = {
  dark: true,
  background: '#000000',
  card: '#1c1c1e',
  text: '#ffffff',
  secondaryText: '#98989f',
  separator: '#38383a',
  accent: '#0a84ff',
  imageBackground: '#2c2c2e',
  danger: '#ff453a',
  success: '#30d158',
};

export function useTheme(): Theme {
  return useColorScheme() === 'dark' ? DARK : LIGHT;
}

export const MONOSPACE = Platform.select({ ios: 'Menlo', default: 'monospace' });

export const SPACING = 16;
