#include "turboimage/ImageRequest.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>

namespace turboimage {

namespace {

// Remote sources: fetched over the network, cached in memory and on disk.
constexpr std::array<std::string_view, 2> kRemoteSchemes = {"http", "https"};

// Local sources (RFC §4.1). Always readable (even under `cacheOnly`) and
// never disk-cached. Android-only schemes on iOS fail in the loader.
constexpr std::array<std::string_view, 3> kLocalSchemes = {"file", "content",
                                                           "android.resource"};

template <std::size_t N>
bool contains(const std::array<std::string_view, N>& schemes,
              std::string_view scheme) {
  return std::find(schemes.begin(), schemes.end(), scheme) != schemes.end();
}

// Not `std::tolower`: it is locale-dependent and can rewrite UTF-8 bytes.
char toLowerAscii(char c) {
  return c >= 'A' && c <= 'Z' ? static_cast<char>(c - 'A' + 'a') : c;
}

std::string lowerAscii(std::string_view s) {
  std::string out(s);
  std::transform(out.begin(), out.end(), out.begin(), toLowerAscii);
  return out;
}

// RFC 9110 §5.6.2 `tchar`.
bool isTokenChar(char c) {
  if ((c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')) {
    return true;
  }
  return std::string_view("!#$%&'*+-.^_`|~").find(c) != std::string_view::npos;
}

bool isValidHeader(const Header& header) {
  if (header.name.empty() ||
      !std::all_of(header.name.begin(), header.name.end(), isTokenChar)) {
    return false;
  }
  // Tab and printable ASCII only. That rejects CR and LF (header
  // injection) and NUL (truncates C strings), and matches what OkHttp
  // accepts, so a value fails here on both platforms instead of throwing
  // inside Android's fetch. It also catches a NUL that JNI hands over in
  // modified UTF-8 (C0 80).
  return std::all_of(header.value.begin(), header.value.end(), [](char c) {
    const auto byte = static_cast<unsigned char>(c);
    return byte == '\t' || (byte >= 0x20 && byte <= 0x7e);
  });
}

// The decode target, first match wins:
//   1. `allowDownscaling` off: original (skipped for vectors, `!hasPixels`).
//   2. `resize`: that width.
//   3. `blur`: original, since its radius is in image pixels.
//   4. `center`: original, since it draws 1:1.
//   5. Otherwise the view's size.
DecodeSize resolveDecodeSize(const ImageRequest& request,
                             const ProcessingSpec& processing,
                             bool hasPixels) {
  const DecodeSize original{
      .kind = DecodeSize::Kind::Original, .width = 0, .fill = false};
  if (hasPixels && !request.allowDownscaling) {
    return original;
  }
  if (processing.resizeWidth > 0) {
    return {.kind = DecodeSize::Kind::Width,
            .width = processing.resizeWidth,
            .fill = false};
  }
  if (processing.blurRadius > 0 || request.resizeMode == ResizeMode::Center) {
    return original;
  }
  // Contain and scale-down fit inside the view; cover and stretch cover it.
  return {.kind = DecodeSize::Kind::View,
          .width = 0,
          .fill = request.resizeMode == ResizeMode::Cover ||
                  request.resizeMode == ResizeMode::Stretch};
}

}  // namespace

std::string canonicalCacheKey(std::string_view uri) {
  // The fragment never reaches the server.
  if (const auto hash = uri.find('#'); hash != std::string_view::npos) {
    uri = uri.substr(0, hash);
  }

  // No "scheme://": nothing to normalise.
  const auto schemeEnd = uri.find("://");
  if (schemeEnd == std::string_view::npos) {
    return std::string(uri);
  }

  const auto authorityStart = schemeEnd + 3;
  auto authorityEnd = uri.find_first_of("/?", authorityStart);
  if (authorityEnd == std::string_view::npos) {
    authorityEnd = uri.size();
  }

  // Userinfo is case-sensitive. Split at the last '@', since a password
  // may hold an unencoded one.
  const auto authority = uri.substr(authorityStart, authorityEnd - authorityStart);
  const auto at = authority.rfind('@');
  const auto hostStart =
      at == std::string_view::npos ? authorityStart : authorityStart + at + 1;

  std::string key;
  key.reserve(uri.size());
  key += lowerAscii(uri.substr(0, authorityStart));          // scheme://
  key += uri.substr(authorityStart, hostStart - authorityStart);  // userinfo@
  key += lowerAscii(uri.substr(hostStart, authorityEnd - hostStart));  // host:port
  key += uri.substr(authorityEnd);
  return key;
}

namespace {

// "scheme://host:port", lower-case, with the default port made explicit;
// empty when `uri` has no "scheme://".
std::string originOf(std::string_view uri) {
  const auto schemeEnd = uri.find("://");
  if (schemeEnd == std::string_view::npos) {
    return {};
  }
  const auto authorityStart = schemeEnd + 3;
  auto authorityEnd = uri.find_first_of("/?#", authorityStart);
  if (authorityEnd == std::string_view::npos) {
    authorityEnd = uri.size();
  }
  auto hostPort = uri.substr(authorityStart, authorityEnd - authorityStart);
  if (const auto at = hostPort.rfind('@'); at != std::string_view::npos) {
    hostPort = hostPort.substr(at + 1);
  }
  const std::string scheme = lowerAscii(uri.substr(0, schemeEnd));
  std::string origin = scheme + "://" + lowerAscii(hostPort);
  // A ':' after the last ']' is a port; an IPv6 literal holds colons too.
  const auto bracket = hostPort.rfind(']');
  const auto colon = hostPort.rfind(':');
  const bool hasPort = colon != std::string_view::npos &&
                       (bracket == std::string_view::npos || colon > bracket);
  if (!hasPort) {
    if (scheme == "http") {
      origin += ":80";
    } else if (scheme == "https") {
      origin += ":443";
    }
  }
  return origin;
}

}  // namespace

bool sameOrigin(std::string_view a, std::string_view b) {
  const auto origin = originOf(a);
  return !origin.empty() && origin == originOf(b);
}

std::vector<std::string> memoryCacheKeyCandidates(std::string_view key) {
  if (key.empty()) {
    return {};
  }
  std::vector<std::string> candidates{std::string(key)};
  if (auto canonical = canonicalCacheKey(key); canonical != candidates.front()) {
    candidates.push_back(std::move(canonical));
  }
  return candidates;
}

ResolveResult resolveRequest(const ImageRequest& request) {
  if (request.uri.empty()) {
    return {.request = std::nullopt, .error = RequestError::EmptyUri};
  }

  const auto schemeEnd = request.uri.find("://");
  const auto scheme = schemeEnd == std::string::npos
                          ? std::string{}
                          : lowerAscii(std::string_view(request.uri).substr(
                                0, schemeEnd));
  const bool isLocal = contains(kLocalSchemes, scheme);
  if (!isLocal && !contains(kRemoteSchemes, scheme)) {
    return {.request = std::nullopt, .error = RequestError::UnsupportedScheme};
  }
  if (!std::all_of(request.headers.begin(), request.headers.end(),
                   isValidHeader)) {
    return {.request = std::nullopt, .error = RequestError::InvalidHeader};
  }

  const ProcessingSpec processing =
      resolveProcessing(request.processing, request.pixelRatio);

  // All fields spelled out for NDK clang's -Wmissing-field-initializers.
  ResolvedRequest resolved{
      .url = request.uri,
      .cacheKey = request.cacheKey.value_or(canonicalCacheKey(request.uri)),
      .processorKey = processorKey(processing),
      .headers = request.headers,
      .memory = {.read = true, .write = true},
      .disk = {.read = true, .write = true},
      .allowNetwork = true,
      .httpCache = false,
      .decode = resolveDecodeSize(request, processing, /*hasPixels=*/true),
      .vectorDecode =
          resolveDecodeSize(request, processing, /*hasPixels=*/false),
  };

  // Exhaustive (no `default:`) so a new policy fails to compile until handled.
  switch (request.cachePolicy) {
    case CachePolicy::Default:
      break;
    case CachePolicy::MemoryOnly:
      resolved.disk = {.read = false, .write = false};
      break;
    case CachePolicy::NoCache:
      resolved.memory = {.read = false, .write = false};
      resolved.disk = {.read = false, .write = false};
      break;
    case CachePolicy::CacheOnly:
      resolved.allowNetwork = false;
      // No write-back: pointless, and Coil would re-encode the disk entry.
      resolved.memory.write = false;
      resolved.disk.write = false;
      break;
    case CachePolicy::UrlCache:
      resolved.httpCache = true;
      break;
  }
  // Local sources: the policy governs memory only; no disk, no HTTP cache.
  if (isLocal) {
    resolved.disk = {.read = false, .write = false};
    resolved.allowNetwork = true;
    resolved.httpCache = false;
  }

  return {.request = std::move(resolved), .error = RequestError::None};
}

std::optional<CachePolicy> parseCachePolicy(std::string_view js) {
  if (js == "default") return CachePolicy::Default;
  if (js == "memoryOnly") return CachePolicy::MemoryOnly;
  if (js == "noCache") return CachePolicy::NoCache;
  if (js == "cacheOnly") return CachePolicy::CacheOnly;
  if (js == "urlCache") return CachePolicy::UrlCache;
  return std::nullopt;
}

std::string_view loadErrorCodeName(LoadErrorCode code) {
  // Exhaustive (no `default:`) so a new code must get a name.
  switch (code) {
    case LoadErrorCode::Unknown:
      return "unknown";
    case LoadErrorCode::InvalidRequest:
      return "invalidRequest";
    case LoadErrorCode::NotCached:
      return "notCached";
    case LoadErrorCode::Network:
      return "network";
    case LoadErrorCode::Decode:
      return "decode";
    case LoadErrorCode::Http:
      return "http";
  }
  // Out-of-range values can arrive across the JNI/ObjC boundary.
  return "unknown";
}

std::string_view coreVersion() { return "2.0.0-alpha.0"; }

bool needsLargerDecode(PixelSize decoded, PixelSize loadedFor, PixelSize now, bool fill) {
  // Also false for NaN.
  const auto positive = [](PixelSize size) { return size.width > 0 && size.height > 0; };
  if (!positive(decoded) || !positive(loadedFor) || !positive(now)) {
    return false;
  }

  // A decode smaller than its view was capped by the source, so reloading
  // gains nothing. One pixel of slack for decoder rounding.
  constexpr double kRoundingSlack = 1;
  const bool shortOfWidth = loadedFor.width > decoded.width + kRoundingSlack;
  const bool shortOfHeight = loadedFor.height > decoded.height + kRoundingSlack;
  const bool cappedBySource = fill ? (shortOfWidth || shortOfHeight) : (shortOfWidth && shortOfHeight);
  if (cappedBySource) {
    return false;
  }

  // Upscale now: fill takes the larger scale, fit the smaller.
  const double horizontal = now.width / decoded.width;
  const double vertical = now.height / decoded.height;
  const double upscale = fill ? std::max(horizontal, vertical) : std::min(horizontal, vertical);
  constexpr double kUpgradeRatio = 1.5;
  return upscale > kUpgradeRatio;
}

namespace {

bool isKnown(PixelSize size) {
  // false for NaN too.
  return size.width > 0 && size.height > 0 && std::isfinite(size.width) &&
         std::isfinite(size.height);
}

}  // namespace

PlacedRect placeImage(PixelSize image, PixelSize box, ResizeMode resizeMode,
                      ContentPosition position) {
  const PlacedRect whole{.x = 0, .y = 0, .width = box.width, .height = box.height};
  if (!isKnown(image) || !isKnown(box) || resizeMode == ResizeMode::Stretch) {
    return whole;
  }
  const double fit = std::min(box.width / image.width, box.height / image.height);
  double scale = 1;
  switch (resizeMode) {
    case ResizeMode::Cover:
      scale = std::max(box.width / image.width, box.height / image.height);
      break;
    case ResizeMode::Contain:
      scale = fit;
      break;
    case ResizeMode::ScaleDown:
      scale = std::min(1.0, fit);
      break;
    case ResizeMode::Center:
    case ResizeMode::Stretch:
      break;
  }
  const double width = image.width * scale;
  const double height = image.height * scale;
  // NaN clamps to the centre, not to an edge.
  const auto fraction = [](double value) {
    return std::isfinite(value) ? std::clamp(value, 0.0, 1.0) : 0.5;
  };
  return {.x = (box.width - width) * fraction(position.x),
          .y = (box.height - height) * fraction(position.y),
          .width = width,
          .height = height};
}

}  // namespace turboimage
