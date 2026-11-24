#include <gtest/gtest.h>

#include <cmath>

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

TEST(CanonicalCacheKey, KeepsUserinfoCase) {
  // Userinfo is case-sensitive (RFC 3986 §3.2.1); only the host is not.
  EXPECT_EQ(canonicalCacheKey("HTTPS://Ada:S3cret@CDN.Example.com:8443/a.png"),
            "https://Ada:S3cret@cdn.example.com:8443/a.png");
}

TEST(CanonicalCacheKey, LowercasesAsciiOnly) {
  // Bytes above 0x7F (here UTF-8 "É") must pass through whatever the C
  // locale is; `std::tolower` would map some of them in a Latin-1 locale.
  EXPECT_EQ(canonicalCacheKey("https://\xC3\x89XAMPLE.com/a.png"),
            "https://\xC3\x89xample.com/a.png");
}

TEST(MemoryCacheKeyCandidates, TriesAnExplicitKeyVerbatimFirst) {
  // `source.cacheKey` is stored as given, so a key with a '#' or a
  // scheme-like prefix must be looked up as given, before the form a URI
  // source would have been stored under.
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
  // A bitmap's original is every pixel it has. A vector's would be its own
  // nominal size, smaller than the view more often than not.
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

// The views start a new load when this comparison says the request changed,
// so every prop that affects a load must take part in it.
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
  // 100x50 decoded for a 300x200 view: it stopped short of the view, so it
  // is the whole source, and another decode would give the same pixels.
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

// chooseSource / largerSourceFor: one image offered at several sizes.

// A typical set: thumbnail, screen-sized and full-sized, 3:2.
const std::vector<PixelSize> kSet{{300, 200}, {1200, 800}, {3000, 2000}};

TEST(ChooseSource, TheSmallestThatTheViewDoesNotScaleUp) {
  EXPECT_EQ(chooseSource(kSet, {300, 200}, ResizeMode::Contain, true), 0u);
  // Contain is bound by the side that fits first: 301x200 draws a 3:2
  // image 300x200, so the thumbnail is still enough; 301x201 is not.
  EXPECT_EQ(chooseSource(kSet, {301, 200}, ResizeMode::Contain, true), 0u);
  EXPECT_EQ(chooseSource(kSet, {301, 201}, ResizeMode::Contain, true), 1u);
  EXPECT_EQ(chooseSource(kSet, {1200, 800}, ResizeMode::Contain, true), 1u);
  EXPECT_EQ(chooseSource(kSet, {2000, 1000}, ResizeMode::Contain, true), 2u);
}

TEST(ChooseSource, OrderDoesNotMatterButTiesGoFirst) {
  const std::vector<PixelSize> shuffled{{3000, 2000}, {300, 200}, {1200, 800}};
  EXPECT_EQ(chooseSource(shuffled, {600, 400}, ResizeMode::Contain, true), 2u);
  const std::vector<PixelSize> twins{{900, 600}, {900, 600}};
  EXPECT_EQ(chooseSource(twins, {600, 400}, ResizeMode::Contain, true), 0u);
}

TEST(ChooseSource, CoverNeedsTheViewCoveredContainOnlyFitted) {
  // A tall 300x900 view: fitting a 3:2 image takes 300 wide, covering it
  // takes 900 tall, so 1350 wide.
  EXPECT_EQ(chooseSource(kSet, {300, 900}, ResizeMode::Contain, true), 0u);
  EXPECT_EQ(chooseSource(kSet, {300, 900}, ResizeMode::Cover, true), 2u);
  EXPECT_EQ(chooseSource(kSet, {300, 900}, ResizeMode::Stretch, true), 2u);
}

TEST(ChooseSource, TheLargestWhenNoneIsLargeEnough) {
  EXPECT_EQ(chooseSource(kSet, {6000, 4000}, ResizeMode::Contain, true), 2u);
}

TEST(ChooseSource, TheLargestWhenTheViewNeedsItsOwnSizeOrIsUnknown) {
  EXPECT_EQ(chooseSource(kSet, {300, 200}, ResizeMode::Center, true), 2u);
  EXPECT_EQ(chooseSource(kSet, {300, 200}, ResizeMode::Contain, false), 2u);
  EXPECT_EQ(chooseSource(kSet, {0, 0}, ResizeMode::Contain, true), 2u);
  EXPECT_EQ(chooseSource(kSet, {std::nan(""), 200}, ResizeMode::Contain, true), 2u);
}

TEST(ChooseSource, CandidatesOfUnknownSizeAreNeverPreferred) {
  const std::vector<PixelSize> partial{{0, 0}, {1200, 800}, {std::nan(""), 5}};
  EXPECT_EQ(chooseSource(partial, {300, 200}, ResizeMode::Contain, true), 1u);
  EXPECT_EQ(chooseSource(std::vector<PixelSize>{{0, 0}, {0, 0}}, {300, 200},
                         ResizeMode::Contain, true),
            0u);
  EXPECT_EQ(chooseSource({}, {300, 200}, ResizeMode::Contain, true), 0u);
}

TEST(LargerSourceFor, OnlyWhenTheChoiceGrows) {
  // Showing the thumbnail in a view that grew to 600x400: the next size up.
  EXPECT_EQ(largerSourceFor(kSet, 0, {600, 400}, ResizeMode::Contain, true), 1u);
  // Still within the thumbnail: no switch.
  EXPECT_EQ(largerSourceFor(kSet, 0, {300, 200}, ResizeMode::Contain, true), std::nullopt);
  // Never down: the full size stays when the view shrinks.
  EXPECT_EQ(largerSourceFor(kSet, 2, {300, 200}, ResizeMode::Contain, true), std::nullopt);
  // Out of range (props changed under it): nothing.
  EXPECT_EQ(largerSourceFor(kSet, 7, {600, 400}, ResizeMode::Contain, true), std::nullopt);
}

}  // namespace
}  // namespace turboimage
