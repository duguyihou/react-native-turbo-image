#include <gtest/gtest.h>

#include "turboimage/ImageRequest.h"

namespace turboimage {
namespace {

TEST(CanonicalCacheKey, LowercasesSchemeAndHostOnly) {
  EXPECT_EQ(canonicalCacheKey("HTTPS://CDN.Example.com/Avatars/Ada.PNG?v=A"),
            "https://cdn.example.com/Avatars/Ada.PNG?v=A");
}

TEST(CanonicalCacheKey, DropsFragment) {
  EXPECT_EQ(canonicalCacheKey("https://cdn.example.com/a.png#thumb"),
            "https://cdn.example.com/a.png");
}

TEST(CanonicalCacheKey, HandlesQueryDirectlyAfterHost) {
  EXPECT_EQ(canonicalCacheKey("https://CDN.example.com?id=7"),
            "https://cdn.example.com?id=7");
}

TEST(CanonicalCacheKey, LeavesSchemelessInputUntouched) {
  EXPECT_EQ(canonicalCacheKey("Avatars/Ada.png"), "Avatars/Ada.png");
}

TEST(ResolveRequest, RejectsEmptyUri) {
  const auto result = resolveRequest({.uri = ""});
  EXPECT_FALSE(result.ok());
  EXPECT_EQ(result.error, RequestError::EmptyUri);
}

TEST(ResolveRequest, RejectsUnsupportedScheme) {
  const auto result = resolveRequest({.uri = "ftp://example.com/a.png"});
  EXPECT_EQ(result.error, RequestError::UnsupportedScheme);
}

TEST(ResolveRequest, ExplicitCacheKeyWins) {
  const auto result = resolveRequest(
      {.uri = "https://cdn.example.com/a.png?sig=123", .cacheKey = "user-42"});
  ASSERT_TRUE(result.ok());
  EXPECT_EQ(result.request->cacheKey, "user-42");
  EXPECT_EQ(result.request->url, "https://cdn.example.com/a.png?sig=123");
}

TEST(ResolveRequestHeaders, PassesHeadersThroughInOrder) {
  const auto result = resolveRequest(
      {.uri = "https://cdn.example.com/a.png",
       .headers = {{"Authorization", "Bearer abc.def"}, {"X-Trace", ""}}});
  ASSERT_TRUE(result.ok());
  EXPECT_EQ(result.request->headers,
            (std::vector<Header>{{"Authorization", "Bearer abc.def"}, {"X-Trace", ""}}));
}

TEST(ResolveRequestHeaders, HeadersAreNotPartOfTheCacheKey) {
  const auto plain = resolveRequest({.uri = "https://cdn.example.com/a.png"});
  const auto authed = resolveRequest(
      {.uri = "https://cdn.example.com/a.png", .headers = {{"Authorization", "x"}}});
  ASSERT_TRUE(plain.ok());
  ASSERT_TRUE(authed.ok());
  EXPECT_EQ(plain.request->cacheKey, authed.request->cacheKey);
}

TEST(ResolveRequestHeaders, RejectsInjectionAndNonTokenNames) {
  const std::vector<Header> invalid = {
      {"", "x"},                       // empty name
      {"Bad Name", "x"},               // space
      {"Bad:Name", "x"},               // separator
      {"X-A", "ok\r\nX-Evil: 1"},       // CRLF injection
      {"X-A", "line\nbreak"},          // bare LF
      {"X-A", std::string("nul\0", 4)}, // NUL
  };
  for (const auto& header : invalid) {
    const auto result = resolveRequest(
        {.uri = "https://cdn.example.com/a.png", .headers = {{"Accept", "image/*"}, header}});
    EXPECT_EQ(result.error, RequestError::InvalidHeader) << header.name << ": " << header.value;
  }
}

TEST(ResolveRequestHeaders, AcceptsEveryTokenCharacterAndOpaqueValueBytes) {
  const auto result = resolveRequest(
      {.uri = "https://cdn.example.com/a.png",
       .headers = {{"!#$%&'*+-.^_`|~09azAZ", "tab\tand UTF-8 \xc3\xa9"}}});
  EXPECT_TRUE(result.ok());
}

TEST(ResolveRequestLocal, AcceptsLocalSchemes) {
  for (const char* uri : {"file:///var/mobile/Containers/Bundle/App.app/assets/logo.png",
                          "content://media/external/images/media/42",
                          "android.resource://com.example.app/2131165270",
                          "FILE:///tmp/a.png"}) {
    EXPECT_TRUE(resolveRequest({.uri = uri}).ok()) << uri;
  }
}

TEST(ResolveRequestLocal, StillRejectsOtherSchemes) {
  for (const char* uri : {"data:image/png;base64,iVBOR", "asset:/logo.png", "ph://ABC",
                          "src_assets_logo"}) {
    EXPECT_EQ(resolveRequest({.uri = uri}).error, RequestError::UnsupportedScheme) << uri;
  }
}

class ResolveRequestLocalPolicy : public ::testing::TestWithParam<CachePolicy> {};

TEST_P(ResolveRequestLocalPolicy, NeverUsesDiskAndIsAlwaysReadable) {
  const auto result =
      resolveRequest({.uri = "file:///tmp/logo.png", .cachePolicy = GetParam()});
  ASSERT_TRUE(result.ok());
  EXPECT_EQ(result.request->disk, (TierAccess{.read = false, .write = false}));
  EXPECT_TRUE(result.request->allowNetwork);
  // The memory tier still follows the policy, exactly as for a remote URL.
  const auto remote =
      resolveRequest({.uri = "https://cdn.example.com/logo.png", .cachePolicy = GetParam()});
  ASSERT_TRUE(remote.ok());
  EXPECT_EQ(result.request->memory, remote.request->memory);
}

INSTANTIATE_TEST_SUITE_P(AllPolicies, ResolveRequestLocalPolicy,
                         ::testing::Values(CachePolicy::Default, CachePolicy::MemoryOnly,
                                           CachePolicy::NoCache, CachePolicy::CacheOnly));

TEST(ParseCachePolicy, AcceptsExactlyTheJsNames) {
  EXPECT_EQ(parseCachePolicy("default"), CachePolicy::Default);
  EXPECT_EQ(parseCachePolicy("memoryOnly"), CachePolicy::MemoryOnly);
  EXPECT_EQ(parseCachePolicy("noCache"), CachePolicy::NoCache);
  EXPECT_EQ(parseCachePolicy("cacheOnly"), CachePolicy::CacheOnly);
  // 1.x names are mapped in JS, never sent to native.
  EXPECT_EQ(parseCachePolicy("dataCache"), std::nullopt);
  EXPECT_EQ(parseCachePolicy(""), std::nullopt);
  EXPECT_EQ(parseCachePolicy("Default"), std::nullopt);
}

TEST(LoadErrorCodeName, NamesAreTheJsContract) {
  EXPECT_EQ(loadErrorCodeName(LoadErrorCode::Unknown), "unknown");
  EXPECT_EQ(loadErrorCodeName(LoadErrorCode::InvalidRequest), "invalidRequest");
  EXPECT_EQ(loadErrorCodeName(LoadErrorCode::NotCached), "notCached");
  EXPECT_EQ(loadErrorCodeName(LoadErrorCode::Network), "network");
  EXPECT_EQ(loadErrorCodeName(LoadErrorCode::Decode), "decode");
}

TEST(LoadErrorCodeName, OutOfRangeIsUnknown) {
  EXPECT_EQ(loadErrorCodeName(static_cast<LoadErrorCode>(99)), "unknown");
}

// The cache-tier matrix is the contract both adapters are tested against, so
// spell every policy out explicitly.
struct PolicyCase {
  CachePolicy policy;
  TierAccess memory;
  TierAccess disk;
  bool allowNetwork;
};

class ResolveRequestPolicy : public ::testing::TestWithParam<PolicyCase> {};

TEST_P(ResolveRequestPolicy, MapsToTierAccess) {
  const auto& c = GetParam();
  const auto result = resolveRequest(
      {.uri = "https://cdn.example.com/a.png", .cachePolicy = c.policy});
  ASSERT_TRUE(result.ok());
  EXPECT_EQ(result.request->memory, c.memory);
  EXPECT_EQ(result.request->disk, c.disk);
  EXPECT_EQ(result.request->allowNetwork, c.allowNetwork);
}

INSTANTIATE_TEST_SUITE_P(
    AllPolicies, ResolveRequestPolicy,
    ::testing::Values(
        PolicyCase{CachePolicy::Default, {true, true}, {true, true}, true},
        PolicyCase{CachePolicy::MemoryOnly, {true, true}, {false, false}, true},
        PolicyCase{CachePolicy::NoCache, {false, false}, {false, false}, true},
        PolicyCase{CachePolicy::CacheOnly, {true, false}, {true, false},
                   false}));

// --- decode size ------------------------------------------------------------

constexpr auto kPhoto = "https://cdn.example.com/photos/harbour.jpg";

DecodeSize decodeOf(const ImageRequest& request) {
  const auto result = resolveRequest(request);
  EXPECT_TRUE(result.ok());
  return result.request->decode;
}

TEST(ResolveDecodeSize, DefaultsToTheViewAndFitsForContain) {
  EXPECT_EQ(decodeOf({.uri = kPhoto}),
            (DecodeSize{.kind = DecodeSize::Kind::View, .width = 0, .fill = false}));
}

TEST(ResolveDecodeSize, CoverAndStretchMustFillTheView) {
  for (const auto mode : {ResizeMode::Cover, ResizeMode::Stretch}) {
    EXPECT_EQ(decodeOf({.uri = kPhoto, .resizeMode = mode}),
              (DecodeSize{.kind = DecodeSize::Kind::View, .width = 0, .fill = true}));
  }
}

TEST(ResolveDecodeSize, CenterDrawsOneToOneSoItNeedsTheOriginal) {
  EXPECT_EQ(decodeOf({.uri = kPhoto, .resizeMode = ResizeMode::Center}).kind,
            DecodeSize::Kind::Original);
}

TEST(ResolveDecodeSize, OptOutDecodesTheOriginal) {
  EXPECT_EQ(decodeOf({.uri = kPhoto, .allowDownscaling = false}).kind,
            DecodeSize::Kind::Original);
  // Even with `resize`: the core then resizes from every source pixel.
  EXPECT_EQ(decodeOf({.uri = kPhoto,
                      .processing = {.resize = 120},
                      .allowDownscaling = false})
                .kind,
            DecodeSize::Kind::Original);
}

TEST(ResolveDecodeSize, ResizeNamesTheWidthInPixels) {
  // 120 pt on a 3x screen; the view's size and mode no longer matter.
  EXPECT_EQ(decodeOf({.uri = kPhoto,
                      .processing = {.resize = 120, .blur = 4},
                      .pixelRatio = 3,
                      .resizeMode = ResizeMode::Center}),
            (DecodeSize{.kind = DecodeSize::Kind::Width, .width = 360, .fill = false}));
}

TEST(ResolveDecodeSize, BlurAloneNeedsTheOriginal) {
  // Its radius is in image pixels: the view's size must not change the look.
  EXPECT_EQ(decodeOf({.uri = kPhoto, .processing = {.blur = 8}}).kind,
            DecodeSize::Kind::Original);
}

TEST(ResolveDecodeSize, PerPixelProcessorsStillDecodeAtTheViewSize) {
  EXPECT_EQ(decodeOf({.uri = kPhoto,
                      .processing = {.monochrome = 0xffffffff, .tint = 0xff2060c0},
                      .resizeMode = ResizeMode::Cover}),
            (DecodeSize{.kind = DecodeSize::Kind::View, .width = 0, .fill = true}));
}

TEST(ResolveDecodeSize, AppliesToLocalSourcesToo) {
  // A camera-roll photo is where downsampling saves the most memory.
  EXPECT_EQ(decodeOf({.uri = "file:///var/mobile/Media/DCIM/IMG_0042.HEIC"}).kind,
            DecodeSize::Kind::View);
}

}  // namespace
}  // namespace turboimage
