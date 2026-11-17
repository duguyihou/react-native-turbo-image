// Unit tests for the JS layer: what <TurboImage> and its statics do before
// anything reaches native. The native view and the TurboModule are replaced
// by mocks, so these tests assert the props and arguments native *receives*.

import { afterEach, beforeEach, describe, expect, it, jest } from '@jest/globals';
import { act } from 'react';
import type { ComponentType } from 'react';
import { ActivityIndicator, Image, StyleSheet, View } from 'react-native';
import { create } from 'react-test-renderer';
import type { ReactTestRenderer } from 'react-test-renderer';

import NativeTurboImageModule from '../NativeTurboImageModule';
import { TurboImage } from '../index';
import type { TurboImageProps } from '../index';

// Stands in for the Fabric view: renders a host element named
// 'TurboImageView' carrying the exact props native would get, and counts
// mounts, because remounting the real view restarts its load.
const mockNativeView = { mounts: 0 };
jest.mock('../TurboImageViewNativeComponent', () => {
  const { createElement, useEffect } = require('react') as typeof import('react');
  return {
    __esModule: true,
    default: function MockTurboImageView(props: Record<string, unknown>) {
      useEffect(() => {
        mockNativeView.mounts += 1;
      }, []);
      return createElement('TurboImageView', props);
    },
  };
});
// `TurboModuleRegistry.getEnforcing` throws outside a native runtime.
jest.mock('../NativeTurboImageModule', () => ({
  __esModule: true,
  default: {
    prefetch: jest.fn(() => Promise.resolve(true)),
    dispose: jest.fn(() => Promise.resolve()),
    clearMemoryCache: jest.fn(() => Promise.resolve()),
    clearDiskCache: jest.fn(() => Promise.resolve()),
  },
}));

// React only batches and flushes inside act() when this is set.
(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

const NativeView = 'TurboImageView' as unknown as ComponentType<Record<string, unknown>>;
const AVATAR = { uri: 'https://cdn.example.com/avatars/ada.jpg' };

function render(props: Partial<TurboImageProps> = {}): ReactTestRenderer {
  let renderer!: ReactTestRenderer;
  act(() => {
    renderer = create(<TurboImage source={AVATAR} {...props} />);
  });
  return renderer;
}

// The props the native view received on the latest render.
const nativeProps = (renderer: ReactTestRenderer) => renderer.root.findByType(NativeView).props;
const spinners = (renderer: ReactTestRenderer) => renderer.root.findAllByType(ActivityIndicator);

type Handler = (event: unknown) => void;
type OnStart = NonNullable<TurboImageProps['onStart']>;
type OnCompletion = NonNullable<TurboImageProps['onCompletion']>;
const startEvent = { nativeEvent: { state: 'running' } };
const completionEvent = { nativeEvent: { state: 'completed' } };

function fire(renderer: ReactTestRenderer, name: 'onStart' | 'onCompletion', event: unknown) {
  act(() => {
    (nativeProps(renderer)[name] as Handler)(event);
  });
}

const advance = (ms: number) => act(() => jest.advanceTimersByTime(ms));

beforeEach(() => {
  mockNativeView.mounts = 0;
  jest.useFakeTimers();
  jest.clearAllMocks();
});

afterEach(() => {
  jest.restoreAllMocks();
  jest.useRealTimers();
});

describe('source', () => {
  it('passes a plain URI source through without a headers field', () => {
    expect(nativeProps(render()).source).toEqual({ uri: AVATAR.uri });
  });

  it('keeps cacheKey', () => {
    const source = { uri: 'https://cdn.example.com/a.jpg?sig=1', cacheKey: 'user-42' };
    expect(nativeProps(render({ source })).source).toEqual(source);
  });

  it.each([
    ['a record', { Authorization: 'Bearer abc', Accept: 'image/png' }],
    [
      '[name, value] pairs',
      [
        ['Authorization', 'Bearer abc'],
        ['Accept', 'image/png'],
      ] as const,
    ],
    [
      'a Headers-like object',
      {
        // Same callback order as fetch's Headers: (value, name).
        forEach(callback: (value: string, name: string) => void) {
          callback('Bearer abc', 'Authorization');
          callback('image/png', 'Accept');
        },
      },
    ],
  ])('normalises headers given as %s', (_form, headers) => {
    const source = { uri: AVATAR.uri, headers };
    expect(nativeProps(render({ source })).source).toEqual({
      uri: AVATAR.uri,
      headers: [
        { name: 'Authorization', value: 'Bearer abc' },
        { name: 'Accept', value: 'image/png' },
      ],
    });
  });

  it('stringifies non-string header values', () => {
    const source = { uri: AVATAR.uri, headers: { 'X-Retry': 3 as unknown as string } };
    expect(nativeProps(render({ source })).source).toEqual({
      uri: AVATAR.uri,
      headers: [{ name: 'X-Retry', value: '3' }],
    });
  });

  it("resolves a require()'d asset with React Native's resolver", () => {
    const resolve = jest
      .spyOn(Image, 'resolveAssetSource')
      .mockReturnValue({ uri: 'file:///app/assets/logo@3x.png', width: 40, height: 40, scale: 3 });
    expect(nativeProps(render({ source: 7 })).source).toEqual({
      uri: 'file:///app/assets/logo@3x.png',
    });
    expect(resolve).toHaveBeenCalledWith(7);
  });

  it('turns an unknown asset id into an empty URI, which the core rejects', () => {
    jest
      .spyOn(Image, 'resolveAssetSource')
      .mockReturnValue(null as unknown as ReturnType<typeof Image.resolveAssetSource>);
    expect(nativeProps(render({ source: 999 })).source).toEqual({ uri: '' });
  });
});

describe('cachePolicy', () => {
  it.each(['default', 'memoryOnly', 'noCache', 'cacheOnly', 'urlCache'] as const)(
    'passes the 2.0 policy %s through',
    (cachePolicy) => {
      expect(nativeProps(render({ cachePolicy })).cachePolicy).toBe(cachePolicy);
    }
  );

  it('leaves an unset policy unset, so the native default applies', () => {
    expect(nativeProps(render()).cachePolicy).toBeUndefined();
  });

  it("maps 1.x's dataCache to default", () => {
    jest.spyOn(console, 'warn').mockImplementation(() => {});
    expect(nativeProps(render({ cachePolicy: 'dataCache' })).cachePolicy).toBe('default');
  });

  it('does not warn for urlCache: it honours Cache-Control again', () => {
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
    render({ cachePolicy: 'urlCache' });
    expect(warn).not.toHaveBeenCalled();
  });

  it('warns once for the legacy name, not once per use', () => {
    // The "already warned" flag is module state, so use a fresh copy of the
    // module. The statics need no React, which keeps the isolated registry
    // from clashing with the test renderer's React instance.
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
    jest.isolateModules(() => {
      const fresh = require('../index') as typeof import('../index');
      fresh.TurboImage.prefetch([AVATAR], 'dataCache');
      fresh.TurboImage.prefetch([AVATAR], 'dataCache');
      fresh.TurboImage.prefetch([AVATAR], 'urlCache');
    });
    expect(warn).toHaveBeenCalledTimes(1);
    expect(warn.mock.calls[0]?.[0]).toMatch(/'dataCache' is deprecated/);
  });
});

describe('allowDownscaling', () => {
  it('is left unset by default, so the native default (true) applies', () => {
    expect(nativeProps(render())).not.toHaveProperty('allowDownscaling');
  });

  it('passes an opt-out through', () => {
    expect(nativeProps(render({ allowDownscaling: false })).allowDownscaling).toBe(false);
  });
});

describe('1.x props that 2.0 ignores', () => {
  it('does not forward format or isProgressiveImageRenderingEnabled to native', () => {
    const props = nativeProps(render({ format: 'gif', isProgressiveImageRenderingEnabled: false }));
    expect(props).not.toHaveProperty('format');
    expect(props).not.toHaveProperty('isProgressiveImageRenderingEnabled');
  });
});

describe('recyclingKey', () => {
  it('forwards the key to native', () => {
    expect(nativeProps(render({ recyclingKey: 'post-4812' })).recyclingKey).toBe('post-4812');
  });

  it("turns expo-image's null into an unset prop", () => {
    expect(nativeProps(render({ recyclingKey: null })).recyclingKey).toBeUndefined();
  });
});

describe('placeholder', () => {
  it('rejects more than one placeholder kind in development', () => {
    jest.spyOn(console, 'error').mockImplementation(() => {}); // React logs the throw
    expect(() =>
      render({
        placeholder: { blurhash: 'LEHV6nWB2yk8pyo0adR*.7kCMdnj', thumbhash: '4AcKPJpwd3dw' },
      })
    ).toThrow(/choose only one placeholder/);
  });

  it('accepts a single placeholder', () => {
    const placeholder = { thumbhash: '4AcKPJpwd3dwd3eHh3eAgAj3iA==' };
    expect(nativeProps(render({ placeholder })).placeholder).toEqual(placeholder);
  });
});

describe('layout', () => {
  const style = { width: 96, height: 96 };

  it('gives the style to the native view when no container is needed', () => {
    const renderer = render({ style });
    expect(nativeProps(renderer).style).toBe(style);
    expect(renderer.root.findAllByType(View)).toHaveLength(0);
  });

  it('rounded: the style moves to a clipping container and the image fills it', () => {
    const renderer = render({ style, rounded: true });
    expect(nativeProps(renderer).style).toBe(StyleSheet.absoluteFill);
    const container = renderer.root.findByType(View);
    expect(StyleSheet.flatten(container.props.style)).toEqual({
      ...style,
      overflow: 'hidden',
      borderRadius: 9999,
    });
  });

  it('indicator: uses a container too, but one that does not clip', () => {
    const renderer = render({ style, indicator: { style: 'medium' } });
    expect(nativeProps(renderer).style).toBe(StyleSheet.absoluteFill);
    expect(StyleSheet.flatten(renderer.root.findByType(View).props.style)).toEqual(style);
  });
});

describe('indicator', () => {
  const indicator = { style: 'large', color: '#e63946' } as const;

  it('shows nothing until a load has run for 150 ms', () => {
    const renderer = render({ indicator });
    expect(spinners(renderer)).toHaveLength(0);

    fire(renderer, 'onStart', startEvent);
    advance(149);
    expect(spinners(renderer)).toHaveLength(0);

    advance(1);
    expect(spinners(renderer)).toHaveLength(1);
  });

  it('removes the spinner when the load completes', () => {
    const renderer = render({ indicator });
    fire(renderer, 'onStart', startEvent);
    advance(150);
    fire(renderer, 'onCompletion', completionEvent);
    expect(spinners(renderer)).toHaveLength(0);
  });

  it('never shows the spinner for a load that completes within 150 ms', () => {
    const renderer = render({ indicator });
    fire(renderer, 'onStart', startEvent);
    advance(100);
    fire(renderer, 'onCompletion', completionEvent);
    advance(1000);
    expect(spinners(renderer)).toHaveLength(0);
    expect(jest.getTimerCount()).toBe(0);
  });

  it('restarts the delay when a new load supersedes one in flight', () => {
    // Native order for a superseded load: completion(cancelled), then start.
    const renderer = render({ indicator });
    fire(renderer, 'onStart', startEvent);
    advance(100);
    fire(renderer, 'onCompletion', { nativeEvent: { state: 'cancelled' } });
    fire(renderer, 'onStart', startEvent);
    advance(100); // 200 ms after the first start, 100 ms after the second
    expect(spinners(renderer)).toHaveLength(0);
    advance(50);
    expect(spinners(renderer)).toHaveLength(1);
  });

  it('keeps the same native view mounted while the spinner comes and goes', () => {
    // A remount would restart the load.
    const renderer = render({ indicator });
    expect(mockNativeView.mounts).toBe(1);
    fire(renderer, 'onStart', startEvent);
    advance(150);
    expect(spinners(renderer)).toHaveLength(1);
    fire(renderer, 'onCompletion', completionEvent);
    expect(mockNativeView.mounts).toBe(1);
  });

  it("maps 1.x's styles onto ActivityIndicator sizes and passes the color", () => {
    const large = render({ indicator });
    fire(large, 'onStart', startEvent);
    advance(150);
    expect(spinners(large)[0]?.props).toMatchObject({ size: 'large', color: '#e63946' });

    const medium = render({ indicator: { style: 'medium' } });
    fire(medium, 'onStart', startEvent);
    advance(150);
    expect(spinners(medium)[0]?.props.size).toBe('small');
  });

  it("still calls the app's own handlers, with the event", () => {
    const onStart = jest.fn<OnStart>();
    const onCompletion = jest.fn<OnCompletion>();
    const renderer = render({ indicator, onStart, onCompletion });
    fire(renderer, 'onStart', startEvent);
    fire(renderer, 'onCompletion', completionEvent);
    expect(onStart).toHaveBeenCalledWith(startEvent);
    expect(onCompletion).toHaveBeenCalledWith(completionEvent);
  });

  it.each([
    [
      'a placeholder is given',
      { indicator, placeholder: { blurhash: 'LEHV6nWB2yk8pyo0adR*.7kCMdnj' } },
    ],
    ['the indicator is an empty object (1.x quirk)', { indicator: {} }],
    ['no indicator is given', {}],
  ])('is off when %s: no spinner, no container, handlers untouched', (_case, props) => {
    const onStart = jest.fn<OnStart>();
    const onCompletion = jest.fn<OnCompletion>();
    const renderer = render({ ...props, onStart, onCompletion });
    expect(nativeProps(renderer).onStart).toBe(onStart);
    expect(nativeProps(renderer).onCompletion).toBe(onCompletion);
    expect(renderer.root.findAllByType(View)).toHaveLength(0);

    fire(renderer, 'onStart', startEvent);
    advance(1000);
    expect(spinners(renderer)).toHaveLength(0);
  });

  it('cancels a pending spinner on unmount', () => {
    const renderer = render({ indicator });
    fire(renderer, 'onStart', startEvent);
    act(() => renderer.unmount());
    expect(jest.getTimerCount()).toBe(0);
  });
});

describe('cache statics', () => {
  const module = jest.mocked(NativeTurboImageModule);

  it('prefetch normalises sources and defaults the policy', async () => {
    await TurboImage.prefetch([{ uri: AVATAR.uri, headers: { Accept: 'image/png' } }]);
    expect(module.prefetch).toHaveBeenCalledWith(
      [{ uri: AVATAR.uri, headers: [{ name: 'Accept', value: 'image/png' }] }],
      'default'
    );
  });

  it('prefetch maps a legacy policy and passes a 2.0 policy through', async () => {
    jest.spyOn(console, 'warn').mockImplementation(() => {});
    await TurboImage.prefetch([AVATAR], 'dataCache');
    await TurboImage.prefetch([AVATAR], 'memoryOnly');
    expect(module.prefetch.mock.calls.map((call) => call[1])).toEqual(['default', 'memoryOnly']);
  });

  it('prefetch resolves with what native reports', async () => {
    module.prefetch.mockResolvedValueOnce(false);
    await expect(TurboImage.prefetch([AVATAR])).resolves.toBe(false);
  });

  it('dispose normalises sources', async () => {
    await TurboImage.dispose([{ uri: AVATAR.uri, cacheKey: 'user-42' }]);
    expect(module.dispose).toHaveBeenCalledWith([{ uri: AVATAR.uri, cacheKey: 'user-42' }]);
  });

  it('clearMemoryCache and clearDiskCache call through', async () => {
    await TurboImage.clearMemoryCache();
    await TurboImage.clearDiskCache();
    expect(module.clearMemoryCache).toHaveBeenCalledTimes(1);
    expect(module.clearDiskCache).toHaveBeenCalledTimes(1);
  });
});
