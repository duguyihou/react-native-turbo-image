#include <gtest/gtest.h>

#include <array>
#include <cstdint>
#include <string_view>

#include "turboimage/Placeholder.h"

namespace turboimage {
namespace {

struct Spot {
  int x;
  int y;
  std::array<int, 4> rgba;
};

struct BlurhashGolden {
  const char* name;
  std::string_view hash;
  int width;
  int height;
  std::uint32_t fnv1a;
  std::array<Spot, 3> spots;
};

struct ThumbhashGolden {
  const char* name;
  std::string_view base64;
  int width;
  int height;
  std::uint32_t fnv1a;
  std::array<Spot, 3> spots;
};

#include "PlaceholderGoldens.inc"

std::uint32_t fnv1a(const std::vector<std::uint8_t>& bytes) {
  std::uint32_t hash = 0x811c9dc5u;
  for (const auto b : bytes) {
    hash ^= b;
    hash *= 0x01000193u;
  }
  return hash;
}

// Spot pixels first, so a mismatch reports where the output diverged.
void expectMatches(const RgbaImage& image, int width, int height,
                   std::uint32_t expectedHash, const std::array<Spot, 3>& spots) {
  ASSERT_EQ(image.width, width);
  ASSERT_EQ(image.height, height);
  ASSERT_EQ(image.pixels.size(), static_cast<std::size_t>(width * height * 4));
  for (const auto& s : spots) {
    const auto* px = &image.pixels[static_cast<std::size_t>((s.y * width + s.x) * 4)];
    EXPECT_EQ((std::array<int, 4>{px[0], px[1], px[2], px[3]}), s.rgba)
        << "at (" << s.x << ", " << s.y << ")";
  }
  EXPECT_EQ(fnv1a(image.pixels), expectedHash);
}

// --- byte-exact agreement with the JS references ---------------------------

class BlurhashGoldenTest : public ::testing::TestWithParam<BlurhashGolden> {};

TEST_P(BlurhashGoldenTest, MatchesReference) {
  const auto& g = GetParam();
  const auto image = decodeBlurhash(g.hash, g.width, g.height);
  ASSERT_TRUE(image.has_value());
  expectMatches(*image, g.width, g.height, g.fnv1a, g.spots);
}

INSTANTIATE_TEST_SUITE_P(Reference, BlurhashGoldenTest,
                         ::testing::ValuesIn(kBlurhashGoldens),
                         [](const auto& info) { return std::string(info.param.name); });

class ThumbhashGoldenTest : public ::testing::TestWithParam<ThumbhashGolden> {};

TEST_P(ThumbhashGoldenTest, MatchesReference) {
  const auto& g = GetParam();
  const auto image = decodeThumbhash(g.base64);
  ASSERT_TRUE(image.has_value());
  expectMatches(*image, g.width, g.height, g.fnv1a, g.spots);
}

INSTANTIATE_TEST_SUITE_P(Reference, ThumbhashGoldenTest,
                         ::testing::ValuesIn(kThumbhashGoldens),
                         [](const auto& info) { return std::string(info.param.name); });

// --- untrusted input --------------------------------------------------------

TEST(Blurhash, RejectsMalformedInput) {
  constexpr std::string_view valid = "LEHV6nWB2yk8pyo0adR*.7kCMdnj";
  EXPECT_FALSE(decodeBlurhash("", 32, 32));
  EXPECT_FALSE(decodeBlurhash("LEHV6", 32, 32));                    // < 6 chars
  EXPECT_FALSE(decodeBlurhash(valid.substr(0, valid.size() - 1), 32, 32));  // length vs components
  EXPECT_FALSE(decodeBlurhash("LEHV6nWB2yk8pyo0adR*.7kCMdn\"", 32, 32));    // non-base83 char
  EXPECT_FALSE(decodeBlurhash(valid, 0, 32));
  EXPECT_FALSE(decodeBlurhash(valid, 32, 129));
}

TEST(Thumbhash, RejectsMalformedInput) {
  EXPECT_FALSE(decodeThumbhash(""));
  EXPECT_FALSE(decodeThumbhash("not base64!"));
  EXPECT_FALSE(decodeThumbhash("4AcK"));  // header only, no AC data
  // A valid hash truncated by a few bytes must be rejected, not over-read.
  constexpr std::string_view valid = "4AcKPJpwd3dwd3eHh3eAgAj3iA==";
  EXPECT_FALSE(decodeThumbhash(valid.substr(0, 16)));
}

TEST(Thumbhash, AcceptsUnpaddedBase64) {
  const auto padded = decodeThumbhash("4AcKPJpwd3dwd3eHh3eAgAj3iA==");
  const auto unpadded = decodeThumbhash("4AcKPJpwd3dwd3eHh3eAgAj3iA");
  ASSERT_TRUE(padded && unpadded);
  EXPECT_EQ(padded->pixels, unpadded->pixels);
}

// --- what the views consume ------------------------------------------------

TEST(PremultiplyAlpha, ScalesColourByAlphaAndKeepsOpaquePixels) {
  RgbaImage image{.width = 2, .height = 1, .pixels = {200, 100, 50, 255, 200, 100, 50, 128}};
  premultiplyAlpha(image);
  EXPECT_EQ(image.pixels, (std::vector<std::uint8_t>{200, 100, 50, 255, 100, 50, 25, 128}));
}

TEST(DecodePlaceholder, PrefersBlurhashAndPremultiplies) {
  const auto both = decodePlaceholder("LEHV6nWB2yk8pyo0adR*.7kCMdnj", "oxiGG44ooYewiImhsBn6Z3B3c3h3eHc=");
  const auto blurhashOnly = decodeBlurhash("LEHV6nWB2yk8pyo0adR*.7kCMdnj", 32, 32);
  ASSERT_TRUE(both && blurhashOnly);
  EXPECT_EQ(both->pixels, blurhashOnly->pixels);  // opaque: premultiply is a no-op

  auto straight = decodeThumbhash("oxiGG44ooYewiImhsBn6Z3B3c3h3eHc=");
  const auto premultiplied = decodePlaceholder("", "oxiGG44ooYewiImhsBn6Z3B3c3h3eHc=");
  ASSERT_TRUE(straight && premultiplied);
  premultiplyAlpha(*straight);
  EXPECT_EQ(premultiplied->pixels, straight->pixels);
}

TEST(DecodePlaceholder, EmptyOrInvalidYieldsNothing) {
  EXPECT_FALSE(decodePlaceholder("", ""));
  EXPECT_FALSE(decodePlaceholder("garbage", ""));
}

}  // namespace
}  // namespace turboimage
