#include "turboimage/ImageRequest.h"

#include <algorithm>
#include <array>
#include <cctype>

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

char toLowerAscii(char c) {
  return static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
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
DecodeSize resolveDecodeSize(const ImageRequest& request,
                             const ProcessingSpec& processing) {
  const DecodeSize original{
      .kind = DecodeSize::Kind::Original, .width = 0, .fill = false};
  if (!request.allowDownscaling) {
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
  return {.kind = DecodeSize::Kind::View,
          .width = 0,
          .fill = request.resizeMode != ResizeMode::Contain};
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

  std::string key;
  key.reserve(uri.size());
  key += lowerAscii(uri.substr(0, authorityEnd));
  key += uri.substr(authorityEnd);
  return key;
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
      .decode = resolveDecodeSize(request, processing),
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
  }
  // Applied after the matrix so every policy agrees on local sources: the
  // policy still governs the memory tier, never the disk or the "network".
  if (isLocal) {
    resolved.disk = {.read = false, .write = false};
    resolved.allowNetwork = true;
  }

  return {.request = std::move(resolved), .error = RequestError::None};
}

std::optional<CachePolicy> parseCachePolicy(std::string_view js) {
  if (js == "default") return CachePolicy::Default;
  if (js == "memoryOnly") return CachePolicy::MemoryOnly;
  if (js == "noCache") return CachePolicy::NoCache;
  if (js == "cacheOnly") return CachePolicy::CacheOnly;
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

}  // namespace turboimage
