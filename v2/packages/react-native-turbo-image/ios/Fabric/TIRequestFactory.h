// Builds the loader-seam request from the C++ core's resolution.
//
// Shared by the Fabric view and the cache TurboModule so a prefetch and a
// later display resolve to the *same* cache key and tier policy. Contains
// C++ types, so it is private to the ObjC++ target and must never be
// imported from a public (Swift-visible) header.

#pragma once

#import <Foundation/Foundation.h>

#include <string>

#include <turboimage/ImageRequest.h>

#import "TIImageRequest.h"

struct TIRequestResult {
  // nil when `error` is set.
  TIImageRequest *_Nullable request = nil;
  turboimage::LoadErrorCode error = turboimage::LoadErrorCode::Unknown;
  NSString *_Nullable message = nil;
};

// `processing` and `pixelRatio` feed the core's processor resolution
// (Processing.h). The cache module passes neither: prefetch/dispose address
// the original, which every processed variant is derived from.
TIRequestResult TIMakeImageRequest(const std::string &uri, const std::string &cacheKey,
                                   turboimage::CachePolicy policy,
                                   const turboimage::ProcessingOptions &processing = {},
                                   double pixelRatio = 1);

NSString *_Nonnull TIStringFromStd(const std::string &s);
