#include "turboimage/Processing.h"

#include <algorithm>
#include <array>
#include <charconv>
#include <cmath>
#include <cstdio>
#include <vector>

// No FMA, as in Placeholder.cpp: box sizes use floating point and must match
// across platforms. Clang only; GCC warns on the pragma and does not fuse.
#if defined(__clang__)
#pragma STDC FP_CONTRACT OFF
#endif

namespace turboimage {

namespace {

// Bump whenever any stage's output changes, to invalidate cached variants.
constexpr std::string_view kKeyVersion = "ti1";

// Large enough for any real image; keeps products below 2^63.
constexpr int kMaxResizeWidth = 65535;

bool isUsable(double value) { return std::isfinite(value) && value > 0; }

bool hasValidBuffer(const RgbaImage& image) {
  return image.width > 0 && image.height > 0 &&
         image.pixels.size() == static_cast<std::size_t>(image.width) *
                                    static_cast<std::size_t>(image.height) * 4;
}

// ---------------------------------------------------------------------------
// Resize: exact area averaging, in integers. Source pixel i spans
// [i*dst, (i+1)*dst) and output j spans [j*src, (j+1)*src), so overlaps are
// integer weights summing to `src`.
// ---------------------------------------------------------------------------

// Resamples `count` lines from `src` to `dst` samples. Byte strides let one
// routine serve rows and columns.
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
// Blur: three box blurs approximate a Gaussian (box sizes from Kovesi, "Fast
// almost-Gaussian filtering"). Running sums make cost independent of radius.
// Edges repeat the border pixel so borders do not fade.
// ---------------------------------------------------------------------------

std::array<int, 3> boxRadiiForSigma(int sigma) {
  constexpr int n = 3;
  const double variance12 = 12.0 * sigma * sigma;
  int lower = static_cast<int>(std::floor(std::sqrt(variance12 / n + 1)));
  if (lower % 2 == 0) {
    --lower;
  }
  const int upper = lower + 2;
  // How many boxes use the lower width so the variances add up.
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

// `(sum + size / 2) / size` via multiply by ceil(2^32 / size) and shift, to
// avoid a hardware divide per byte. Exact for size <= 1023 and
// sum <= 255 * size (error < 2^-4); boxes here are at most 501.
class BoxAverage {
 public:
  explicit BoxAverage(std::uint32_t size)
      : half_(size / 2), reciprocal_(((std::uint64_t{1} << 32) + size - 1) / size) {}

  std::uint8_t operator()(std::uint32_t sum) const {
    return static_cast<std::uint8_t>(((sum + half_) * reciprocal_) >> 32);
  }

 private:
  std::uint32_t half_;
  std::uint64_t reciprocal_;
};

// Horizontal box pass, in place. `scratch` copies the row, since the window
// reads pixels already overwritten.
void boxBlurRows(std::uint8_t* pixels, int width, int height, int radius,
                 std::vector<std::uint8_t>& scratch) {
  if (radius <= 0 || width <= 1) {
    return;
  }
  const BoxAverage average(static_cast<std::uint32_t>(2 * radius + 1));
  const auto rowStride = static_cast<std::size_t>(width) * 4;
  const int last = width - 1;
  scratch.resize(rowStride);
  auto at = [&](int x) {
    return scratch.data() + static_cast<std::size_t>(std::clamp(x, 0, last)) * 4;
  };

  for (int y = 0; y < height; ++y) {
    std::uint8_t* out = pixels + static_cast<std::size_t>(y) * rowStride;
    std::copy_n(out, rowStride, scratch.begin());
    // Window [x - radius, x + radius] for x = 0, edges clamped.
    std::array<std::uint32_t, 4> sums{};
    for (int k = -radius; k <= radius; ++k) {
      const std::uint8_t* in = at(k);
      for (std::size_t c = 0; c < 4; ++c) {
        sums[c] += in[c];
      }
    }
    for (int x = 0; x < width; ++x, out += 4) {
      const std::uint8_t* entering = at(x + radius + 1);
      const std::uint8_t* leaving = at(x - radius);
      for (std::size_t c = 0; c < 4; ++c) {
        out[c] = average(sums[c]);
        sums[c] += entering[c];
        sums[c] -= leaving[c];
      }
    }
  }
}

// Vertical box pass, same arithmetic as `boxBlurRows`, over strips of
// `kColumnBlock` columns so each row read is contiguous (cache-friendly).
constexpr int kColumnBlock = 16;

void boxBlurColumns(std::uint8_t* pixels, int width, int height, int radius,
                    std::vector<std::uint8_t>& scratch) {
  if (radius <= 0 || height <= 1) {
    return;
  }
  const BoxAverage average(static_cast<std::uint32_t>(2 * radius + 1));
  const auto rowStride = static_cast<std::size_t>(width) * 4;
  const int last = height - 1;
  std::array<std::uint32_t, kColumnBlock * 4> sums{};

  for (int x0 = 0; x0 < width; x0 += kColumnBlock) {
    const auto stripBytes =
        static_cast<std::size_t>(std::min(kColumnBlock, width - x0)) * 4;
    std::uint8_t* strip = pixels + static_cast<std::size_t>(x0) * 4;
    // Copy the strip, since the window reads rows already overwritten.
    scratch.resize(stripBytes * static_cast<std::size_t>(height));
    for (int y = 0; y < height; ++y) {
      std::copy_n(strip + static_cast<std::size_t>(y) * rowStride, stripBytes,
                  scratch.begin() + static_cast<std::ptrdiff_t>(y * stripBytes));
    }
    auto row = [&](int y) {
      return scratch.data() +
             static_cast<std::size_t>(std::clamp(y, 0, last)) * stripBytes;
    };

    // Window [y - radius, y + radius] for y = 0, edges clamped.
    std::fill(sums.begin(), sums.end(), 0u);
    for (int k = -radius; k <= radius; ++k) {
      const std::uint8_t* in = row(k);
      for (std::size_t i = 0; i < stripBytes; ++i) {
        sums[i] += in[i];
      }
    }
    for (int y = 0; y < height; ++y) {
      std::uint8_t* out = strip + static_cast<std::size_t>(y) * rowStride;
      const std::uint8_t* entering = row(y + radius + 1);
      const std::uint8_t* leaving = row(y - radius);
      for (std::size_t i = 0; i < stripBytes; ++i) {
        out[i] = average(sums[i]);
        sums[i] += entering[i];
        sums[i] -= leaving[i];
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
    // Whole pixels; below 0.5 rounds to "no blur" (invisible anyway).
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
  // Valid only if re-encoding gives the same key: rejects reordering,
  // duplicates, leading zeros, upper-case hex, out-of-range and empty.
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

  // Rows, then columns; separable area averaging is exact.
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
  std::vector<std::uint8_t> scratch;
  for (const int box : boxRadiiForSigma(radius)) {
    boxBlurRows(image.pixels.data(), image.width, image.height, box, scratch);
    boxBlurColumns(image.pixels.data(), image.width, image.height, box,
                   scratch);
  }
}

// Maps luminance onto the colour (white = greyscale). The colour's alpha is
// the effect's intensity.
void monochrome(RgbaImage& image, std::uint32_t argb) {
  if (!hasValidBuffer(image)) {
    return;
  }
  const Argb color = unpack(argb);
  for (std::size_t i = 0; i < image.pixels.size(); i += 4) {
    std::uint8_t* px = &image.pixels[i];
    // Rec. 709 weights summing to 256; on premultiplied values, so
    // luma <= alpha.
    const std::uint32_t luma = (54u * px[0] + 183u * px[1] + 19u * px[2] + 128u) >> 8;
    const std::array<std::uint32_t, 3> channel = {color.r, color.g, color.b};
    for (std::size_t c = 0; c < 3; ++c) {
      const std::uint32_t mono = div255(luma * channel[c]);
      px[c] = div255(mono * color.a + px[c] * (255u - color.a));
    }
  }
}

// Porter-Duff "source atop" with a solid colour: keeps transparency; a
// translucent colour mixes with the original.
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
      // Premultiply by the pixel's alpha, then mix by the colour's alpha.
      const std::uint32_t source = div255(channel[c] * alpha);
      px[c] = div255(source * color.a + px[c] * (255u - color.a));
    }
  }
}

RgbaImage applyProcessing(RgbaImage image, const ProcessingSpec& spec) {
  // Skip when not shrinking: `resizeToWidth` would copy the whole image, and
  // the decode is usually already this width.
  if (spec.resizeWidth > 0 && spec.resizeWidth < image.width) {
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
