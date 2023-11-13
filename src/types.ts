export type ResizeMode = 'contain' | 'cover' | 'stretch' | 'center';
export const resizeMode = {
  contain: 'contain',
  cover: 'cover',
  stretch: 'stretch',
  center: 'center',
} as const;
