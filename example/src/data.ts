import { RouteName } from './screens/routes.type';

export const routesData = [
  {
    title: 'List',
    data: [
      { name: 'React Native Image', destination: RouteName.Image },
      {
        name: 'TurboImage with UrlCache (default)',
        destination: RouteName.UrlCache,
      },
      { name: 'TurboImage with DataCache', destination: RouteName.DataCache },
      {
        name: 'TurboImage with dynamaticUri',
        destination: RouteName.DynamaticUri,
      },
    ],
  },
  {
    title: 'Placeholder',
    data: [
      { name: 'thumbhash', destination: RouteName.Thumbhash },
      { name: 'blurhash', destination: RouteName.Blurhash },
      { name: 'memoryCacheKey', destination: RouteName.MemoryCacheKeyPrevious },
    ],
  },
  {
    title: 'Prefetch',
    data: [
      {
        name: 'Prefetch with UrlCache (default)',
        destination: RouteName.PrefetchWithUrlCache,
      },
      {
        name: 'Prefetch with DataCache',
        destination: RouteName.PrefetchWithDataCache,
      },
    ],
  },
  {
    title: 'Events',
    data: [
      { name: 'Start -> Completion(Success)', destination: RouteName.Success },
      { name: 'Start -> Completion(Failure)', destination: RouteName.Failure },
    ],
  },
  {
    title: 'Image Processing',
    data: [{ name: 'Processing', destination: RouteName.ImageProcessing }],
  },
  {
    title: 'Live Text',
    data: [{ name: 'iOS 16+ only', destination: RouteName.LiveText }],
  },
  {
    title: 'Other Formats(Experimental)',
    data: [
      { name: 'SVG', destination: RouteName.SVG },
      { name: 'Gif', destination: RouteName.Gif },
      { name: 'APNG', destination: RouteName.APNG },
    ],
  },
];

export const liveTextData = [
  {
    uri: 'https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:ejihld4sywvvqwe67cdkn4jq/bafkreibcshvfvfi4suht32tcp4ds77y2yghtcig62byqyq3ot4abpsplhu@jpeg',
  },
  {
    uri: 'https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:lzlqyldh7nfc34pfffvd24ko/bafkreihimujh4kxa4gecniimqfnmdjnlajjek6pleh5tt5k4djhno3lzu4@jpeg',
  },
];

export const processingData = [
  {
    title: 'Original',
    uri: 'https://placedog.net/300/300?id=238',
  },
  {
    title: 'Resize',
    uri: 'https://placedog.net/300/300?id=238',
    resize: 150,
  },
  {
    title: 'Monochrome',
    uri: 'https://placedog.net/300/300?id=238',
    resize: 150,
    monochrome: 'white',
  },
  {
    title: 'Circle',
    uri: 'https://placedog.net/300/300?id=238',
    resize: 150,
    rounded: true,
  },
  {
    title: 'Blur',
    uri: 'https://placedog.net/300/300?id=238',
    resize: 150,
    blur: 5,
    rounded: true,
  },
  {
    title: 'Tint',
    uri: 'https://placedog.net/300/300?id=238',
    resize: 100,
    blur: 5,
    rounded: true,
    tint: 'black',
  },
];
