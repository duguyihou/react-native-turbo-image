#include <gtest/gtest.h>

#include <cmath>
#include <cstdint>
#include <limits>
#include <random>

#include "turboimage/ImageRequest.h"
#include "turboimage/Processing.h"

namespace turboimage {
namespace {

// --- helpers ----------------------------------------------------------------

RgbaImage solid(int width, int height, std::uint8_t r, std::uint8_t g,
                std::uint8_t b, std::uint8_t a) {
  RgbaImage image{.width = width, .height = height, .pixels = {}};
  for (int i = 0; i < width * height; ++i) {
    image.pixels.insert(image.pixels.end(), {r, g, b, a});
  }
  return image;
}

const std::uint8_t* pixel(const RgbaImage& image, int x, int y) {
  return &image.pixels[static_cast<std::size_t>((y * image.width + x) * 4)];
}

// Random premultiplied pixels (every channel <= alpha).
RgbaImage randomPremultiplied(int width, int height, unsigned seed) {
  std::mt19937 rng(seed);
  std::uniform_int_distribution<int> byte(0, 255);
  RgbaImage image{.width = width, .height = height, .pixels = {}};
  for (int i = 0; i < width * height; ++i) {
    const auto a = static_cast<std::uint8_t>(byte(rng));
    for (int c = 0; c < 3; ++c) {
      image.pixels.push_back(static_cast<std::uint8_t>(byte(rng) * a / 255));
    }
    image.pixels.push_back(a);
  }
  return image;
}

::testing::AssertionResult isPremultiplied(const RgbaImage& image) {
  for (std::size_t i = 0; i < image.pixels.size(); i += 4) {
    for (std::size_t c = 0; c < 3; ++c) {
      if (image.pixels[i + c] > image.pixels[i + 3]) {
        return ::testing::AssertionFailure()
               << "channel " << c << " exceeds alpha at byte " << i;
      }
    }
  }
  return ::testing::AssertionSuccess();
}

// --- resolveProcessing ------------------------------------------------------

TEST(ResolveProcessing, DefaultsAreEmpty) {
  EXPECT_TRUE(resolveProcessing({}, 3).empty());
}

TEST(ResolveProcessing, ResizeIsInPointsTimesPixelRatio) {
  EXPECT_EQ(resolveProcessing({.resize = 100}, 3).resizeWidth, 300);
  EXPECT_EQ(resolveProcessing({.resize = 100.4}, 2.625).resizeWidth, 264);
}

TEST(ResolveProcessing, UnusablePixelRatioMeansOne) {
  EXPECT_EQ(resolveProcessing({.resize = 50}, 0).resizeWidth, 50);
  EXPECT_EQ(resolveProcessing({.resize = 50}, -2).resizeWidth, 50);
  EXPECT_EQ(resolveProcessing({.resize = 50}, std::nan("")).resizeWidth, 50);
}

TEST(ResolveProcessing, NonPositiveOrNanValuesAreAbsent) {
  const double nan = std::nan("");
  const double inf = std::numeric_limits<double>::infinity();
  for (const double value : {0.0, -1.0, nan, inf}) {
    EXPECT_TRUE(resolveProcessing({.resize = value, .blur = value}, 2).empty())
        << value;
  }
}

TEST(ResolveProcessing, TinyPositiveResizeStillResizes) {
  EXPECT_EQ(resolveProcessing({.resize = 0.1}, 1).resizeWidth, 1);
}

TEST(ResolveProcessing, BlurRoundsToWholePixelsAndClamps) {
  EXPECT_EQ(resolveProcessing({.blur = 0.4}, 1).blurRadius, 0);
  EXPECT_EQ(resolveProcessing({.blur = 2.5}, 1).blurRadius, 3);
  EXPECT_EQ(resolveProcessing({.blur = 1e9}, 1).blurRadius, kMaxBlurRadius);
  // Blur is in image pixels, not points: the pixel ratio does not apply.
  EXPECT_EQ(resolveProcessing({.blur = 4}, 3).blurRadius, 4);
}

TEST(ResolveProcessing, ColorsPassThrough) {
  const auto spec =
      resolveProcessing({.monochrome = 0xffff0000u, .tint = 0x00000000u}, 1);
  EXPECT_EQ(spec.monochrome, 0xffff0000u);
  // A fully transparent tint is kept: a no-op on pixels, but asked for.
  EXPECT_EQ(spec.tint, 0x00000000u);
}

// --- processorKey / parseProcessorKey ---------------------------------------

TEST(ProcessorKey, EmptySpecHasEmptyKey) {
  EXPECT_EQ(processorKey({}), "");
}

TEST(ProcessorKey, FixedOrderAndFormat) {
  EXPECT_EQ(processorKey({.resizeWidth = 300,
                          .blurRadius = 8,
                          .monochrome = 0xffff0000u,
                          .tint = 0x80abcdefu}),
            "ti1;w=300;b=8;m=ffff0000;t=80abcdef");
  EXPECT_EQ(processorKey({.blurRadius = 2}), "ti1;b=2");
  EXPECT_EQ(processorKey({.tint = 0x1u}), "ti1;t=00000001");
}

TEST(ProcessorKey, RoundTrips) {
  const std::vector<ProcessingSpec> specs = {
      {.resizeWidth = 1},
      {.blurRadius = kMaxBlurRadius},
      {.monochrome = 0u},
      {.tint = 0xffffffffu},
      {.resizeWidth = 65535, .blurRadius = 1, .monochrome = 7u, .tint = 9u},
  };
  for (const auto& spec : specs) {
    const auto key = processorKey(spec);
    EXPECT_EQ(parseProcessorKey(key), spec) << key;
  }
}

TEST(ParseProcessorKey, RejectsAnythingProcessorKeyCannotWrite) {
  for (const char* key : {
           "",
           "ti1",                     // empty spec
           "ti0;w=3",                 // unknown version
           "ti1;b=2;w=3",             // wrong order
           "ti1;w=3;w=4",             // duplicate
           "ti1;w=03",                // leading zero
           "ti1;w=0",                 // zero is "absent"
           "ti1;w=-3",                // sign
           "ti1;w=65536",             // above the resize cap
           "ti1;b=251",               // above the blur cap
           "ti1;m=FFFF0000",          // upper-case hex
           "ti1;m=ff0000",            // short colour
           "ti1;x=1",                 // unknown field
           "ti1;w=",                  // no value
           "ti1;w=3;",                // trailing separator
           "ti1w=3",                  // missing separator
           "ti1;w=99999999999999999", // overflow
       }) {
    EXPECT_EQ(parseProcessorKey(key), std::nullopt) << key;
  }
}

// --- resolveRequest integration ---------------------------------------------

TEST(ResolveRequestProcessing, NoProcessingKeepsAnEmptyKey) {
  const auto result = resolveRequest({.uri = "https://cdn.example.com/a.png"});
  ASSERT_TRUE(result.ok());
  EXPECT_EQ(result.request->processorKey, "");
}

TEST(ResolveRequestProcessing, VariantsShareTheOriginalsCacheKey) {
  const auto plain = resolveRequest({.uri = "https://cdn.example.com/a.png"});
  const auto blurred = resolveRequest({.uri = "https://cdn.example.com/a.png",
                                       .processing = {.resize = 100, .blur = 4},
                                       .pixelRatio = 2});
  ASSERT_TRUE(plain.ok());
  ASSERT_TRUE(blurred.ok());
  // One original on disk, several variants in memory (RFC §4.5a).
  EXPECT_EQ(blurred.request->cacheKey, plain.request->cacheKey);
  EXPECT_EQ(blurred.request->processorKey, "ti1;w=200;b=4");
}

// --- resizeToWidth ----------------------------------------------------------

TEST(ResizeToWidth, NeverUpscales) {
  const auto image = solid(4, 2, 10, 20, 30, 40);
  EXPECT_EQ(resizeToWidth(image, 4).pixels, image.pixels);
  EXPECT_EQ(resizeToWidth(image, 9).width, 4);
}

TEST(ResizeToWidth, AveragesExactAreas) {
  // One row, four pixels: 0, 100, 200, 255 (opaque grey ramp) to 2 pixels.
  RgbaImage image{.width = 4, .height = 1, .pixels = {}};
  for (const std::uint8_t v : {0, 100, 200, 255}) {
    image.pixels.insert(image.pixels.end(), {v, v, v, 255});
  }
  const auto out = resizeToWidth(image, 2);
  ASSERT_EQ(out.width, 2);
  ASSERT_EQ(out.height, 1);
  EXPECT_EQ(pixel(out, 0, 0)[0], 50);   // (0 + 100) / 2
  EXPECT_EQ(pixel(out, 1, 0)[0], 228);  // (200 + 255) / 2 = 227.5, rounded
}

TEST(ResizeToWidth, FractionalFootprintsWeightByOverlap) {
  // 3 -> 2: output 0 covers source 0 fully and half of source 1.
  RgbaImage image{.width = 3, .height = 1, .pixels = {}};
  for (const std::uint8_t v : {0, 90, 180}) {
    image.pixels.insert(image.pixels.end(), {v, v, v, 255});
  }
  const auto out = resizeToWidth(image, 2);
  EXPECT_EQ(pixel(out, 0, 0)[0], 30);   // (2*0 + 1*90) / 3
  EXPECT_EQ(pixel(out, 1, 0)[0], 150);  // (1*90 + 2*180) / 3
}

TEST(ResizeToWidth, PreservesAspectRatioRoundingToNearestRow) {
  EXPECT_EQ(resizeToWidth(solid(400, 300, 0, 0, 0, 255), 100).height, 75);
  EXPECT_EQ(resizeToWidth(solid(3, 2, 0, 0, 0, 255), 2).height, 1);  // 1.33
  EXPECT_EQ(resizeToWidth(solid(3, 5, 0, 0, 0, 255), 2).height, 3);  // 3.33
  EXPECT_EQ(resizeToWidth(solid(1000, 1, 0, 0, 0, 255), 3).height, 1);
}

TEST(ResizeToWidth, SolidStaysSolidAndPremultiplied) {
  const auto out = resizeToWidth(solid(97, 61, 12, 34, 56, 78), 13);
  EXPECT_EQ(out.pixels, solid(13, 8, 12, 34, 56, 78).pixels);
  EXPECT_TRUE(isPremultiplied(resizeToWidth(randomPremultiplied(53, 31, 1), 7)));
}

// --- gaussianBlur -----------------------------------------------------------

TEST(GaussianBlur, ZeroRadiusIsANoOp) {
  auto image = randomPremultiplied(9, 9, 2);
  const auto before = image.pixels;
  gaussianBlur(image, 0);
  EXPECT_EQ(image.pixels, before);
}

TEST(GaussianBlur, SolidImagesAreUnchangedIncludingEdges) {
  // Edges repeat the border pixel, so nothing fades to transparent.
  auto image = solid(20, 7, 10, 20, 30, 200);
  gaussianBlur(image, 5);
  EXPECT_EQ(image.pixels, solid(20, 7, 10, 20, 30, 200).pixels);
}

TEST(GaussianBlur, ApproximatesTheRequestedStandardDeviation) {
  // One bright column: its blurred profile's variance should be ~sigma^2.
  for (const int sigma : {2, 5, 12}) {
    const int width = 8 * sigma * 2 + 1;
    const int centre = width / 2;
    RgbaImage image = solid(width, 1, 0, 0, 0, 255);
    std::uint8_t* px = &image.pixels[static_cast<std::size_t>(centre) * 4];
    px[0] = 255;
    gaussianBlur(image, sigma);

    double mass = 0;
    double variance = 0;
    for (int x = 0; x < width; ++x) {
      const double v = pixel(image, x, 0)[0];
      mass += v;
      variance += v * (x - centre) * (x - centre);
    }
    variance /= mass;
    EXPECT_NEAR(std::sqrt(variance), sigma, 0.15 * sigma) << "sigma " << sigma;
  }
}

TEST(GaussianBlur, IsSymmetricAndKeepsPremultipliedInvariant) {
  RgbaImage image = solid(31, 31, 0, 0, 0, 0);
  std::uint8_t* centre = &image.pixels[static_cast<std::size_t>((15 * 31 + 15) * 4)];
  centre[0] = centre[3] = 255;
  gaussianBlur(image, 3);
  EXPECT_EQ(pixel(image, 12, 15)[0], pixel(image, 18, 15)[0]);
  EXPECT_EQ(pixel(image, 15, 12)[0], pixel(image, 15, 18)[0]);
  EXPECT_EQ(pixel(image, 12, 15)[0], pixel(image, 15, 12)[0]);
  EXPECT_TRUE(isPremultiplied(image));

  auto noisy = randomPremultiplied(40, 25, 3);
  gaussianBlur(noisy, 7);
  EXPECT_TRUE(isPremultiplied(noisy));
}

// The blur's exact output, pinned. Any change to an output byte needs a new
// `kKeyVersion`, or apps keep showing stale cached variants. The hashes come
// from the slower blur, so they prove the faster one gives the same bytes.
//
// Uses raw `std::mt19937` output only (fully specified by the standard), so
// the hashes hold on every toolchain.
TEST(GaussianBlur, OutputIsPinned) {
  auto portableNoise = [](int width, int height, unsigned seed) {
    std::mt19937 rng(seed);
    RgbaImage image{.width = width, .height = height, .pixels = {}};
    image.pixels.resize(static_cast<std::size_t>(width) * height * 4);
    for (std::size_t i = 0; i < image.pixels.size(); i += 4) {
      const auto a = static_cast<std::uint8_t>(rng() % 256);
      image.pixels[i + 3] = a;
      for (std::size_t c = 0; c < 3; ++c) {
        image.pixels[i + c] = static_cast<std::uint8_t>(a == 0 ? 0 : rng() % (a + 1u));
      }
    }
    return image;
  };
  auto fnv1a = [](const RgbaImage& image) {
    std::uint64_t hash = 1469598103934665603ull;
    for (const auto byte : image.pixels) {
      hash = (hash ^ byte) * 1099511628211ull;
    }
    return hash;
  };
  struct Case {
    int width, height, radius;
    unsigned seed;
    std::uint64_t hash;
  };
  const Case cases[] = {
      {301, 203, 1, 11, 0xee12cb3c180489e5ull},
      {301, 203, 6, 12, 0xe9c641629144f8e6ull},
      {301, 203, 40, 13, 0x08f9d94182d2e280ull},
      {301, 203, 250, 14, 0x8f3b29ae90ef25c0ull},
      {15, 40, 3, 15, 0xb1a0aef961765131ull},
      {17, 40, 3, 16, 0x39e40155001f03b8ull},
      {1, 64, 4, 17, 0x32cdd4c563fffe59ull},
      {64, 1, 4, 18, 0x8042b65bce527039ull},
  };
  for (const auto& c : cases) {
    RgbaImage image = portableNoise(c.width, c.height, c.seed);
    gaussianBlur(image, c.radius);
    EXPECT_EQ(fnv1a(image), c.hash)
        << c.width << "x" << c.height << " radius " << c.radius;
  }
}

TEST(GaussianBlur, RadiusLargerThanTheImageIsSafe) {
  auto image = randomPremultiplied(3, 2, 4);
  gaussianBlur(image, kMaxBlurRadius);
  EXPECT_TRUE(isPremultiplied(image));
  // Everything collapses towards the mean; neighbours end up close.
  EXPECT_NEAR(pixel(image, 0, 0)[3], pixel(image, 2, 1)[3], 2);
}

// --- monochrome -------------------------------------------------------------

TEST(Monochrome, WhiteIsGreyscale) {
  auto image = solid(1, 1, 255, 0, 0, 255);  // pure red
  monochrome(image, 0xffffffffu);
  // Rec. 709 luma of red: 54/256 * 255 = 53.8
  EXPECT_EQ(image.pixels, (std::vector<std::uint8_t>{54, 54, 54, 255}));
}

TEST(Monochrome, MapsLuminanceOntoTheColour) {
  auto white = solid(1, 1, 255, 255, 255, 255);
  monochrome(white, 0xffff8000u);
  EXPECT_EQ(white.pixels, (std::vector<std::uint8_t>{255, 128, 0, 255}));

  auto black = solid(1, 1, 0, 0, 0, 255);
  monochrome(black, 0xffff8000u);
  EXPECT_EQ(black.pixels, (std::vector<std::uint8_t>{0, 0, 0, 255}));
}

TEST(Monochrome, ColourAlphaIsIntensity) {
  auto image = solid(1, 1, 200, 100, 50, 255);
  const auto before = image.pixels;
  monochrome(image, 0x00ffffffu);
  EXPECT_EQ(image.pixels, before);
}

TEST(Monochrome, KeepsAlphaAndPremultipliedInvariant) {
  auto image = randomPremultiplied(16, 16, 5);
  const auto before = image;
  monochrome(image, 0xc0ff00ffu);
  for (std::size_t i = 3; i < image.pixels.size(); i += 4) {
    EXPECT_EQ(image.pixels[i], before.pixels[i]);
  }
  EXPECT_TRUE(isPremultiplied(image));
}

// --- tint -------------------------------------------------------------------

TEST(Tint, OpaqueColourFillsCoverageKeepingAlpha) {
  RgbaImage image{.width = 3,
                  .height = 1,
                  .pixels = {10, 20, 30, 255,   //
                             50, 50, 50, 128,   // half-covered
                             0, 0, 0, 0}};      // transparent
  tint(image, 0xff00ff80u);
  EXPECT_EQ(image.pixels, (std::vector<std::uint8_t>{0, 255, 128, 255,  //
                                                     0, 128, 64, 128,   //
                                                     0, 0, 0, 0}));
}

TEST(Tint, TranslucentColourMixes) {
  auto image = solid(1, 1, 0, 0, 0, 255);
  tint(image, 0x80ffffffu);
  // 255 * 128/255 + 0 = 128
  EXPECT_EQ(image.pixels, (std::vector<std::uint8_t>{128, 128, 128, 255}));
  auto noisy = randomPremultiplied(16, 16, 6);
  tint(noisy, 0x7f123456u);
  EXPECT_TRUE(isPremultiplied(noisy));
}

// --- processImage -----------------------------------------------------------

TEST(ProcessImage, AppliesStagesInOrder) {
  // Resize first: the blur radius applies to the resized image. A solid
  // image hides blur, so check dimensions and the tint that ends the chain.
  const auto out = processImage(solid(8, 4, 1, 2, 3, 255),
                                processorKey({.resizeWidth = 4,
                                              .blurRadius = 1,
                                              .monochrome = 0xffffffffu,
                                              .tint = 0xff102030u}));
  ASSERT_TRUE(out.has_value());
  EXPECT_EQ(out->width, 4);
  EXPECT_EQ(out->height, 2);
  EXPECT_EQ(out->pixels, solid(4, 2, 0x10, 0x20, 0x30, 255).pixels);
}

TEST(ProcessImage, RejectsBadKeysAndBuffers) {
  EXPECT_EQ(processImage(solid(2, 2, 0, 0, 0, 255), "ti1;w=0"), std::nullopt);
  EXPECT_EQ(processImage(solid(2, 2, 0, 0, 0, 255), ""), std::nullopt);
  RgbaImage truncated = solid(2, 2, 0, 0, 0, 255);
  truncated.pixels.pop_back();
  EXPECT_EQ(processImage(truncated, "ti1;b=1"), std::nullopt);
}

}  // namespace
}  // namespace turboimage
