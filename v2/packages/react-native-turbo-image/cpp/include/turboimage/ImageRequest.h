// TurboImage core: cross-platform request semantics.
//
// This header is the single source of truth for what an image request
// *means* in TurboImage 2.0. The iOS (Nuke) and Android (Coil) adapters do
// not interpret JS props themselves; they receive a `ResolvedRequest` from
// `resolveRequest()` and translate it mechanically into loader options. That
// way cache keys and cache-tier behaviour cannot drift between platforms
// (RFC rule 2 and rule 3).
//
// Ownership contract:
//   * Every type here is a plain value type. Nothing holds pointers into
//     caller-owned memory, so results may outlive their inputs.
//
// Threading contract:
//   * Every function here is pure: no global state, no I/O, no allocation
//     shared across calls. They are safe to call concurrently from any
//     thread, including the RN JS thread, the UI thread, and loader worker
//     threads.
//
// Dependency contract:
//   * Standard library only. No React Native, Foundation, UIKit, JNI, or
//     Android headers may be included from `cpp/` (RFC rule: core has no
//     platform-framework dependencies). Platform glue lives in
//     `ios/Fabric/` and `android/src/main/cpp/`.

#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

#include "turboimage/Processing.h"

namespace turboimage {

// The JS-facing cache policy. The integer values are part of the ABI shared
// with the JNI bridge and the ObjC++ bridge, so they are pinned explicitly.
enum class CachePolicy : std::int32_t {
  // Read and write memory + disk, fall back to the network.
  Default = 0,
  // Never touch the disk cache; memory and network only.
  MemoryOnly = 1,
  // Skip every cache tier for reads and writes; always hit the network.
  NoCache = 2,
  // Serve from memory or disk only; never start a network request.
  CacheOnly = 3,
};

// What a loader is allowed to do with one cache tier. This maps 1:1 onto
// Coil's `CachePolicy` and onto Nuke's `ImageRequest.Options` read/write
// flags, which is why it is expressed as two booleans instead of a single
// enum: both loaders model reads and writes independently.
struct TierAccess {
  bool read = true;
  bool write = true;

  friend bool operator==(const TierAccess&, const TierAccess&) = default;
};

// Parses the JS spelling ('default' | 'memoryOnly' | 'noCache' |
// 'cacheOnly'). Unknown or empty strings yield std::nullopt; callers treat
// that as Default (Codegen already defaults the view prop). One parser so
// views and the cache module cannot disagree.
[[nodiscard]] std::optional<CachePolicy> parseCachePolicy(std::string_view js);

struct ImageRequest {
  std::string uri;
  // An explicit cache key overrides URI-derived keys. Used when the same
  // image is served from rotating signed URLs.
  std::optional<std::string> cacheKey;
  CachePolicy cachePolicy = CachePolicy::Default;
  // Pixel processors (resize/blur/monochrome/tint) and the screen scale that
  // converts `resize` from points/dp to pixels. See Processing.h.
  ProcessingOptions processing;
  double pixelRatio = 1;
};

struct ResolvedRequest {
  std::string url;
  // The key adapters MUST use for both memory and disk caches. It names the
  // *original* image: processed variants share it, and adapters attach
  // `processorKey` so their loader keeps one memory entry per variant while
  // the disk tier keeps one copy of the original bytes.
  std::string cacheKey;
  // Empty when no processing is requested; otherwise the identity of the
  // processing step and its complete description (see Processing.h).
  std::string processorKey;
  TierAccess memory;
  TierAccess disk;
  bool allowNetwork = true;

  friend bool operator==(const ResolvedRequest&, const ResolvedRequest&) =
      default;
};

enum class RequestError : std::int32_t {
  None = 0,
  EmptyUri = 1,
  UnsupportedScheme = 2,
};

struct ResolveResult {
  std::optional<ResolvedRequest> request;
  RequestError error = RequestError::None;

  [[nodiscard]] bool ok() const { return request.has_value(); }
};

// Why a load failed, as exposed to JS in `onError.code`. Adapters classify
// their loader's errors into these buckets so JS sees the same code for the
// same situation on both platforms (e.g. a `cacheOnly` miss is `NotCached`
// whether Nuke reports `dataMissingInCache` or Coil synthesises HTTP 504).
// Integer values are a pinned ABI shared with the ObjC seam and JNI.
enum class LoadErrorCode : std::int32_t {
  Unknown = 0,
  // The core rejected the request before any loader ran.
  InvalidRequest = 1,
  // The policy forbade the network and no cache tier had the image.
  NotCached = 2,
  // Transport or HTTP failure.
  Network = 3,
  // Bytes arrived but could not be decoded into an image.
  Decode = 4,
};

// The stable JS spelling of a `LoadErrorCode`.
[[nodiscard]] std::string_view loadErrorCodeName(LoadErrorCode code);

// Normalises a URI into the canonical form used for cache keys:
//   * scheme and host are lower-cased (they are case-insensitive per
//     RFC 3986, and the two loaders disagree on whether they normalise them),
//   * the fragment is dropped (it never reaches the server).
// Path and query are preserved byte-for-byte because servers may treat them
// case-sensitively.
[[nodiscard]] std::string canonicalCacheKey(std::string_view uri);

// Turns JS-facing props into the platform-neutral instructions adapters
// execute. Validation lives here so both platforms reject the same inputs.
[[nodiscard]] ResolveResult resolveRequest(const ImageRequest& request);

// A stable, human-readable version string for the core, surfaced in the
// example app so a build can prove it linked the shared C++ code.
[[nodiscard]] std::string_view coreVersion();

}  // namespace turboimage
