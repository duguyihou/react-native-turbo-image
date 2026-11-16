import TurboImageView from './TurboImageViewNativeComponent';
import type { NativeProps } from './TurboImageViewNativeComponent';

export type TurboImageProps = NativeProps;
export type {
  ErrorEvent,
  LoadEvent,
  NativeSource,
} from './TurboImageViewNativeComponent';

// The 2.0 walking skeleton exposes the native component directly. The 1.x
// JS conveniences (placeholder props, prefetch, cache helpers) are
// intentionally omitted until the image pipeline milestone; see
// docs/migration-plan.md for the order they come back in.
export function TurboImage(props: TurboImageProps) {
  return <TurboImageView {...props} />;
}

export default TurboImage;
