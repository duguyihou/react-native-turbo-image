#include "turboimage/Processing.h"

#include <algorithm>
#include <array>
#include <charconv>
#include <cmath>
#include <cstdio>
#include <vector>

// Same reason as Placeholder.cpp: the box sizes come from a sqrt and a
// division, and a fused multiply-add would round differently on arm64. All
// per-pixel work is integer arithmetic, so this is the only floating point
// that could make the platforms disagree. Clang only, as there: GCC does
// not know the pragma (a warning, so an error where warnings are errors)
// and does not contract in strict ISO mode anyway.
#if defined(__clang__)
#pragma STDC FP_CONTRACT OFF
#endif

namespace turboimage {

namespace {

// Bumped whenever any stage's output changes for the same spec, so stale
// memory-cached variants are never mistaken for new ones.
constexpr std::string_view kKeyVersion = "ti1";

// Large enough for any real image; keeps every product below 2^63.
constexpr int kMaxResizeWidth = 65535;

bool isUsable(double value) { return std::isfinite(value) && value > 0; }

bool hasValidBuffer(const RgbaImage& image) {
  return image.width > 0 && image.height > 0 &&
         image.pixels.size() == static_cast<std::size_t>(image.width) *
                                    static_cast<std::size_t>(image.height) * 4;
}

// ---------------------------------------------------------------------------
// Resize: exact area averaging (a box filter whose footprint is the output
// pixel). It is the best-quality pure downscaler and needs only integers.
//
// Place source pixel i on [i*dst, (i+1)*dst) and output pixel j on
// [j*src, (j+1)*src). Both spans are integers, so every overlap is an
// integer weight and each output's weights sum to exactly `src`.
// ---------------------------------------------------------------------------

// Resamples `count` lines of `src` samples to `dst` samples. `step` is the
// distance between consecutive samples of one line and `lineStride` the
// distance between lines, both in bytes, so one routine serves rows and
// columns.
void resampleLines(const std::uint8_t* in, std::uint8_t* out, int src, int dst,
                   int count, std::size_t inStep, std::size_t inLineStride,
                   std::size_t outStep, std::size_t outLineStride) {
  const auto srcSize = static_cast<std::uint64_t>(src);
  const auto dstSize = static_cast<std::uint64_t>(dst);
  for (int line = 0; line < count; ++line) {
    const std::uint8_t* inLine = in + static_cast<std::size_t>(line) * inLineStride;
    std::uint8_t* outLine = out + static_cast<std::size_t>(line) * outLineStride;
    for (std::uint64_t j = 0; j < dstSize; ++j) {
      const std::uint64_t begin = j * srcSize;
      const std::uint64_t end = begin + srcSize;
      std::array<std::uint64_t, 4> sum{};
      for (std::uint64_t i = begin / dstSize; i * dstSize < end; ++i) {
        const std::uint64_t overlap =
            std::min((i + 1) * dstSize, end) - std::max(i * dstSize, begin);
        const std::uint8_t* px = inLine + i * inStep;
        for (int c = 0; c < 4; ++c) {
          sum[c] += overlap * px[c];
        }
      }
      std::uint8_t* px = outLine + j * outStep;
      for (int c = 0; c < 4; ++c) {
        px[c] = static_cast<std::uint8_t>((sum[c] + srcSize / 2) / srcSize);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Blur: three successive box blurs approximate a Gaussian of the requested
// standard deviation (central limit theorem; box sizes from W. Kovesi, "Fast
// almost-Gaussian filtering", 2010). Each box is a running sum, so the cost
// is independent of the radius. Edges repeat the border pixel, so the image
// keeps its size and the borders do not fade to transparent.
// ---------------------------------------------------------------------------

std::array<int, 3> boxRadiiForSigma(int sigma) {
  constexpr int n = 3;
  const double variance12 = 12.0 * sigma * sigma;
  int lower = static_cast<int>(std::floor(std::sqrt(variance12 / n + 1)));
  if (lower % 2 == 0) {
    --lower;
  }
  const int upper = lower + 2;
  // How many of the n boxes use the lower width so the variances add up.
  const double idealLowerCount =
      (variance12 - n * lower * lower - 4.0 * n * lower - 3.0 * n) /
      (-4.0 * lower - 4.0);
  const long lowerCount = std::lround(idealLowerCount);

  std::array<int, 3> radii{};
  for (int i = 0; i < n; ++i) {
    const int width = i < lowerCount ? lower : upper;
    radii[static_cast<std::size_t>(i)] = (width - 1) / 2;
  }
  return radii;
}

// One box pass over `count` lines of `length` pixels, in place. `scratch`
// holds a copy of the current line, because the window reads pixels the pass
// has already overwritten.
void boxBlurLines(std::uint8_t* pixels, int length, int count, std::size_t step,
                  std::size_t lineStride, int radius,
                  std::vector<std::uint8_t>& scratch) {
  if (radius <= 0 || length <= 1) {
    return;
  }
  const auto size = static_cast<std::uint32_t>(2 * radius + 1);
  const auto last = length - 1;
  scratch.resize(static_cast<std::size_t>(length) * 4);

  for (int line = 0; line < count; ++line) {
    std::uint8_t* base = pixels + static_cast<std::size_t>(line) * lineStride;
    for (int x = 0; x < length; ++x) {
      std::copy_n(base + static_cast<std::size_t>(x) * step, 4,
                  scratch.begin() + static_cast<std::ptrdiff_t>(x) * 4);
    }
    auto sample = [&](int x, int c) -> std::uint32_t {
      return scratch[static_cast<std::size_t>(std::clamp(x, 0, last)) * 4 +
                     static_cast<std::size_t>(c)];
    };

    for (int c = 0; c < 4; ++c) {
      // Window [x - radius, x + radius] for x = 0, edges clamped.
      std::uint32_t sum = 0;
      for (int k = -radius; k <= radius; ++k) {
        sum += sample(k, c);
      }
      for (int x = 0; x < length; ++x) {
        base[static_cast<std::size_t>(x) * step + static_cast<std::size_t>(c)] =
            static_cast<std::uint8_t>((sum + size / 2) / size);
        sum += sample(x + radius + 1, c);
        sum -= sample(x - radius, c);
      }
    }
  }
}

struct Argb {
  std::uint32_t a, r, g, b;
};

Argb unpack(std::uint32_t argb) {
  return {(argb >> 24) & 0xff, (argb >> 16) & 0xff, (argb >> 8) & 0xff,
          argb & 0xff};
}

// Rounded x / 255 for x in [0, 255 * 255].
std::uint8_t div255(std::uint32_t x) {
  return static_cast<std::uint8_t>((x + 127) / 255);
}

void appendField(std::string& key, char name, std::uint32_t value, bool hex) {
  std::array<char, 16> buffer{};
  const int length = std::snprintf(buffer.data(), buffer.size(),
                                   hex ? ";%c=%08x" : ";%c=%u", name, value);
  key.append(buffer.data(), static_cast<std::size_t>(length));
}

}  // namespace

ProcessingSpec resolveProcessing(const ProcessingOptions& options,
                                 double pixelRatio) {
  const double ratio = isUsable(pixelRatio) ? pixelRatio : 1.0;
  ProcessingSpec spec;
  if (isUsable(options.resize)) {
    // A positive request never collapses to "no resize".
    const double pixels = std::round(options.resize * ratio);
    spec.resizeWidth = static_cast<int>(
        std::clamp(pixels, 1.0, static_cast<double>(kMaxResizeWidth)));
  }
  if (isUsable(options.blur)) {
    // Rounds to whole pixels like 1.x (`blur.intValue`); below 0.5 a
    // Gaussian is invisible, so it rounds to "no blur".
    spec.blurRadius = static_cast<int>(std::clamp(
        std::round(options.blur), 0.0, static_cast<double>(kMaxBlurRadius)));
  }
  spec.monochrome = options.monochrome;
  spec.tint = options.tint;
  return spec;
}

std::string processorKey(const ProcessingSpec& spec) {
  if (spec.empty()) {
    return {};
  }
  std::string key(kKeyVersion);
  if (spec.resizeWidth > 0) {
    appendField(key, 'w', static_cast<std::uint32_t>(spec.resizeWidth), false);
  }
  if (spec.blurRadius > 0) {
    appendField(key, 'b', static_cast<std::uint32_t>(spec.blurRadius), false);
  }
  if (spec.monochrome) {
    appendField(key, 'm', *spec.monochrome, true);
  }
  if (spec.tint) {
    appendField(key, 't', *spec.tint, true);
  }
  return key;
}

std::optional<ProcessingSpec> parseProcessorKey(std::string_view key) {
  if (!key.starts_with(kKeyVersion)) {
    return std::nullopt;
  }
  ProcessingSpec spec;
  std::string_view rest = key.substr(kKeyVersion.size());
  while (!rest.empty()) {
    // Each field is ";<name>=<value>".
    if (rest.size() < 4 || rest[0] != ';' || rest[2] != '=') {
      return std::nullopt;
    }
    const char name = rest[1];
    rest.remove_prefix(3);
    const auto end = std::min(rest.find(';'), rest.size());
    const std::string_view text = rest.substr(0, end);
    rest.remove_prefix(end);

    const int base = (name == 'm' || name == 't') ? 16 : 10;
    std::uint32_t value = 0;
    const auto [ptr, error] =
        std::from_chars(text.data(), text.data() + text.size(), value, base);
    if (error != std::errc{} || ptr != text.data() + text.size()) {
      return std::nullopt;
    }
    switch (name) {
      case 'w':
        spec.resizeWidth = static_cast<int>(
            std::min<std::uint32_t>(value, kMaxResizeWidth + 1));
        break;
      case 'b':
        spec.blurRadius = static_cast<int>(
            std::min<std::uint32_t>(value, kMaxBlurRadius + 1));
        break;
      case 'm':
        spec.monochrome = value;
        break;
      case 't':
        spec.tint = value;
        break;
      default:
        return std::nullopt;
    }
  }
  // Strictness without a grammar: a key is valid only if it is exactly what
  // processorKey would write for the spec it parsed to. That rejects field
  // reordering, duplicates, leading zeros, upper-case hex, out-of-range
  // values and the empty spec in one comparison.
  if (spec.resizeWidth > kMaxResizeWidth || spec.blurRadius > kMaxBlurRadius ||
      processorKey(spec) != key) {
    return std::nullopt;
  }
  return spec;
}

RgbaImage resizeToWidth(const RgbaImage& image, int width) {
  if (width <= 0 || width >= image.width || !hasValidBuffer(image)) {
    return image;  // never upscale
  }
  // Preserve the aspect ratio, rounding to the nearest row.
  const auto srcW = static_cast<std::int64_t>(image.width);
  const auto srcH = static_cast<std::int64_t>(image.height);
  const int height = static_cast<int>(
      std::max<std::int64_t>(1, (srcH * width + srcW / 2) / srcW));

  // Horizontal pass (rows), then vertical (columns). Separable area
  // averaging is exactly equivalent to the 2-D box footprint.
  std::vector<std::uint8_t> rows(static_cast<std::size_t>(width) *
                                 static_cast<std::size_t>(image.height) * 4);
  resampleLines(image.pixels.data(), rows.data(), image.width, width,
                image.height, 4, static_cast<std::size_t>(image.width) * 4, 4,
                static_cast<std::size_t>(width) * 4);

  RgbaImage out{.width = width,
                .height = height,
                .pixels = std::vector<std::uint8_t>(
                    static_cast<std::size_t>(width) *
                    static_cast<std::size_t>(height) * 4)};
  const auto rowStride = static_cast<std::size_t>(width) * 4;
  resampleLines(rows.data(), out.pixels.data(), image.height, height, width,
                rowStride, 4, rowStride, 4);
  return out;
}

void gaussianBlur(RgbaImage& image, int radius) {
  if (radius <= 0 || !hasValidBuffer(image)) {
    return;
  }
  radius = std::min(radius, kMaxBlurRadius);
  // TODO: the column passes stride a whole row per sample, which dominates
  // the ~270 ms a 12 MP blur takes. Blurring a transposed copy (or tiles)
  // would keep them cache-friendly.
  const auto rowStride = static_cast<std::size_t>(image.width) * 4;
  std::vector<std::uint8_t> scratch;
  for (const int box : boxRadiiForSigma(radius)) {
    boxBlurLines(image.pixels.data(), image.width, image.height, 4, rowStride,
                 box, scratch);
    boxBlurLines(image.pixels.data(), image.height, image.width, rowStride, 4,
                 box, scratch);
  }
}

// Maps each pixel's luminance onto the colour: white becomes the colour,
// black stays black, so `monochrome="white"` is plain greyscale. The colour's
// alpha is the effect's intensity (blend with the original), which gives the
// otherwise meaningless alpha of a monochrome colour a useful job.
void monochrome(RgbaImage& image, std::uint32_t argb) {
  if (!hasValidBuffer(image)) {
    return;
  }
  const Argb color = unpack(argb);
  for (std::size_t i = 0; i < image.pixels.size(); i += 4) {
    std::uint8_t* px = &image.pixels[i];
    // Rec. 709 luma weights scaled to sum to 256. Computed on premultiplied
    // values, so the result is already premultiplied (luma <= alpha).
    const std::uint32_t luma = (54u * px[0] + 183u * px[1] + 19u * px[2] + 128u) >> 8;
    const std::array<std::uint32_t, 3> channel = {color.r, color.g, color.b};
    for (std::size_t c = 0; c < 3; ++c) {
      const std::uint32_t mono = div255(luma * channel[c]);
      px[c] = div255(mono * color.a + px[c] * (255u - color.a));
    }
  }
}

// Porter-Duff "source atop" with a solid colour, the same operation as 1.x
// Android's ColorFilterTransformation and iOS's template tinting: opaque
// pixels take the colour, transparency is kept. A translucent colour mixes
// with the original.
void tint(RgbaImage& image, std::uint32_t argb) {
  if (!hasValidBuffer(image)) {
    return;
  }
  const Argb color = unpack(argb);
  const std::array<std::uint32_t, 3> channel = {color.r, color.g, color.b};
  for (std::size_t i = 0; i < image.pixels.size(); i += 4) {
    std::uint8_t* px = &image.pixels[i];
    const std::uint32_t alpha = px[3];
    for (std::size_t c = 0; c < 3; ++c) {
      // Colour premultiplied by the pixel's coverage, then mixed by the
      // colour's own alpha.
      const std::uint32_t source = div255(channel[c] * alpha);
      px[c] = div255(source * color.a + px[c] * (255u - color.a));
    }
  }
}

RgbaImage applyProcessing(RgbaImage image, const ProcessingSpec& spec) {
  if (spec.resizeWidth > 0) {
    image = resizeToWidth(image, spec.resizeWidth);
  }
  gaussianBlur(image, spec.blurRadius);
  if (spec.monochrome) {
    monochrome(image, *spec.monochrome);
  }
  if (spec.tint) {
    tint(image, *spec.tint);
  }
  return image;
}

std::optional<RgbaImage> processImage(RgbaImage image, std::string_view key) {
  const auto spec = parseProcessorKey(key);
  if (!spec || !hasValidBuffer(image)) {
    return std::nullopt;
  }
  return applyProcessing(std::move(image), *spec);
}

}  // namespace turboimage
