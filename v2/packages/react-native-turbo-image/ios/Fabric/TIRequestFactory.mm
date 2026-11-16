#import "TIRequestFactory.h"

#include <optional>

NSString *TIStringFromStd(const std::string &s) {
  return [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding]
             ?: @"";
}

TIRequestResult TIMakeImageRequest(const std::string &uri, const std::string &cacheKey,
                                   turboimage::CachePolicy policy) {
  const auto result = turboimage::resolveRequest({
      .uri = uri,
      .cacheKey = cacheKey.empty() ? std::nullopt : std::optional<std::string>(cacheKey),
      .cachePolicy = policy,
  });
  if (!result.ok()) {
    return {.request = nil,
            .error = turboimage::LoadErrorCode::InvalidRequest,
            .message = [NSString stringWithFormat:@"Invalid request (core error %d)",
                                                  static_cast<int>(result.error)]};
  }

  const auto &resolved = *result.request;
  NSURL *url = [NSURL URLWithString:TIStringFromStd(resolved.url)];
  if (url == nil) {
    return {.request = nil,
            .error = turboimage::LoadErrorCode::InvalidRequest,
            .message = @"Invalid URL"};
  }

  TIImageRequest *request = [[TIImageRequest alloc] initWithURL:url
                                                       cacheKey:TIStringFromStd(resolved.cacheKey)
                                                memoryCacheRead:resolved.memory.read
                                               memoryCacheWrite:resolved.memory.write
                                                  diskCacheRead:resolved.disk.read
                                                 diskCacheWrite:resolved.disk.write
                                                   allowNetwork:resolved.allowNetwork];
  return {.request = request, .error = turboimage::LoadErrorCode::Unknown, .message = nil};
}
