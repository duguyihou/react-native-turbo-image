// TurboImage core: image processors (resize, blur, monochrome, tint), run
// here on both platforms as integer math on RGBA8 so output matches
// (RFC §4.5a).
//
// Flow: `resolveRequest()` turns `ProcessingOptions` into a `processorKey`.
// Adapters attach one processing step identified by that key (so each
// variant gets its own memory-cache entry), and the step calls
// `processImage(pixels, processorKey)`. The key is the whole description,
// so cache identity cannot disagree with the pixels.
//
// Pixels are premultiplied RGBA8 in and out; no channel exceeds alpha.
// Pure and thread-safe, but run on a background queue: a full-size photo
// takes tens of ms.

#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

#include "turboimage/Placeholder.h"  // RgbaImage

namespace turboimage {

// The JS props. Values <= 0 or NaN mean "absent".
struct ProcessingOptions {
  // Target width in points/dp. Keeps aspect ratio; never upscales.
  double resize = 0;
  // Gaussian sigma in pixels of the resized image, so pair with `resize`
  // for a resolution-independent look.
  double blur = 0;
  // 0xAARRGGBB (a processed React Native color).
  std::optional<std::uint32_t> monochrome;
  std::optional<std::uint32_t> tint;

  friend bool operator==(const ProcessingOptions&,
                         const ProcessingOptions&) = default;
};

// Normalised, pixel-exact description of the work: options that give the
// same pixels give the same spec, key and cache entry.
struct ProcessingSpec {
  // Target width in pixels; 0 = no resize.
  int resizeWidth = 0;
  // Sigma in pixels; 0 = no blur.
  int blurRadius = 0;
  std::optional<std::uint32_t> monochrome;
  std::optional<std::uint32_t> tint;

  [[nodiscard]] bool empty() const {
    return resizeWidth == 0 && blurRadius == 0 && !monochrome && !tint;
  }

  friend bool operator==(const ProcessingSpec&, const ProcessingSpec&) =
      default;
};

// Largest blur radius; beyond it the image is a flat average anyway.
inline constexpr int kMaxBlurRadius = 250;

// Props to spec. `pixelRatio` <= 0 or NaN is treated as 1. Bad values are
// dropped or clamped, never rejected, so an odd prop cannot fail a load.
[[nodiscard]] ProcessingSpec resolveProcessing(const ProcessingOptions& options,
                                               double pixelRatio);

// Stable text form, e.g. "ti1;w=300;b=8;m=ffff0000"; empty for an empty
// spec. Bump the version tag whenever any algorithm's output changes.
[[nodiscard]] std::string processorKey(const ProcessingSpec& spec);

// Strict inverse of `processorKey`; anything else (including "") is nullopt.
[[nodiscard]] std::optional<ProcessingSpec> parseProcessorKey(
    std::string_view key);

// Applies resize, blur, monochrome, tint, in that order.
[[nodiscard]] RgbaImage applyProcessing(RgbaImage image,
                                        const ProcessingSpec& spec);

// What the platform step calls. nullopt for a bad key or a buffer that
// does not match its size; adapters report that as a decode failure.
[[nodiscard]] std::optional<RgbaImage> processImage(RgbaImage image,
                                                    std::string_view key);

// Individual stages, exposed for tests. Each is a no-op for a neutral
// parameter (width >= image width, radius 0, ...).
[[nodiscard]] RgbaImage resizeToWidth(const RgbaImage& image, int width);
void gaussianBlur(RgbaImage& image, int radius);
void monochrome(RgbaImage& image, std::uint32_t argb);
void tint(RgbaImage& image, std::uint32_t argb);

}  // namespace turboimage
