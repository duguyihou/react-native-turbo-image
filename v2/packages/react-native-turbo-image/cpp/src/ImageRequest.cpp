#include "turboimage/ImageRequest.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>

namespace turboimage {

namespace {

// Remote sources: fetched over the network, cached in memory and on disk.
constexpr std::array<std::string_view, 2> kRemoteSchemes = {"http", "https"};

// Local sources (RFC §4.1): `file` (iOS bundled `require()` assets in
// release builds, documents, photos), and Android's `content` (pickers,
// MediaStore) and `android.resource` (release `require()` assets, resolved
// from resource names by the Android view). They are always readable,
// because reading one is not a network request, so `cacheOnly` still loads
// them; and they never touch the disk tier, because copying a local file
// into the cache only costs space. The core does not know the platform: an
// Android-only scheme on iOS gets past here and fails in the loader.
constexpr std::array<std::string_view, 3> kLocalSchemes = {"file", "content",
                                                           "android.resource"};

template <std::size_t N>
bool contains(const std::array<std::string_view, N>& schemes,
              std::string_view scheme) {
  return std::find(schemes.begin(), schemes.end(), scheme) != schemes.end();
}

// Not `std::tolower`: that follows the C locale, and an app that sets a
// Latin-1 locale would have bytes above 0x7F (half of a UTF-8 character)
// rewritten, on one platform and not the other.
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
  // Field values may hold any octet except the ones that end a line (or a C
  // string on the way into the platform HTTP stacks).
  return header.value.find_first_of(std::string_view("\r\n\0", 3)) ==
         std::string::npos;
}

// The decode target, in order of precedence. Each rule exists because the
// one below it would change what the app asked for:
//   1. `allowDownscaling` off: the app wants every pixel.
//   2. `resize`: the app named the width it wants; nothing larger is needed,
//      whatever the view's size.
//   3. `blur` without `resize`: its radius is in pixels of the image, so the
//      same prop must act on the same bitmap in a small view and a large one.
//   4. `center`: the image is drawn 1:1, not scaled to the view, so a smaller
//      decode would draw a smaller image.
//   5. Otherwise the view's size bounds what can be shown.
// `monochrome` and `tint` work per pixel, so they are indifferent to rule 5.
//
// `hasPixels` false asks for the target of a vector source instead
// (`ResolvedRequest::vectorDecode`): rule 1 does not apply, because there is
// no "every pixel" to want. Rules 3 and 4 still do: they are about the
// image's own size, which a vector has too.
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
  // Drop the fragment first: everything after '#' is client-side only.
  if (const auto hash = uri.find('#'); hash != std::string_view::npos) {
    uri = uri.substr(0, hash);
  }

  // Without "scheme://" there is no authority to normalise; keep the input
  // as-is rather than guessing.
  const auto schemeEnd = uri.find("://");
  if (schemeEnd == std::string_view::npos) {
    return std::string(uri);
  }

  // The authority runs until the first '/', '?' (or the end of the string).
  const auto authorityStart = schemeEnd + 3;
  auto authorityEnd = uri.find_first_of("/?", authorityStart);
  if (authorityEnd == std::string_view::npos) {
    authorityEnd = uri.size();
  }

  // "user:password@" in front of the host is case-sensitive and stays as
  // written. The last '@' ends it: an unencoded '@' inside a password is
  // malformed but seen in the wild, and the host cannot contain one.
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

  // Every field is spelled out: NDK clang's -Wmissing-field-initializers
  // (-Wextra) rejects partial designated initialisers under -Werror.
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

  // Cache-tier matrix. Keep this switch exhaustive (no `default:`) so adding
  // a policy is a compile error until both tiers are decided.
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
      // Writing back what we just read is pointless and, for Coil, would
      // re-encode the disk entry.
      resolved.memory.write = false;
      resolved.disk.write = false;
      break;
    case CachePolicy::UrlCache:
      resolved.httpCache = true;
      break;
  }
  // Applied after the matrix so every policy agrees on local sources: the
  // policy still governs the memory tier, never the disk or the "network".
  // A local file has no HTTP response, so there is no HTTP cache either.
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
  // Exhaustive on purpose (no `default:`), so a new code must get a name.
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
  }
  // Out-of-range values can arrive from the JNI/ObjC ABI boundary.
  return "unknown";
}

std::string_view coreVersion() { return "2.0.0-alpha.0"; }

bool needsLargerDecode(PixelSize decoded, PixelSize loadedFor, PixelSize now, bool fill) {
  // Every size must be known and positive; this is false for NaN too.
  const auto positive = [](PixelSize size) { return size.width > 0 && size.height > 0; };
  if (!positive(decoded) || !positive(loadedFor) || !positive(now)) {
    return false;
  }

  // Cut down for its view, or the source at its own size? A decode bounded
  // by the view touches the view's box on one side (fit) or covers it (fill);
  // one that stops short of that was capped by the source. One pixel of
  // slack for the decoders' rounding.
  constexpr double kRoundingSlack = 1;
  const bool shortOfWidth = loadedFor.width > decoded.width + kRoundingSlack;
  const bool shortOfHeight = loadedFor.height > decoded.height + kRoundingSlack;
  const bool cappedBySource = fill ? (shortOfWidth || shortOfHeight) : (shortOfWidth && shortOfHeight);
  if (cappedBySource) {
    return false;
  }

  // How much the view would scale the image up now, by the same rule the
  // decode followed: fill takes the larger of the two scales, fit the
  // smaller.
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

double area(PixelSize size) { return size.width * size.height; }

// The first known candidate of the largest area, or nullopt if none is known.
std::optional<std::size_t> largestSource(const std::vector<PixelSize>& candidates) {
  std::optional<std::size_t> best;
  for (std::size_t i = 0; i < candidates.size(); ++i) {
    if (isKnown(candidates[i]) && (!best || area(candidates[i]) > area(candidates[*best]))) {
      best = i;
    }
  }
  return best;
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

std::size_t chooseSource(const std::vector<PixelSize>& candidates, PixelSize view,
                         ResizeMode resizeMode, bool allowDownscaling) {
  const auto largest = largestSource(candidates);
  if (!largest) {
    return 0;
  }
  if (!allowDownscaling || resizeMode == ResizeMode::Center || !isKnown(view)) {
    return *largest;
  }
  // How much the view scales a candidate, by the decode-size rule: fill
  // takes the larger of the two scales, fit the smaller. At most 1: the
  // candidate has every pixel the view draws.
  const bool fill = resizeMode == ResizeMode::Cover || resizeMode == ResizeMode::Stretch;
  std::optional<std::size_t> best;
  for (std::size_t i = 0; i < candidates.size(); ++i) {
    const PixelSize candidate = candidates[i];
    if (!isKnown(candidate)) {
      continue;
    }
    const double horizontal = view.width / candidate.width;
    const double vertical = view.height / candidate.height;
    const double scale = fill ? std::max(horizontal, vertical) : std::min(horizontal, vertical);
    if (scale <= 1 && (!best || area(candidate) < area(candidates[*best]))) {
      best = i;
    }
  }
  return best.value_or(*largest);
}

std::optional<std::size_t> largerSourceFor(const std::vector<PixelSize>& candidates,
                                           std::size_t current, PixelSize now,
                                           ResizeMode resizeMode, bool allowDownscaling) {
  if (current >= candidates.size()) {
    return std::nullopt;
  }
  const std::size_t next = chooseSource(candidates, now, resizeMode, allowDownscaling);
  const bool larger = isKnown(candidates[next]) &&
                      (!isKnown(candidates[current]) ||
                       area(candidates[next]) > area(candidates[current]));
  return larger ? std::optional<std::size_t>(next) : std::nullopt;
}

}  // namespace turboimage
