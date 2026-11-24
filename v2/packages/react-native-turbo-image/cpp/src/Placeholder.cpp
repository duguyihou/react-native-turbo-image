#include "turboimage/Placeholder.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <numbers>

// Bit-for-bit agreement with the JS references (and between iOS and
// Android) requires that `a * b + c` is not fused into an FMA, which rounds
// once instead of twice. Clang (Apple and NDK) contracts by default on
// arm64; this pragma turns it off for this file. GCC honours
// -ffp-contract=off already in strict ISO mode (CXX_EXTENSIONS OFF).
#if defined(__clang__)
#pragma STDC FP_CONTRACT OFF
#endif

namespace turboimage {

namespace {

constexpr double kPi = std::numbers::pi;

// ---------------------------------------------------------------------------
// blurhash — port of npm `blurhash` 2.0.5 `decode` (Wolt).
// ---------------------------------------------------------------------------

constexpr std::string_view kBase83Alphabet =
    "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?"
    "@[]^_{|}~";

// Returns -1 for characters outside the alphabet. (The reference silently
// computes garbage for them; we reject the hash instead.)
int base83Digit(char c) {
  const auto pos = kBase83Alphabet.find(c);
  return pos == std::string_view::npos ? -1 : static_cast<int>(pos);
}

std::optional<int> decode83(std::string_view s) {
  int value = 0;
  for (const char c : s) {
    const int digit = base83Digit(c);
    if (digit < 0) {
      return std::nullopt;
    }
    value = value * 83 + digit;
  }
  return value;
}

double sRgbToLinear(int value) {
  const double v = value / 255.0;
  return v <= 0.04045 ? v / 12.92 : std::pow((v + 0.055) / 1.055, 2.4);
}

std::uint8_t linearToSrgb(double value) {
  const double v = std::clamp(value, 0.0, 1.0);
  // `Math.trunc(x + 0.5)` in the reference; x >= 0 so truncation == floor.
  const double scaled = v <= 0.0031308
                            ? v * 12.92 * 255 + 0.5
                            : (1.055 * std::pow(v, 0.4166666666666667) - 0.055) * 255 + 0.5;
  return static_cast<std::uint8_t>(scaled);
}

double signPow(double value, double exp) {
  return (value < 0 ? -1.0 : 1.0) * std::pow(std::abs(value), exp);
}

using Rgb = std::array<double, 3>;

}  // namespace

std::optional<RgbaImage> decodeBlurhash(std::string_view hash, int width,
                                        int height) {
  if (width < 1 || width > 128 || height < 1 || height > 128 ||
      hash.size() < 6) {
    return std::nullopt;
  }

  const auto sizeFlag = decode83(hash.substr(0, 1));
  const auto quantisedMax = decode83(hash.substr(1, 1));
  if (!sizeFlag || !quantisedMax) {
    return std::nullopt;
  }
  const int numY = *sizeFlag / 9 + 1;
  const int numX = *sizeFlag % 9 + 1;
  if (hash.size() != static_cast<std::size_t>(4 + 2 * numX * numY)) {
    return std::nullopt;
  }
  // TurboImage always decodes with punch = 1. (The reference computes
  // `punch | 1`, which would turn 2 into 3; irrelevant at 1.)
  const double maximumValue = (*quantisedMax + 1) / 166.0;

  std::vector<Rgb> colours(static_cast<std::size_t>(numX * numY));
  for (int i = 0; i < numX * numY; ++i) {
    if (i == 0) {
      const auto dc = decode83(hash.substr(2, 4));
      if (!dc) {
        return std::nullopt;
      }
      colours[0] = {sRgbToLinear(*dc >> 16), sRgbToLinear((*dc >> 8) & 255),
                    sRgbToLinear(*dc & 255)};
    } else {
      const auto ac = decode83(hash.substr(4 + i * 2, 2));
      if (!ac) {
        return std::nullopt;
      }
      const int quantR = *ac / 361;
      const int quantG = (*ac / 19) % 19;
      const int quantB = *ac % 19;
      colours[static_cast<std::size_t>(i)] = {
          signPow((quantR - 9) / 9.0, 2) * maximumValue,
          signPow((quantG - 9) / 9.0, 2) * maximumValue,
          signPow((quantB - 9) / 9.0, 2) * maximumValue};
    }
  }

  RgbaImage image{.width = width,
                  .height = height,
                  .pixels = std::vector<std::uint8_t>(
                      static_cast<std::size_t>(width * height * 4))};
  // Each cosine depends on one axis only, so it is computed once per column
  // (or row) and component: (width + height) × components calls instead of
  // two per pixel per component (~2.6 M for a 128 px, 9×9 hash). The
  // expressions are the reference's, so the values, and the pixels, are
  // bit-identical (the golden tests hash them).
  std::vector<double> cosX(static_cast<std::size_t>(width * numX));
  for (int x = 0; x < width; ++x) {
    for (int i = 0; i < numX; ++i) {
      cosX[static_cast<std::size_t>(x * numX + i)] = std::cos(kPi * x * i / width);
    }
  }
  std::vector<double> cosY(static_cast<std::size_t>(height * numY));
  for (int y = 0; y < height; ++y) {
    for (int j = 0; j < numY; ++j) {
      cosY[static_cast<std::size_t>(y * numY + j)] = std::cos(kPi * y * j / height);
    }
  }
  for (int y = 0; y < height; ++y) {
    for (int x = 0; x < width; ++x) {
      double r = 0;
      double g = 0;
      double b = 0;
      for (int j = 0; j < numY; ++j) {
        for (int i = 0; i < numX; ++i) {
          // Same operation order as the reference; see FP_CONTRACT above.
          const double basis = cosX[static_cast<std::size_t>(x * numX + i)] *
                               cosY[static_cast<std::size_t>(y * numY + j)];
          const Rgb& c = colours[static_cast<std::size_t>(i + j * numX)];
          r += c[0] * basis;
          g += c[1] * basis;
          b += c[2] * basis;
        }
      }
      auto* px = &image.pixels[static_cast<std::size_t>(4 * (x + y * width))];
      px[0] = linearToSrgb(r);
      px[1] = linearToSrgb(g);
      px[2] = linearToSrgb(b);
      px[3] = 255;
    }
  }
  return image;
}

// ---------------------------------------------------------------------------
// thumbhash — port of npm `thumbhash` 0.1.1 `thumbHashToRGBA` (Evan Wallace).
// ---------------------------------------------------------------------------

namespace {

// Standard base64 (RFC 4648 §4), padding optional. Whitespace is rejected:
// JS callers pass the hash verbatim.
std::optional<std::vector<std::uint8_t>> decodeBase64(std::string_view in) {
  while (!in.empty() && in.back() == '=') {
    in.remove_suffix(1);
  }
  if (in.size() % 4 == 1) {
    return std::nullopt;
  }
  auto sextet = [](char c) -> int {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
  };
  std::vector<std::uint8_t> out;
  out.reserve(in.size() * 3 / 4);
  std::uint32_t buffer = 0;
  int bits = 0;
  for (const char c : in) {
    const int v = sextet(c);
    if (v < 0) {
      return std::nullopt;
    }
    buffer = (buffer << 6) | static_cast<std::uint32_t>(v);
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out.push_back(static_cast<std::uint8_t>((buffer >> bits) & 0xFF));
    }
  }
  return out;
}

// Number of AC coefficients `decodeChannel(nx, ny, …)` reads.
int acCount(int nx, int ny) {
  int n = 0;
  for (int cy = 0; cy < ny; ++cy) {
    for (int cx = cy ? 0 : 1; cx * ny < nx * (ny - cy); ++cx) {
      ++n;
    }
  }
  return n;
}

// Same formula as the reference's `Math.max(0, 255 * Math.min(1, v))`
// stored into a Uint8Array (which truncates).
std::uint8_t toByte(double v) {
  return static_cast<std::uint8_t>(std::max(0.0, 255 * std::min(1.0, v)));
}

}  // namespace

std::optional<RgbaImage> decodeThumbhash(std::string_view base64Hash) {
  const auto decoded = decodeBase64(base64Hash);
  if (!decoded || decoded->size() < 5) {
    return std::nullopt;
  }
  const auto& hash = *decoded;

  const std::uint32_t header24 = hash[0] | (hash[1] << 8) | (hash[2] << 16);
  const std::uint32_t header16 = hash[3] | (hash[4] << 8);
  const double lDc = (header24 & 63) / 63.0;
  const double pDc = ((header24 >> 6) & 63) / 31.5 - 1;
  const double qDc = ((header24 >> 12) & 63) / 31.5 - 1;
  const double lScale = ((header24 >> 18) & 31) / 31.0;
  const bool hasAlpha = (header24 >> 23) != 0;
  const double pScale = ((header16 >> 3) & 63) / 63.0;
  const double qScale = ((header16 >> 9) & 63) / 63.0;
  const bool isLandscape = (header16 >> 15) != 0;
  const int lx = std::max(3, isLandscape ? (hasAlpha ? 5 : 7)
                                         : static_cast<int>(header16 & 7));
  const int ly = std::max(3, isLandscape ? static_cast<int>(header16 & 7)
                                         : (hasAlpha ? 5 : 7));

  // Validate the length before reading any AC nibble (the reference does
  // not, and would read past the end of a truncated hash).
  const std::size_t acStart = hasAlpha ? 6 : 5;
  const int totalAc =
      acCount(lx, ly) + 2 * acCount(3, 3) + (hasAlpha ? acCount(5, 5) : 0);
  if (hash.size() < acStart + static_cast<std::size_t>((totalAc + 1) / 2)) {
    return std::nullopt;
  }
  const double aDc = hasAlpha ? (hash[5] & 15) / 15.0 : 1.0;
  const double aScale = hasAlpha ? (hash[5] >> 4) / 15.0 : 0.0;

  int acIndex = 0;
  auto decodeChannel = [&](int nx, int ny, double scale) {
    std::vector<double> ac;
    for (int cy = 0; cy < ny; ++cy) {
      for (int cx = cy ? 0 : 1; cx * ny < nx * (ny - cy); ++cx) {
        const int nibble =
            (hash[acStart + static_cast<std::size_t>(acIndex >> 1)] >>
             ((acIndex & 1) << 2)) &
            15;
        ++acIndex;
        ac.push_back((nibble / 7.5 - 1) * scale);
      }
    }
    return ac;
  };
  const auto lAc = decodeChannel(lx, ly, lScale);
  const auto pAc = decodeChannel(3, 3, pScale * 1.25);
  const auto qAc = decodeChannel(3, 3, qScale * 1.25);
  const auto aAc = hasAlpha ? decodeChannel(5, 5, aScale) : std::vector<double>{};

  // thumbHashToApproximateAspectRatio: note it reads the *raw* header nibble
  // (not clamped to >= 3), exactly like the reference.
  const int rawHeader = hash[3];
  const bool ratioHasAlpha = (hash[2] & 0x80) != 0;
  const bool ratioLandscape = (hash[4] & 0x80) != 0;
  const int rlx = ratioLandscape ? (ratioHasAlpha ? 5 : 7) : (rawHeader & 7);
  const int rly = ratioLandscape ? (rawHeader & 7) : (ratioHasAlpha ? 5 : 7);
  if (rlx == 0 || rly == 0) {
    return std::nullopt;
  }
  const double ratio = static_cast<double>(rlx) / rly;
  // Math.round on positive values.
  const int w = static_cast<int>(std::floor((ratio > 1 ? 32 : 32 * ratio) + 0.5));
  const int h = static_cast<int>(std::floor((ratio > 1 ? 32 / ratio : 32) + 0.5));
  if (w < 1 || h < 1) {
    return std::nullopt;
  }

  RgbaImage image{.width = w,
                  .height = h,
                  .pixels = std::vector<std::uint8_t>(
                      static_cast<std::size_t>(w * h * 4))};
  std::array<double, 7> fy{};
  const int nx = std::max(lx, hasAlpha ? 5 : 3);
  const int ny = std::max(ly, hasAlpha ? 5 : 3);
  // The reference computes both factors for every pixel, though `fx` depends
  // on the column only and `fy` on the row only. Same expressions, so the
  // same values (see the blurhash decoder above).
  std::vector<std::array<double, 7>> columns(static_cast<std::size_t>(w));
  for (int x = 0; x < w; ++x) {
    for (int cx = 0; cx < nx; ++cx) {
      columns[static_cast<std::size_t>(x)][static_cast<std::size_t>(cx)] =
          std::cos(kPi / w * (x + 0.5) * cx);
    }
  }
  for (int y = 0, i = 0; y < h; ++y) {
    for (int cy = 0; cy < ny; ++cy) {
      fy[static_cast<std::size_t>(cy)] = std::cos(kPi / h * (y + 0.5) * cy);
    }
    for (int x = 0; x < w; ++x, i += 4) {
      double l = lDc;
      double p = pDc;
      double q = qDc;
      double a = aDc;
      const std::array<double, 7>& fx = columns[static_cast<std::size_t>(x)];
      for (int cy = 0, j = 0; cy < ly; ++cy) {
        const double fy2 = fy[static_cast<std::size_t>(cy)] * 2;
        for (int cx = cy ? 0 : 1; cx * ly < lx * (ly - cy); ++cx, ++j) {
          l += lAc[static_cast<std::size_t>(j)] * fx[static_cast<std::size_t>(cx)] * fy2;
        }
      }
      for (int cy = 0, j = 0; cy < 3; ++cy) {
        const double fy2 = fy[static_cast<std::size_t>(cy)] * 2;
        for (int cx = cy ? 0 : 1; cx < 3 - cy; ++cx, ++j) {
          const double f = fx[static_cast<std::size_t>(cx)] * fy2;
          p += pAc[static_cast<std::size_t>(j)] * f;
          q += qAc[static_cast<std::size_t>(j)] * f;
        }
      }
      if (hasAlpha) {
        for (int cy = 0, j = 0; cy < 5; ++cy) {
          const double fy2 = fy[static_cast<std::size_t>(cy)] * 2;
          for (int cx = cy ? 0 : 1; cx < 5 - cy; ++cx, ++j) {
            a += aAc[static_cast<std::size_t>(j)] * fx[static_cast<std::size_t>(cx)] * fy2;
          }
        }
      }
      const double b = l - 2.0 / 3 * p;
      const double r = (3 * l - b + q) / 2;
      const double g = r - q;
      auto* px = &image.pixels[static_cast<std::size_t>(i)];
      px[0] = toByte(r);
      px[1] = toByte(g);
      px[2] = toByte(b);
      px[3] = toByte(a);
    }
  }
  return image;
}

// ---------------------------------------------------------------------------

void premultiplyAlpha(RgbaImage& image) {
  for (std::size_t i = 0; i + 3 < image.pixels.size(); i += 4) {
    const unsigned a = image.pixels[i + 3];
    if (a == 255) {
      continue;
    }
    // Same truncating formula as 1.x's Swift thumbhash path.
    for (std::size_t c = 0; c < 3; ++c) {
      image.pixels[i + c] = static_cast<std::uint8_t>(image.pixels[i + c] * a / 255);
    }
  }
}

std::optional<RgbaImage> decodePlaceholder(std::string_view blurhash,
                                           std::string_view thumbhash) {
  std::optional<RgbaImage> image;
  if (!blurhash.empty()) {
    // 32x32 matches 1.x; the view scales it up with interpolation.
    image = decodeBlurhash(blurhash, 32, 32);
  } else if (!thumbhash.empty()) {
    image = decodeThumbhash(thumbhash);
  }
  if (image) {
    premultiplyAlpha(*image);
  }
  return image;
}

}  // namespace turboimage
