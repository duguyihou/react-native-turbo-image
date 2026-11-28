// Builds the seam request from the core's resolution. Shared by the view and
// the cache module so prefetch and display get the same cache key. Has C++
// types: never import it from a public header.

#pragma once

#import <Foundation/Foundation.h>

#include <optional>
#include <string>
#include <vector>

#include <turboimage/ImageRequest.h>

#import "TIImageRequest.h"

struct TIRequestResult {
  // nil when `error` is set.
  TIImageRequest *_Nullable request = nil;
  turboimage::LoadErrorCode error = turboimage::LoadErrorCode::Unknown;
  NSString *_Nullable message = nil;
};

// Resolves `request` with the core and converts it for the seam.
// `viewPixelSize` bounds the decode when the core asks for it; zero (no
// layout yet, or the cache module) decodes the original.
TIRequestResult TIMakeImageRequest(const turboimage::ImageRequest &request,
                                   CGSize viewPixelSize = CGSizeZero);

// JS sends an absent `cacheKey` as an empty string.
std::optional<std::string> TIOptionalCacheKey(const std::string &cacheKey);

NSString *_Nonnull TIStringFromStd(const std::string &s);

// An adapter's error as the core's code; another domain is an adapter bug,
// so `Unknown`.
turboimage::LoadErrorCode TICoreErrorCode(NSError *_Nonnull error);
