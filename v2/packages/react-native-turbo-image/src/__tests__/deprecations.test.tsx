// Development warnings for deprecated props. A file of its own: each warning
// fires once per module instance, and Jest gives each file a fresh one.

import { describe, expect, it, jest } from '@jest/globals';
import { act } from 'react';
import { create } from 'react-test-renderer';

import { TurboImage } from '../index';
import type { TurboImageProps } from '../index';

jest.mock('../TurboImageViewNativeComponent', () => {
  const { createElement } = require('react') as typeof import('react');
  return {
    __esModule: true,
    default: (props: Record<string, unknown>) => createElement('TurboImageView', props),
  };
});
// `TurboModuleRegistry.getEnforcing` throws outside a native runtime.
jest.mock('../NativeTurboImageModule', () => ({ __esModule: true, default: {} }));

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

const AVATAR = { uri: 'https://cdn.example.com/avatars/ada.jpg' };

// The warnings logged while rendering `props` twice.
function warningsFor(props: Partial<TurboImageProps>): string[] {
  const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
  for (let i = 0; i < 2; i++) {
    act(() => {
      create(<TurboImage source={AVATAR} {...props} />);
    });
  }
  const messages = warn.mock.calls.map((call) => String(call[0]));
  warn.mockRestore();
  return messages;
}

describe('deprecated props', () => {
  it.each<[string, Partial<TurboImageProps>, RegExp]>([
    ['rounded', { rounded: true }, /`rounded` is deprecated/],
    ['indicator', { indicator: { style: 'medium' } }, /`indicator` is deprecated/],
    [
      'placeholder.memoryCacheKey',
      { placeholder: { memoryCacheKey: AVATAR.uri } },
      /`placeholder.memoryCacheKey` is deprecated/,
    ],
    ['format', { format: 'gif' }, /`format` is deprecated/],
    [
      'isProgressiveImageRenderingEnabled',
      { isProgressiveImageRenderingEnabled: true },
      /`isProgressiveImageRenderingEnabled` is deprecated/,
    ],
  ])('%s warns once in development', (_name, props, message) => {
    const warnings = warningsFor(props);
    expect(warnings).toHaveLength(1);
    expect(warnings[0]).toMatch(message);
  });

  it('current props do not warn', () => {
    expect(
      warningsFor({ placeholder: { uri: AVATAR.uri }, style: { borderRadius: 9999 } })
    ).toEqual([]);
  });
});
