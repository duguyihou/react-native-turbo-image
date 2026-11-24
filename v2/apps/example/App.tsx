// TurboImage example app: a Home screen leading to four demos and the
// on-device smoke test.
//
// Navigation is a plain stack in state, not a navigation library: the app
// has five screens and no tabs or modals, and react-native-screens would be
// one more native dependency to keep building on every React Native the
// library supports. A screen unmounts when it is left (a native stack would
// keep it), so going back and forth mounts and unmounts its images: that is
// the "rapid screen navigation" scenario, and why nothing here caches
// screens. No iOS swipe-back gesture; Android's back button pops.
//
// Deep links pick the first screen, for scripts:
//   turboimageexample://smoke                  the smoke test (smoke-*.sh)
//   turboimageexample://performance?count=1000&dataset=repeated
//   turboimageexample://gallery | detail | playground
// iOS: xcrun simctl launch booted org.reactjs.native.example.TurboImageExample \
//        -launchURL '<link>'
//      (`simctl openurl` works too, but iOS first asks "Open in …?", which a
//      script cannot answer. A `-key value` launch argument lands in
//      NSUserDefaults' argument domain, which RN's Settings module reads.)
// Android: adb shell am start -a android.intent.action.VIEW -d '<link>'

// index.js imports this first, which is what applies the cache sizes; this
// import only reads the result.
import { cacheConfigured } from './src/startup';

import { Fragment, useCallback, useEffect, useState } from 'react';
import { BackHandler, Linking, Platform, Settings, StatusBar } from 'react-native';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { DetailScreen } from './src/screens/Detail';
import { GalleryScreen } from './src/screens/Gallery';
import { HomeScreen } from './src/screens/Home';
import { PerformanceScreen, parsePerformanceParams } from './src/screens/Performance';
import type { PerformanceParams } from './src/screens/Performance';
import { PlaygroundScreen } from './src/screens/Playground';
import { SmokeTest } from './src/smoke/SmokeTest';
import { Screen } from './src/ui';
import { useTheme } from './src/theme';

export type Route =
  | { name: 'home' }
  | { name: 'gallery' }
  | { name: 'detail'; sourceId?: string }
  | { name: 'performance'; params?: PerformanceParams }
  | { name: 'playground' }
  | { name: 'smoke' };

export type Navigate = (route: Route) => void;

const HOME: Route = { name: 'home' };

// `turboimageexample://<screen>?<query>` → the stack to show. Anything else
// (no link, an unknown screen) → Home.
function routeFromUrl(url: string | null): Route[] {
  const match = url?.match(/^turboimageexample:\/\/([a-z]+)\/?(?:\?(.*))?$/i);
  if (!match) {
    return [HOME];
  }
  const [, screen, query = ''] = match;
  const params = Object.fromEntries(
    query
      .split('&')
      .filter(Boolean)
      .map((pair) => pair.split('=').map(decodeURIComponent) as [string, string])
  );
  switch (screen!.toLowerCase()) {
    case 'smoke':
      return [HOME, { name: 'smoke' }];
    case 'gallery':
      return [HOME, { name: 'gallery' }];
    case 'detail':
      return [HOME, { name: 'detail', sourceId: params.source }];
    case 'playground':
      return [HOME, { name: 'playground' }];
    case 'performance':
      return [HOME, { name: 'performance', params: parsePerformanceParams(params) }];
    default:
      return [HOME];
  }
}

export default function App() {
  const theme = useTheme();
  // `null` until the launch link is read, so a deep-linked launch never
  // mounts Home's content first.
  const [stack, setStack] = useState<Route[] | null>(null);
  // Bumped by every link, so a link to the screen already shown remounts it
  // with the link's parameters.
  const [linkGeneration, setLinkGeneration] = useState(0);

  useEffect(() => {
    // The `-launchURL` launch argument (iOS), else the link that opened the app.
    const launchArgument = Platform.OS === 'ios' ? Settings.get('launchURL') : undefined;
    Linking.getInitialURL().then(
      (url) =>
        setStack(routeFromUrl(url ?? (typeof launchArgument === 'string' ? launchArgument : null))),
      () => setStack([HOME])
    );
    // A link while running (`simctl openurl` again) replaces the stack.
    const subscription = Linking.addEventListener('url', ({ url }) => {
      setStack(routeFromUrl(url));
      setLinkGeneration((generation) => generation + 1);
    });
    return () => subscription.remove();
  }, []);

  const route = stack?.[stack.length - 1];
  const canGoBack = (stack?.length ?? 0) > 1;
  const navigate = useCallback<Navigate>(
    (next) => setStack((current) => [...(current ?? [HOME]), next]),
    []
  );
  const back = useCallback(
    () => setStack((current) => (current && current.length > 1 ? current.slice(0, -1) : current)),
    []
  );

  useEffect(() => {
    if (!canGoBack) {
      return undefined;
    }
    const subscription = BackHandler.addEventListener('hardwareBackPress', () => {
      back();
      return true;
    });
    return () => subscription.remove();
  }, [canGoBack, back]);

  return (
    <SafeAreaProvider>
      <StatusBar barStyle={theme.dark ? 'light-content' : 'dark-content'} />
      {route && (
        <Fragment key={`${linkGeneration}:${stack!.length}`}>
          {renderRoute(route, navigate, back)}
        </Fragment>
      )}
    </SafeAreaProvider>
  );
}

function renderRoute(route: Route, navigate: Navigate, back: () => void) {
  switch (route.name) {
    case 'home':
      return <HomeScreen navigate={navigate} cacheConfigured={cacheConfigured} />;
    case 'gallery':
      return <GalleryScreen navigate={navigate} onBack={back} />;
    case 'detail':
      return <DetailScreen initialSourceId={route.sourceId} onBack={back} />;
    case 'performance':
      return <PerformanceScreen initialParams={route.params} onBack={back} />;
    case 'playground':
      return <PlaygroundScreen onBack={back} />;
    case 'smoke':
      return (
        <Screen title="Smoke test" onBack={back} scroll={false}>
          <SmokeTest />
        </Screen>
      );
  }
}
