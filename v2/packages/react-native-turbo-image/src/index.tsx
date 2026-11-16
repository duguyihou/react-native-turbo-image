import TurboImageView from './TurboImageViewNativeComponent';
import type { NativeProps } from './TurboImageViewNativeComponent';

export type TurboImageProps = NativeProps;
export type {
  CompletionEvent,
  FailureEvent,
  NativePlaceholder as Placeholder,
  NativeSource,
  ProgressEvent,
  StartEvent,
  SuccessEvent,
} from './TurboImageViewNativeComponent';

// 2.0 exposes the native component almost directly. The remaining 1.x JS
// conveniences (memoryCacheKey placeholders, prefetch, cache helpers) are
// intentionally omitted for now; docs/migration-plan.md lists the order they
// come back in.
export function TurboImage(props: TurboImageProps) {
  // Same rule as 1.x: one placeholder kind at a time. Native would silently
  // prefer blurhash; failing loudly in development is kinder.
  if (
    __DEV__ &&
    props.placeholder?.blurhash &&
    props.placeholder?.thumbhash
  ) {
    throw new Error(
      'TurboImage: pass either placeholder.blurhash or placeholder.thumbhash, not both'
    );
  }
  return <TurboImageView {...props} />;
}

export default TurboImage;
