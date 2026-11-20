// TurboImage core: image processors (resize, blur, monochrome, tint).
//
// 1.x applied these with each platform's own filters: Nuke's Resize, a
// CIGaussianBlur, CIColorMonochrome and `UIImage.withTintColor` on iOS, and
// Coil 2 transformations (RenderScript blur, BlendMode.COLOR) on Android. The
// two platforms therefore produced visibly different images for the same
// props, and RenderScript is gone in Coil 3's world. 2.0 runs every processor
// here, on both platforms, as integer arithmetic on RGBA8 pixels (RFC §4.5a).
//
// How the pieces fit:
//   1. The view hands `ProcessingOptions` (JS props) to `resolveRequest()`,
//      which normalises them into a `ProcessingSpec` and encodes it as the
//      request's `processorKey` (ImageRequest.h).
//   2. Adapters attach one opaque processing step identified by that key
//      (Nuke `ImageProcessors.Anonymous(id:)`, a Coil `Transformation` whose
//      `cacheKey` it is). Both loaders fold that identifier into their
//      memory-cache key, so each variant is cached separately while the disk
//      tier keeps one copy of the original bytes.
//   3. The processing step calls `processImage(pixels, processorKey)`. The
//      key is the whole description, so nothing else crosses the JNI or ObjC
//      boundary and the cache identity cannot disagree with the pixels.
//
// Pixel contract: every function takes and returns *premultiplied* RGBA8
// (CGImage premultipliedLast / Android ARGB_8888 memory layout) and keeps the
// invariant that no colour channel exceeds alpha.
//
// Threading contract: pure functions, safe on any thread. Processing is
// O(pixels) for every processor (blur included, independent of radius), but a
// full-resolution photo still takes tens of milliseconds, so loaders run it on
// their background decode queues, never on the main thread.

#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

#include "turboimage/Placeholder.h"  // RgbaImage

namespace turboimage {

// The JS props, as the views receive them. Values that do not describe a real
// operation (<= 0, NaN) mean "absent"; see `resolveProcessing`.
struct ProcessingOptions {
  // Target width in density-independent units (iOS points, Android dp).
  // Aspect ratio is preserved and images are never upscaled (1.x semantics,
  // Nuke's `Resize(width:)` default).
  double resize = 0;
  // Gaussian standard deviation in pixels of the image *after* resizing. The
  // same number therefore blurs a 4000 px original far less than a 400 px
  // thumbnail; pair `blur` with `resize` for a resolution-independent look.
  double blur = 0;
  // 0xAARRGGBB (the integer form of a processed React Native color).
  std::optional<std::uint32_t> monochrome;
  std::optional<std::uint32_t> tint;

  friend bool operator==(const ProcessingOptions&,
                         const ProcessingOptions&) = default;
};

// Normalised, pixel-exact description of the work. Two option sets that
// would produce the same pixels produce the same spec (and therefore the same
// processor key and the same cache entry).
struct ProcessingSpec {
  // Target width in pixels; 0 = no resize.
  int resizeWidth = 0;
  // Standard deviation in pixels; 0 = no blur.
  int blurRadius = 0;
  std::optional<std::uint32_t> monochrome;
  std::optional<std::uint32_t> tint;

  [[nodiscard]] bool empty() const {
    return resizeWidth == 0 && blurRadius == 0 && !monochrome && !tint;
  }

  friend bool operator==(const ProcessingSpec&, const ProcessingSpec&) =
      default;
};

// Largest accepted blur radius. Beyond this the image is a flat average
// anyway; the cap keeps the key space (and running sums) bounded.
inline constexpr int kMaxBlurRadius = 250;

// Converts props to a spec. `pixelRatio` is the screen scale
// (`UIScreen.scale`, `DisplayMetrics.density`); non-positive or NaN is
// treated as 1. Out-of-range inputs are dropped or clamped, never rejected:
// 1.x never validated these props, so an odd value must not fail a load.
[[nodiscard]] ProcessingSpec resolveProcessing(const ProcessingOptions& options,
                                               double pixelRatio);

// Stable text form of a spec, e.g. "ti1;w=300;b=8;m=ffff0000". Empty for an
// empty spec, so an unprocessed request keeps exactly its 1.x-compatible
// cache identity. The leading version tag changes whenever any algorithm
// below changes its output, which invalidates every memory-cached variant.
[[nodiscard]] std::string processorKey(const ProcessingSpec& spec);

// Inverse of `processorKey`. Strict: anything `processorKey` cannot have
// produced (including an empty string) returns nullopt.
[[nodiscard]] std::optional<ProcessingSpec> parseProcessorKey(
    std::string_view key);

// Applies, in 1.x's order: resize, blur, monochrome, tint.
[[nodiscard]] RgbaImage applyProcessing(RgbaImage image,
                                        const ProcessingSpec& spec);

// What the platform processing step calls. Returns nullopt for a key that
// does not parse or an image whose buffer does not match its size; adapters
// report that as a decode failure.
[[nodiscard]] std::optional<RgbaImage> processImage(RgbaImage image,
                                                    std::string_view key);

// The individual stages, exposed for tests. Each is a no-op when its
// parameter says so (width >= image width, radius 0, ...).
[[nodiscard]] RgbaImage resizeToWidth(const RgbaImage& image, int width);
void gaussianBlur(RgbaImage& image, int radius);
void monochrome(RgbaImage& image, std::uint32_t argb);
void tint(RgbaImage& image, std::uint32_t argb);

}  // namespace turboimage
