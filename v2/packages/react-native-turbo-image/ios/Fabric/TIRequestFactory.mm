#import "TIRequestFactory.h"

#include <cmath>
#include <exception>
#include <memory>
#include <optional>
#include <vector>

#include <turboimage/Processing.h>

namespace {

// UIImage -> premultiplied RGBA8 -> core -> UIImage. Drawing through UIKit
// bakes in the EXIF orientation, so the core always sees upright pixels; the
// result keeps the input's scale so its size in points is unchanged (unless
// `resize` changed it on purpose).
//
// May throw: the pixel buffer and the core's working copies are plain C++
// allocations. Callers go through TIProcessImage below.
UIImage *TIProcessImageUnguarded(UIImage *image, const std::string &key) {
  // Processors apply to still images. An animated image is processed as its
  // first frame and becomes static, which is also what Coil does with
  // transformations on Android (and what 1.x Android did).
  // TODO: process every frame, on both platforms.
  if (image.images.count > 0) {
    image = image.images.firstObject;
  }
  const CGFloat scale = image.scale > 0 ? image.scale : 1;
  const auto width = static_cast<int>(std::lround(image.size.width * scale));
  const auto height = static_cast<int>(std::lround(image.size.height * scale));
  if (width <= 0 || height <= 0) {
    return nil;
  }

  turboimage::RgbaImage rgba{
      .width = width,
      .height = height,
      .pixels = std::vector<std::uint8_t>(static_cast<std::size_t>(width) * height * 4)};
  // Owned by a guard, not released by hand: `processImage` below can throw
  // while this is still needed for the result.
  const std::unique_ptr<CGColorSpace, void (*)(CGColorSpaceRef)> colorSpaceOwner(
      CGColorSpaceCreateWithName(kCGColorSpaceSRGB), CGColorSpaceRelease);
  CGColorSpaceRef colorSpace = colorSpaceOwner.get();
  CGContextRef context = CGBitmapContextCreate(
      rgba.pixels.data(), width, height, 8, static_cast<size_t>(width) * 4, colorSpace,
      kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
  if (context == nullptr) {
    return nil;
  }
  // UIKit draws top-down; CG contexts are bottom-up.
  CGContextTranslateCTM(context, 0, height);
  CGContextScaleCTM(context, 1, -1);
  UIGraphicsPushContext(context);
  [image drawInRect:CGRectMake(0, 0, width, height)];
  UIGraphicsPopContext();
  CGContextRelease(context);

  const auto processed = turboimage::processImage(std::move(rgba), key);
  if (!processed) {
    return nil;
  }
  NSData *data = [NSData dataWithBytes:processed->pixels.data() length:processed->pixels.size()];
  CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
  CGImageRef cgImage = CGImageCreate(
      static_cast<size_t>(processed->width), static_cast<size_t>(processed->height), 8, 32,
      static_cast<size_t>(processed->width) * 4, colorSpace,
      kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast, provider, nullptr, true,
      kCGRenderingIntentDefault);
  UIImage *result = cgImage ? [UIImage imageWithCGImage:cgImage
                                                  scale:scale
                                            orientation:UIImageOrientationUp]
                            : nil;
  CGImageRelease(cgImage);
  CGDataProviderRelease(provider);
  return result;
}

// The exception barrier for processing. This runs inside a block on the
// loader's processing queue, and a C++ exception that leaves a block
// terminates the app. Processing a large image needs several copies of it,
// so running out of memory here is a failed load (nil: the loader reports a
// processing failure), not a crash.
UIImage *TIProcessImage(UIImage *image, const std::string &key) {
  try {
    return TIProcessImageUnguarded(image, key);
  } catch (const std::exception &e) {
    NSLog(@"TurboImage: processing failed: %s", e.what());
    return nil;
  } catch (...) {
    NSLog(@"TurboImage: processing failed with an unknown C++ exception");
    return nil;
  }
}

}  // namespace

NSString *TIStringFromStd(const std::string &s) {
  return [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding]
             ?: @"";
}

std::optional<std::string> TIOptionalCacheKey(const std::string &cacheKey) {
  return cacheKey.empty() ? std::nullopt : std::optional<std::string>(cacheKey);
}

namespace {

// The core's decode target as the seam's pixel bound (TIImageRequest.h).
CGSize TIDecodeSize(const turboimage::DecodeSize &decode, CGSize viewPixelSize) {
  switch (decode.kind) {
    case turboimage::DecodeSize::Kind::Original:
      return CGSizeZero;
    case turboimage::DecodeSize::Kind::Width:
      return CGSizeMake(decode.width, 0);
    case turboimage::DecodeSize::Kind::View:
      // Rounded up, so a fractional layout never decodes a pixel short. A
      // view with no area yet has nothing to bound the decode with.
      return viewPixelSize.width > 0 && viewPixelSize.height > 0
                 ? CGSizeMake(std::ceil(viewPixelSize.width), std::ceil(viewPixelSize.height))
                 : CGSizeZero;
  }
  return CGSizeZero;
}

}  // namespace

TIRequestResult TIMakeImageRequest(const turboimage::ImageRequest &imageRequest,
                                   CGSize viewPixelSize) {
  const auto result = turboimage::resolveRequest(imageRequest);
  if (!result.ok()) {
    return {.request = nil,
            .error = turboimage::LoadErrorCode::InvalidRequest,
            .message = result.error == turboimage::RequestError::InvalidHeader
                           ? @"Invalid header: names must be HTTP tokens and values must not "
                             @"contain CR, LF or NUL"
                           : [NSString stringWithFormat:@"Invalid request (core error %d)",
                                                        static_cast<int>(result.error)]};
  }

  const auto &resolved = *result.request;
  NSURL *url = [NSURL URLWithString:TIStringFromStd(resolved.url)];
  if (url == nil) {
    return {.request = nil,
            .error = turboimage::LoadErrorCode::InvalidRequest,
            .message = @"Invalid URL"};
  }

  // The block owns a copy of the key: it outlives this call and runs on the
  // loader's processing queue.
  TIImageProcessor processor = nil;
  if (!resolved.processorKey.empty()) {
    const std::string key = resolved.processorKey;
    processor = ^UIImage *(UIImage *image) {
      return TIProcessImage(image, key);
    };
  }

  NSMutableArray<NSArray<NSString *> *> *headerPairs =
      [NSMutableArray arrayWithCapacity:resolved.headers.size()];
  for (const auto &header : resolved.headers) {
    [headerPairs addObject:@[ TIStringFromStd(header.name), TIStringFromStd(header.value) ]];
  }

  TIImageRequest *request = [[TIImageRequest alloc] initWithURL:url
                                                       cacheKey:TIStringFromStd(resolved.cacheKey)
                                                memoryCacheRead:resolved.memory.read
                                               memoryCacheWrite:resolved.memory.write
                                                  diskCacheRead:resolved.disk.read
                                                 diskCacheWrite:resolved.disk.write
                                                   allowNetwork:resolved.allowNetwork
                                                   processorKey:TIStringFromStd(resolved.processorKey)
                                                      processor:processor
                                                        headers:headerPairs
                                                      httpCache:resolved.httpCache
                                                     decodeSize:TIDecodeSize(resolved.decode,
                                                                             viewPixelSize)
                                                     decodeFill:resolved.decode.fill
                                               vectorDecodeSize:TIDecodeSize(resolved.vectorDecode,
                                                                             viewPixelSize)
                                               vectorDecodeFill:resolved.vectorDecode.fill
                                                   displayScale:imageRequest.pixelRatio];
  return {.request = request, .error = turboimage::LoadErrorCode::Unknown, .message = nil};
}
