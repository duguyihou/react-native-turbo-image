#include <gtest/gtest.h>

#include <cmath>

#include "turboimage/ImageRequest.h"

namespace turboimage {
namespace {

TEST(CanonicalCacheKey, LowercasesSchemeAndHostOnly) {
  EXPECT_EQ(canonicalCacheKey("HTTPS://CDN.Example.com/Avatars/Ada.PNG?v=A"),
            "https://cdn.example.com/Avatars/Ada.PNG?v=A");
}

TEST(SameOrigin, ComparesSchemeHostAndPort) {
  EXPECT_TRUE(sameOrigin("https://cdn.example.com/a.jpg", "https://cdn.example.com/thumbs/a.jpg?w=20"));
  EXPECT_TRUE(sameOrigin("HTTPS://CDN.example.com/a.jpg", "https://cdn.EXAMPLE.com/b.jpg"));
  EXPECT_TRUE(sameOrigin("https://cdn.example.com/a.jpg", "https://cdn.example.com:443/b.jpg"));
  EXPECT_TRUE(sameOrigin("http://cdn.example.com/a.jpg", "http://cdn.example.com:80/b.jpg"));
  EXPECT_TRUE(sameOrigin("https://user:pw@cdn.example.com/a.jpg", "https://cdn.example.com/b.jpg"));
  EXPECT_TRUE(sameOrigin("http://[::1]:8765/a.jpg", "http://[::1]:8765/b.jpg"));

  EXPECT_FALSE(sameOrigin("https://api.example.com/a.jpg", "https://thumbs.cdn-vendor.com/a.jpg"));
  EXPECT_FALSE(sameOrigin("https://cdn.example.com/a.jpg", "http://cdn.example.com/a.jpg"));
  EXPECT_FALSE(sameOrigin("https://cdn.example.com/a.jpg", "https://cdn.example.com:8443/a.jpg"));
  EXPECT_FALSE(sameOrigin("http://[::1]:8765/a.jpg", "http://[::1]/a.jpg"));
  EXPECT_FALSE(sameOrigin("https://cdn.example.com.evil.test/a.jpg", "https://cdn.example.com/a.jpg"));
  EXPECT_FALSE(sameOrigin("not a uri", "not a uri"));
}

TEST(SameOrigin, EndsTheHostWhereOkHttpDoes) {
  // OkHttp ends the host at a backslash, so this connects to evil.test.
  EXPECT_FALSE(sameOrigin("https://cdn.example.com/a.jpg", "https://evil.test\\@cdn.example.com/t.jpg"));
  EXPECT_FALSE(sameOrigin("https://cdn.example.com/a.jpg", "https://evil.test\\cdn.example.com"));
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

TEST(CanonicalCacheKey, KeepsUserinfoCase) {
  // Userinfo is case-sensitive (RFC 3986 §3.2.1); only the host is not.
  EXPECT_EQ(canonicalCacheKey("HTTPS://Ada:S3cret@CDN.Example.com:8443/a.png"),
            "https://Ada:S3cret@cdn.example.com:8443/a.png");
}

TEST(CanonicalCacheKey, LowercasesAsciiOnly) {
  // Non-ASCII bytes pass through regardless of the C locale.
  EXPECT_EQ(canonicalCacheKey("https://\xC3\x89XAMPLE.com/a.png"),
            "https://\xC3\x89xample.com/a.png");
}

TEST(MemoryCacheKeyCandidates, TriesAnExplicitKeyVerbatimFirst) {
  // As given first (an explicit `cacheKey`), then canonical (a URI).
  EXPECT_EQ(memoryCacheKeyCandidates("Avatar#42"),
            (std::vector<std::string>{"Avatar#42", "Avatar"}));
  EXPECT_EQ(memoryCacheKeyCandidates("HTTPS://CDN.Example.com/a.png#thumb"),
            (std::vector<std::string>{"HTTPS://CDN.Example.com/a.png#thumb",
                                      "https://cdn.example.com/a.png"}));
}

TEST(MemoryCacheKeyCandidates, DoesNotRepeatAKeyThatIsAlreadyCanonical) {
  EXPECT_EQ(memoryCacheKeyCandidates("https://cdn.example.com/a.png"),
            (std::vector<std::string>{"https://cdn.example.com/a.png"}));
  EXPECT_EQ(memoryCacheKeyCandidates("avatar-42"), (std::vector<std::string>{"avatar-42"}));
}

TEST(MemoryCacheKeyCandidates, EmptyKeyHasNoCandidates) {
  EXPECT_TRUE(memoryCacheKeyCandidates("").empty());
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
      // Outside tab and printable ASCII, which OkHttp throws on mid-fetch:
      {"X-A", "caf\xc3\xa9"},          // UTF-8
      {"X-A", "nul\xc0\x80"},          // NUL as JNI's modified UTF-8
      {"X-A", "del\x7f"},              // DEL
      {"X-A", "bell\x07"},             // other control
  };
  for (const auto& header : invalid) {
    const auto result = resolveRequest(
        {.uri = "https://cdn.example.com/a.png", .headers = {{"Accept", "image/*"}, header}});
    EXPECT_EQ(result.error, RequestError::InvalidHeader) << header.name << ": " << header.value;
  }
}

TEST(ResolveRequestHeaders, AcceptsEveryTokenCharacterAndPrintableAsciiValues) {
  const auto result = resolveRequest(
      {.uri = "https://cdn.example.com/a.png",
       .headers = {{"!#$%&'*+-.^_`|~09azAZ", "tab\tand printable ASCII ~!@#$%^&*()"}}});
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
                                           CachePolicy::NoCache, CachePolicy::CacheOnly,
                                           CachePolicy::UrlCache));

TEST(ResolveRequestLocal, HasNoHttpCache) {
  // A local file has no HTTP response to take freshness from.
  const auto result = resolveRequest(
      {.uri = "file:///tmp/logo.png", .cachePolicy = CachePolicy::UrlCache});
  ASSERT_TRUE(result.ok());
  EXPECT_FALSE(result.request->httpCache);
}

TEST(ParseCachePolicy, AcceptsExactlyTheJsNames) {
  EXPECT_EQ(parseCachePolicy("default"), CachePolicy::Default);
  EXPECT_EQ(parseCachePolicy("memoryOnly"), CachePolicy::MemoryOnly);
  EXPECT_EQ(parseCachePolicy("noCache"), CachePolicy::NoCache);
  EXPECT_EQ(parseCachePolicy("cacheOnly"), CachePolicy::CacheOnly);
  EXPECT_EQ(parseCachePolicy("urlCache"), CachePolicy::UrlCache);
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
  EXPECT_EQ(loadErrorCodeName(LoadErrorCode::Http), "http");
}

TEST(LoadErrorCodeName, OutOfRangeIsUnknown) {
  EXPECT_EQ(loadErrorCodeName(static_cast<LoadErrorCode>(99)), "unknown");
}

// The cache-tier matrix both adapters are tested against, spelled out.
struct PolicyCase {
  CachePolicy policy;
  TierAccess memory;
  TierAccess disk;
  bool allowNetwork;
  // Whether `disk` means the HTTP cache instead of the keyed disk cache.
  bool httpCache;
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
  EXPECT_EQ(result.request->httpCache, c.httpCache);
}

INSTANTIATE_TEST_SUITE_P(
    AllPolicies, ResolveRequestPolicy,
    ::testing::Values(
        PolicyCase{CachePolicy::Default, {true, true}, {true, true}, true, false},
        PolicyCase{CachePolicy::MemoryOnly, {true, true}, {false, false}, true,
                   false},
        PolicyCase{CachePolicy::NoCache, {false, false}, {false, false}, true,
                   false},
        PolicyCase{CachePolicy::CacheOnly, {true, false}, {true, false}, false,
                   false},
        PolicyCase{CachePolicy::UrlCache, {true, true}, {true, true}, true,
                   true}));

// A prefetch writes memory only where no disk tier would keep the bytes.
// {policy, uri, memory.write}; every other field matches a view's.
struct PrefetchCase {
  CachePolicy policy;
  const char* uri;
  bool memoryWrite;
};

class ResolvePrefetch : public ::testing::TestWithParam<PrefetchCase> {};

TEST_P(ResolvePrefetch, DecodesOnlyWhenNoDiskTierWrites) {
  const auto& c = GetParam();
  const ImageRequest request{.uri = c.uri, .cachePolicy = c.policy};
  const auto view = resolveRequest(request);
  const auto prefetch = resolveRequest(request, RequestPurpose::Prefetch);
  ASSERT_TRUE(view.ok());
  ASSERT_TRUE(prefetch.ok());

  EXPECT_EQ(prefetch.request->memory.write, c.memoryWrite);
  auto expected = *view.request;
  expected.memory.write = c.memoryWrite;
  EXPECT_EQ(*prefetch.request, expected);
}

INSTANTIATE_TEST_SUITE_P(
    AllPolicies, ResolvePrefetch,
    ::testing::Values(
        PrefetchCase{CachePolicy::Default, "https://cdn.example.com/a.png", false},
        PrefetchCase{CachePolicy::UrlCache, "https://cdn.example.com/a.png", false},
        PrefetchCase{CachePolicy::MemoryOnly, "https://cdn.example.com/a.png", true},
        PrefetchCase{CachePolicy::NoCache, "https://cdn.example.com/a.png", false},
        PrefetchCase{CachePolicy::CacheOnly, "https://cdn.example.com/a.png", false},
        PrefetchCase{CachePolicy::Default, "file:///data/a.png", true}));

TEST(ResolveRequestHttpCache, KeepsTheExplicitKeyForTheMemoryTier) {
  // The HTTP cache is keyed by URL; `cacheKey` still names the memory entry.
  const auto result = resolveRequest({.uri = "https://cdn.example.com/a.png?sig=1",
                                      .cacheKey = "avatar-42",
                                      .cachePolicy = CachePolicy::UrlCache});
  ASSERT_TRUE(result.ok());
  EXPECT_TRUE(result.request->httpCache);
  EXPECT_EQ(result.request->cacheKey, "avatar-42");
  EXPECT_EQ(result.request->url, "https://cdn.example.com/a.png?sig=1");
}

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

// --- decode size of a vector source (SVG) -----------------------------------

constexpr auto kLogo = "https://cdn.example.com/brand/logo.svg";

DecodeSize vectorDecodeOf(const ImageRequest& request) {
  const auto result = resolveRequest(request);
  EXPECT_TRUE(result.ok());
  return result.request->vectorDecode;
}

TEST(ResolveVectorDecodeSize, MatchesTheBitmapTargetWhileDownscalingIsOn) {
  for (const ImageRequest& request : {
           ImageRequest{.uri = kLogo},
           ImageRequest{.uri = kLogo, .resizeMode = ResizeMode::Cover},
           ImageRequest{.uri = kLogo, .resizeMode = ResizeMode::Center},
           ImageRequest{.uri = kLogo, .processing = {.blur = 8}},
           ImageRequest{.uri = kLogo, .processing = {.resize = 120}, .pixelRatio = 3},
       }) {
    EXPECT_EQ(vectorDecodeOf(request), decodeOf(request));
  }
}

TEST(ResolveVectorDecodeSize, OptOutStillDrawsAtTheViewSize) {
  // A vector's "original" is its nominal size, usually smaller than the view.
  const ImageRequest optOut{.uri = kLogo, .allowDownscaling = false};
  EXPECT_EQ(decodeOf(optOut).kind, DecodeSize::Kind::Original);
  EXPECT_EQ(vectorDecodeOf(optOut),
            (DecodeSize{.kind = DecodeSize::Kind::View, .width = 0, .fill = false}));
}

TEST(ResolveVectorDecodeSize, OptOutKeepsTheRulesAboutTheImagesOwnSize) {
  // `center` draws 1:1 and `blur`'s radius is in image pixels, opt-out or not.
  EXPECT_EQ(vectorDecodeOf({.uri = kLogo,
                            .allowDownscaling = false,
                            .resizeMode = ResizeMode::Center})
                .kind,
            DecodeSize::Kind::Original);
  EXPECT_EQ(vectorDecodeOf({.uri = kLogo,
                            .processing = {.blur = 8},
                            .allowDownscaling = false})
                .kind,
            DecodeSize::Kind::Original);
  // `resize` names a width: draw at it, there is nothing larger to resize from.
  EXPECT_EQ(vectorDecodeOf({.uri = kLogo,
                            .processing = {.resize = 120},
                            .pixelRatio = 3,
                            .allowDownscaling = false}),
            (DecodeSize{.kind = DecodeSize::Kind::Width, .width = 360, .fill = false}));
}

// Views reload when this differs, so every load-affecting prop must count.
TEST(ImageRequestEquality, EveryFieldTakesPart) {
  const ImageRequest base{.uri = "https://example.com/a.jpg"};
  EXPECT_EQ(base, ImageRequest{.uri = "https://example.com/a.jpg"});

  auto changed = base;
  changed.uri = "https://example.com/b.jpg";
  EXPECT_NE(base, changed);
  changed = base;
  changed.cacheKey = "avatar-7";
  EXPECT_NE(base, changed);
  changed = base;
  changed.cachePolicy = CachePolicy::CacheOnly;
  EXPECT_NE(base, changed);
  changed = base;
  changed.processing.blur = 4;
  EXPECT_NE(base, changed);
  changed = base;
  changed.pixelRatio = 3;
  EXPECT_NE(base, changed);
  changed = base;
  changed.headers = {{.name = "Authorization", .value = "Bearer token"}};
  EXPECT_NE(base, changed);
  changed = base;
  changed.allowDownscaling = false;
  EXPECT_NE(base, changed);
  changed = base;
  changed.resizeMode = ResizeMode::Cover;
  EXPECT_NE(base, changed);
}

// needsLargerDecode: when a view has grown past its image.

TEST(NeedsLargerDecode, NotUntilTheViewWouldScaleTheImageUpByHalf) {
  // 300x200 decoded for a 300x200 view (fit).
  const PixelSize decoded{300, 200};
  EXPECT_FALSE(needsLargerDecode(decoded, {300, 200}, {300, 200}, false));
  EXPECT_FALSE(needsLargerDecode(decoded, {300, 200}, {450, 300}, false));  // exactly 1.5x
  EXPECT_TRUE(needsLargerDecode(decoded, {300, 200}, {600, 400}, false));
}

TEST(NeedsLargerDecode, FitFollowsTheSideThatBinds) {
  // A 3:2 image fitting a view that only grows taller is not drawn larger.
  EXPECT_FALSE(needsLargerDecode({300, 200}, {300, 200}, {300, 900}, false));
  // Fill covers the view, so the taller view needs more pixels.
  EXPECT_TRUE(needsLargerDecode({450, 300}, {300, 300}, {300, 900}, true));
}

TEST(NeedsLargerDecode, NeverForASourceAlreadyAtItsOwnSize) {
  // 100x50 for a 300x200 view: capped by the source, so reloading gains nothing.
  EXPECT_FALSE(needsLargerDecode({100, 50}, {300, 200}, {900, 600}, false));
  // Fill: covering 300x300 needed 450x300; it came out 200x100.
  EXPECT_FALSE(needsLargerDecode({200, 100}, {300, 300}, {900, 900}, true));
}

TEST(NeedsLargerDecode, ToleratesTheDecodersRounding) {
  // One pixel short of the view is still a decode bounded by it.
  EXPECT_TRUE(needsLargerDecode({299, 199}, {300, 200}, {600, 400}, false));
}

TEST(NeedsLargerDecode, UnknownSizesNeverReload) {
  const PixelSize nothing{0, 0};
  const PixelSize nan{std::nan(""), 10};
  EXPECT_FALSE(needsLargerDecode(nothing, {300, 200}, {900, 600}, false));
  EXPECT_FALSE(needsLargerDecode({300, 200}, nothing, {900, 600}, false));
  EXPECT_FALSE(needsLargerDecode({300, 200}, {300, 200}, nothing, false));
  EXPECT_FALSE(needsLargerDecode(nan, {300, 200}, {900, 600}, false));
}

// placeImage: where a view draws its image.

// A 200x100 box and a square image, so every mode leaves space or overflow.
constexpr PixelSize kBox{200, 100};
constexpr ContentPosition kCentre{};
constexpr ContentPosition kTopLeft{.x = 0, .y = 0};
constexpr ContentPosition kBottomRight{.x = 1, .y = 1};

TEST(PlaceImage, CoverOverflowsAndPositionChoosesTheCrop) {
  // 50x50 scaled by 4 to cover: 200x200, 100 too tall.
  EXPECT_EQ(placeImage({50, 50}, kBox, ResizeMode::Cover, kCentre), (PlacedRect{0, -50, 200, 200}));
  EXPECT_EQ(placeImage({50, 50}, kBox, ResizeMode::Cover, kTopLeft), (PlacedRect{0, 0, 200, 200}));
  EXPECT_EQ(placeImage({50, 50}, kBox, ResizeMode::Cover, kBottomRight),
            (PlacedRect{0, -100, 200, 200}));
}

TEST(PlaceImage, ContainLeavesSpaceThatPositionDistributes) {
  EXPECT_EQ(placeImage({50, 50}, kBox, ResizeMode::Contain, kCentre), (PlacedRect{50, 0, 100, 100}));
  EXPECT_EQ(placeImage({50, 50}, kBox, ResizeMode::Contain, kTopLeft), (PlacedRect{0, 0, 100, 100}));
  EXPECT_EQ(placeImage({50, 50}, kBox, ResizeMode::Contain, {.x = 0.25, .y = 0.5}),
            (PlacedRect{25, 0, 100, 100}));
}

TEST(PlaceImage, CenterKeepsTheImagesOwnSize) {
  EXPECT_EQ(placeImage({50, 50}, kBox, ResizeMode::Center, kCentre), (PlacedRect{75, 25, 50, 50}));
  EXPECT_EQ(placeImage({50, 50}, kBox, ResizeMode::Center, kBottomRight),
            (PlacedRect{150, 50, 50, 50}));
  // Larger than the box: overflows, as UIViewContentModeCenter does.
  EXPECT_EQ(placeImage({400, 400}, kBox, ResizeMode::Center, kCentre),
            (PlacedRect{-100, -150, 400, 400}));
}

TEST(PlaceImage, ScaleDownIsCenterWhenItFitsAndContainWhenNot) {
  EXPECT_EQ(placeImage({50, 50}, kBox, ResizeMode::ScaleDown, kCentre), (PlacedRect{75, 25, 50, 50}));
  EXPECT_EQ(placeImage({400, 400}, kBox, ResizeMode::ScaleDown, kCentre),
            (PlacedRect{50, 0, 100, 100}));
  EXPECT_EQ(placeImage({400, 400}, kBox, ResizeMode::ScaleDown, kTopLeft),
            (PlacedRect{0, 0, 100, 100}));
}

TEST(PlaceImage, StretchAndUnknownSizesFillTheBox) {
  const PlacedRect whole{0, 0, 200, 100};
  EXPECT_EQ(placeImage({50, 50}, kBox, ResizeMode::Stretch, kTopLeft), whole);
  EXPECT_EQ(placeImage({0, 0}, kBox, ResizeMode::Cover, kTopLeft), whole);
  EXPECT_EQ(placeImage({std::nan(""), 5}, kBox, ResizeMode::Contain, kCentre), whole);
}

TEST(PlaceImage, PositionIsClampedAndNanCentres) {
  EXPECT_EQ(placeImage({50, 50}, kBox, ResizeMode::Contain, {.x = -3, .y = 9}),
            placeImage({50, 50}, kBox, ResizeMode::Contain, {.x = 0, .y = 1}));
  EXPECT_EQ(placeImage({50, 50}, kBox, ResizeMode::Contain, {.x = std::nan(""), .y = 0.5}),
            placeImage({50, 50}, kBox, ResizeMode::Contain, kCentre));
}

TEST(ResolveDecodeSize, ScaleDownFitsLikeContain) {
  // It never draws the image larger than contain would, so it needs no more.
  const auto resolved = resolveRequest({.uri = "https://cdn.example.com/a.jpg",
                                        .resizeMode = ResizeMode::ScaleDown});
  ASSERT_TRUE(resolved.ok());
  EXPECT_EQ(resolved.request->decode, (DecodeSize{.kind = DecodeSize::Kind::View, .width = 0, .fill = false}));
}

}  // namespace
}  // namespace turboimage
