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

}  // namespace
}  // namespace turboimage
