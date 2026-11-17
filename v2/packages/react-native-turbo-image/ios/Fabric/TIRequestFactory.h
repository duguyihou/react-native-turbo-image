// Builds the loader-seam request from the C++ core's resolution.
//
// Shared by the Fabric view and the cache TurboModule so a prefetch and a
// later display resolve to the *same* cache key and tier policy. Contains
// C++ types, so it is private to the ObjC++ target and must never be
// imported from a public (Swift-visible) header.

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

// Resolves `request` with the core and converts the result for the seam.
//
// `viewPixelSize` is the size of the view the image is for, in pixels. The
// core decides whether the decode is bounded by it (`DecodeSize::Kind::View`)
// and this turns that into a concrete size. The cache module has no view
// and passes none: it also sets `allowDownscaling = false`, so the core
// never asks for one. A zero size (a view not laid out yet) decodes the
// original instead of nothing.
TIRequestResult TIMakeImageRequest(const turboimage::ImageRequest &request,
                                   CGSize viewPixelSize = CGSizeZero);

// JS sends an absent `cacheKey` as an empty string.
std::optional<std::string> TIOptionalCacheKey(const std::string &cacheKey);

NSString *_Nonnull TIStringFromStd(const std::string &s);
