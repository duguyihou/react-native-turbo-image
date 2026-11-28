// JS-layer tests: native view and module are mocked, so these assert what
// native *receives*.

import { afterEach, beforeEach, describe, expect, it, jest } from '@jest/globals';
import { act, createRef } from 'react';
import type { ComponentType } from 'react';
import { ActivityIndicator, Image, StyleSheet, View } from 'react-native';
import { create } from 'react-test-renderer';
import type { ReactTestRenderer } from 'react-test-renderer';

import NativeTurboImageModule from '../NativeTurboImageModule';
import { TurboImage } from '../index';
import type { TurboImageInstance, TurboImageProps } from '../index';

// Fake Fabric view: records the props and counts mounts (a remount restarts
// the real view's load).
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
    getSize: jest.fn(() => Promise.resolve({ width: 640, height: 480 })),
    configureCache: jest.fn(() => true),
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

function position(contentPosition: TurboImageProps['contentPosition']) {
  const props = nativeProps(render({ contentPosition }));
  return [props.contentPositionX, props.contentPositionY];
}

describe('contentPosition', () => {
  it('sends nothing when unset, so native keeps its centred default', () => {
    expect(position(undefined)).toEqual([undefined, undefined]);
  });

  it('turns keywords into fractions, in either order', () => {
    expect(position('top')).toEqual([0.5, 0]);
    expect(position('bottom right')).toEqual([1, 1]);
    expect(position('left top')).toEqual([0, 0]);
    expect(position('center')).toEqual([0.5, 0.5]);
  });

  it('turns percentages from an edge into fractions', () => {
    expect(position({ top: '20%' })).toEqual([0.5, 0.2]);
    expect(position({ right: '10%', bottom: '0%' })).toEqual([0.9, 1]);
  });

  it('accepts every percentage its type allows', () => {
    // `${number}%` admits these, so they must not fall back to centre.
    expect(position({ top: '.5%' })).toEqual([0.5, 0.005]);
    expect(position({ left: '1e1%' })).toEqual([0.1, 0.5]);
    expect(position({ left: '+25%' })).toEqual([0.25, 0.5]);
  });

  it('warns in development about what it cannot place', () => {
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
    expect(position('middle' as never)).toEqual([0.5, 0.5]);
    expect(position({ top: 10 } as never)).toEqual([0.5, 0.5]);
    expect(warn).toHaveBeenCalledTimes(2);
  });

  it('takes two keywords only on different axes', () => {
    // As CSS `object-position`: one word per axis, `center` on either.
    expect(position('center top')).toEqual([0.5, 0]);
    expect(position('right center')).toEqual([1, 0.5]);
    // @ts-expect-error: both words place the vertical axis.
    position('top bottom');
    // @ts-expect-error: both words place the horizontal axis.
    position('left left');
  });

  it('warns in development when two keywords place one axis, and keeps the first', () => {
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
    expect(position('top bottom' as never)).toEqual([0.5, 0]);
    expect(position('right left' as never)).toEqual([1, 0.5]);
    expect(warn).toHaveBeenCalledTimes(2);
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
    // Fresh module copy to reset the "already warned" flag.
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

describe('progressEnabled', () => {
  // Off, the native views ask the loader for no progress at all.
  it('is false without an onProgress handler', () => {
    expect(nativeProps(render()).progressEnabled).toBe(false);
  });

  it('is true with one, and the handler still reaches the native view', () => {
    const onProgress = jest.fn<NonNullable<TurboImageProps['onProgress']>>();
    const props = nativeProps(render({ onProgress }));
    expect(props.progressEnabled).toBe(true);
    expect(props.onProgress).toBe(onProgress);
  });
});

// A handler that does nothing, for tests about which handlers exist.
const noop = () => {};

describe('loadEventMask', () => {
  // The native views send only the events that have a handler.
  it('is 0 without handlers', () => {
    expect(nativeProps(render()).loadEventMask).toBe(0);
  });

  it("has one bit per handler, in the spec's order", () => {
    expect(nativeProps(render({ onStart: noop })).loadEventMask).toBe(1);
    expect(nativeProps(render({ onSuccess: noop })).loadEventMask).toBe(2);
    expect(nativeProps(render({ onFailure: noop })).loadEventMask).toBe(4);
    expect(nativeProps(render({ onCompletion: noop })).loadEventMask).toBe(8);
    expect(nativeProps(render({ onSuccess: noop, onFailure: noop })).loadEventMask).toBe(6);
  });

  it('includes start and completion for the indicator', () => {
    expect(nativeProps(render({ indicator: { style: 'medium' } })).loadEventMask).toBe(9);
  });

  it('does not count onProgress, which progressEnabled gates', () => {
    expect(nativeProps(render({ onProgress: noop })).loadEventMask).toBe(0);
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

  it('accepts an image as { uri }', () => {
    const placeholder = { uri: 'https://cdn.example.com/p/ada-32.jpg' };
    expect(nativeProps(render({ placeholder })).placeholder).toEqual(placeholder);
  });

  it("resolves a require()'d image like a source", () => {
    jest
      .spyOn(Image, 'resolveAssetSource')
      .mockReturnValue({ uri: 'file:///app/assets/grey@3x.png', width: 8, height: 8, scale: 3 });
    expect(nativeProps(render({ placeholder: 12 })).placeholder).toEqual({
      uri: 'file:///app/assets/grey@3x.png',
    });
  });

  it('counts an image as a placeholder kind of its own', () => {
    jest.spyOn(console, 'error').mockImplementation(() => {}); // React logs the throw
    expect(() =>
      render({ placeholder: { uri: 'https://cdn.example.com/p/ada-32.jpg', thumbhash: '4AcK' } })
    ).toThrow(/choose only one placeholder/);
  });
});

describe('layout', () => {
  const style = { width: 96, height: 96 };

  it('gives the style to the native view when no container is needed', () => {
    const renderer = render({ style });
    // `overflow: 'hidden'` makes iOS clip to `borderRadius`.
    expect(StyleSheet.flatten(nativeProps(renderer).style)).toEqual({
      ...style,
      overflow: 'hidden',
    });
    expect(renderer.root.findAllByType(View)).toHaveLength(0);
  });

  it("lets the app's overflow win over the default", () => {
    const renderer = render({ style: { ...style, overflow: 'visible' } });
    expect(StyleSheet.flatten(nativeProps(renderer).style)).toMatchObject({ overflow: 'visible' });
  });

  it('rounded: the image view clips itself, with no container', () => {
    const renderer = render({ style: { ...style, borderRadius: 8 }, rounded: true });
    // After the app's style, as in 1.x: `rounded` wins over its radius.
    expect(StyleSheet.flatten(nativeProps(renderer).style)).toEqual({
      ...style,
      overflow: 'hidden',
      borderRadius: 9999,
    });
    expect(renderer.root.findAllByType(View)).toHaveLength(0);
  });

  it('rounded: toggling it keeps the same native view mounted', () => {
    // A remount would restart the load.
    const renderer = render({ style });
    act(() => {
      renderer.update(<TurboImage source={AVATAR} style={style} rounded />);
    });
    act(() => {
      renderer.update(<TurboImage source={AVATAR} style={style} rounded={false} />);
    });
    expect(mockNativeView.mounts).toBe(1);
  });

  it('rounded with an indicator: the container clips, so the spinner is clipped too', () => {
    const renderer = render({ style, rounded: true, indicator: { style: 'medium' } });
    expect(nativeProps(renderer).style).toBe(StyleSheet.absoluteFill);
    expect(StyleSheet.flatten(renderer.root.findByType(View).props.style)).toEqual({
      ...style,
      overflow: 'hidden',
      borderRadius: 9999,
    });
  });

  it('indicator: the container clips to a borderRadius, as the image view does', () => {
    const renderer = render({
      style: { ...style, borderRadius: 12 },
      indicator: { style: 'medium' },
    });
    expect(nativeProps(renderer).style).toBe(StyleSheet.absoluteFill);
    expect(StyleSheet.flatten(renderer.root.findByType(View).props.style)).toEqual({
      ...style,
      borderRadius: 12,
      overflow: 'hidden',
    });
  });

  it("indicator: the app's overflow still wins on the container", () => {
    const renderer = render({
      style: { ...style, overflow: 'visible' },
      indicator: { style: 'medium' },
    });
    expect(StyleSheet.flatten(renderer.root.findByType(View).props.style)).toMatchObject({
      overflow: 'visible',
    });
  });
});

// Fake native node that says which host element a ref landed on.
const createNodeMock = (element: { type: unknown }) => ({ hostType: element.type });

function refOf(props: Partial<TurboImageProps>) {
  const ref = createRef<TurboImageInstance>();
  act(() => {
    create(<TurboImage ref={ref} source={AVATAR} {...props} />, { createNodeMock });
  });
  return ref.current as unknown as { hostType?: string } | null;
}

describe('ref', () => {
  it.each([
    ['no container', {}],
    ['rounded', { rounded: true }],
  ] as Array<[string, Partial<TurboImageProps>]>)(
    'is the native image view with %s',
    (_name, props) => {
      expect(refOf(props)?.hostType).toBe('TurboImageView');
    }
  );

  it('is the container when the indicator adds one, as in 1.x', () => {
    // RN's Jest preset mocks <View>, so just check it is not the image view.
    const instance = refOf({ indicator: { style: 'medium' } });
    expect(instance).not.toBeNull();
    expect(instance?.hostType).not.toBe('TurboImageView');
  });

  it('does not also reach the image view inside a container', () => {
    const renderer = render({
      indicator: { style: 'medium' },
      ref: createRef<TurboImageInstance>(),
    });
    expect(nativeProps(renderer).ref).toBeUndefined();
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

  it('keeps the same native view mounted when a placeholder comes or goes', () => {
    // A row that gets its blurhash later must not restart its load.
    const placeholder = { blurhash: 'LEHV6nWB2yk8pyo0adR*.7kCMdnj' };
    const renderer = render({ indicator });
    act(() => {
      renderer.update(
        <TurboImage source={AVATAR} indicator={indicator} placeholder={placeholder} />
      );
    });
    act(() => {
      renderer.update(<TurboImage source={AVATAR} indicator={indicator} />);
    });
    expect(mockNativeView.mounts).toBe(1);
  });

  it("never spins over a placeholder, and still calls the app's handlers", () => {
    const onStart = jest.fn<OnStart>();
    const onCompletion = jest.fn<OnCompletion>();
    const renderer = render({
      indicator,
      placeholder: { blurhash: 'LEHV6nWB2yk8pyo0adR*.7kCMdnj' },
      onStart,
      onCompletion,
    });

    fire(renderer, 'onStart', startEvent);
    advance(1000);
    expect(spinners(renderer)).toHaveLength(0);
    fire(renderer, 'onCompletion', completionEvent);
    expect(onStart).toHaveBeenCalledWith(startEvent);
    expect(onCompletion).toHaveBeenCalledWith(completionEvent);
  });

  it('stops a spinner whose load completed while a placeholder hid it', () => {
    // The load ends while the placeholder is set; when the placeholder goes,
    // the same view (no remount, no new load) must not spin again.
    const placeholder = { blurhash: 'LEHV6nWB2yk8pyo0adR*.7kCMdnj' };
    const renderer = render({ indicator });
    fire(renderer, 'onStart', startEvent);
    advance(150);
    act(() => {
      renderer.update(
        <TurboImage source={AVATAR} indicator={indicator} placeholder={placeholder} />
      );
    });
    expect(nativeProps(renderer).loadEventMask & 8).toBe(8); // completion still sent
    fire(renderer, 'onCompletion', completionEvent);
    act(() => {
      renderer.update(<TurboImage source={AVATAR} indicator={indicator} />);
    });

    expect(spinners(renderer)).toHaveLength(0);
  });

  it.each([
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

  it("prefetch passes an options object's policy", async () => {
    await TurboImage.prefetch([AVATAR], { cachePolicy: 'urlCache' });
    expect(module.prefetch).toHaveBeenCalledWith([AVATAR], 'urlCache');
  });

  it("prefetch takes 1.x's policy string as its second argument", async () => {
    await TurboImage.prefetch([AVATAR], 'urlCache');
    expect(module.prefetch).toHaveBeenCalledWith([AVATAR], 'urlCache');
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

  it('getSize normalises the source, defaults the policy and resolves the size', async () => {
    await expect(
      TurboImage.getSize({ uri: AVATAR.uri, headers: { Authorization: 'Bearer t0ken' } })
    ).resolves.toEqual({ width: 640, height: 480 });
    expect(module.getSize).toHaveBeenCalledWith(
      { uri: AVATAR.uri, headers: [{ name: 'Authorization', value: 'Bearer t0ken' }] },
      'default'
    );
  });

  it('getSize passes the rejection through', async () => {
    module.getSize.mockRejectedValueOnce(Object.assign(new Error('404'), { code: 'http' }));
    await expect(TurboImage.getSize(AVATAR, 'cacheOnly')).rejects.toMatchObject({
      code: 'http',
    });
    expect(module.getSize).toHaveBeenLastCalledWith(AVATAR, 'cacheOnly');
  });

  it('configureCache sends whole bytes, and 0 for unset or unusable sizes', () => {
    expect(TurboImage.configureCache({ maxDiskSize: 300 * 1024 * 1024 + 0.5 })).toBe(true);
    TurboImage.configureCache({ maxMemoryCost: Number.NaN });
    TurboImage.configureCache({ maxDiskSize: -1, maxMemoryCost: 64e6 });
    expect(module.configureCache.mock.calls).toEqual([
      [300 * 1024 * 1024, 0],
      [0, 0],
      [0, 64e6],
    ]);
  });

  it('configureCache returns false and warns in development once the caches exist', () => {
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
    module.configureCache.mockReturnValueOnce(false);
    expect(TurboImage.configureCache({ maxDiskSize: 1 })).toBe(false);
    expect(warn).toHaveBeenCalledWith(expect.stringMatching(/caches already exist/));
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

// Compile-time only: the payload types name the values native sends, so a
// misspelt code is a type error. `bun run typecheck` checks these.
const misspeltCode: NonNullable<TurboImageProps['onFailure']> = ({ nativeEvent }) => {
  // @ts-expect-error: 'notcached' is not a load error code.
  if (nativeEvent.code === 'notcached') return;
};
const misspeltState: NonNullable<TurboImageProps['onCompletion']> = ({ nativeEvent }) => {
  // @ts-expect-error: 'canceled' is not a completion state.
  if (nativeEvent.state === 'canceled') return;
};

describe('event payload types', () => {
  it('narrows codes and states to their documented values', () => {
    expect([misspeltCode, misspeltState]).toHaveLength(2);
  });
});
