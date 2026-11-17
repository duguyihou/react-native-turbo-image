#include "turboimage/ImageRequest.h"

#include <algorithm>
#include <array>
#include <cctype>

namespace turboimage {

namespace {

// Schemes the 2.0 walking skeleton accepts. Local assets (`file`, bundled
// resources) are a TODO for the pipeline milestone; they need per-platform
// resolution rules that are out of scope until both platforms build.
constexpr std::array<std::string_view, 2> kSupportedSchemes = {"http",
                                                               "https"};

char toLowerAscii(char c) {
  return static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
}

std::string lowerAscii(std::string_view s) {
  std::string out(s);
  std::transform(out.begin(), out.end(), out.begin(), toLowerAscii);
  return out;
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
  if (std::find(kSupportedSchemes.begin(), kSupportedSchemes.end(), scheme) ==
      kSupportedSchemes.end()) {
    return {.request = std::nullopt, .error = RequestError::UnsupportedScheme};
  }

  // Every field is spelled out: NDK clang's -Wmissing-field-initializers
  // (-Wextra) rejects partial designated initialisers under -Werror.
  ResolvedRequest resolved{
      .url = request.uri,
      .cacheKey = request.cacheKey.value_or(canonicalCacheKey(request.uri)),
      .processorKey = processorKey(
          resolveProcessing(request.processing, request.pixelRatio)),
      .memory = {.read = true, .write = true},
      .disk = {.read = true, .write = true},
      .allowNetwork = true,
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
