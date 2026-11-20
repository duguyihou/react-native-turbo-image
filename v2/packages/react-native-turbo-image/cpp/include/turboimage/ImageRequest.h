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
#include <vector>

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
  // Memory as usual, but the disk tier is the platform's HTTP cache, which
  // obeys the response's `Cache-Control` (freshness, revalidation with
  // ETag/Last-Modified, `no-store`). 1.x's name and, on iOS, 1.x's behaviour.
  // See `ResolvedRequest::httpCache` for what this means for adapters.
  UrlCache = 4,
};

// The JS `resizeMode`. The core needs it for one decision only: how large an
// image the view needs decoded (`DecodeSize`). Drawing stays with the views.
// Pinned ABI, like `CachePolicy`.
enum class ResizeMode : std::int32_t {
  Contain = 0,
  Cover = 1,
  Stretch = 2,
  Center = 3,
};

// How large the loader should decode the image. Decoding a 12 MP photo for a
// 100 pt avatar costs ~48 MB of bitmap for pixels nobody sees; downsampling
// while decoding (ImageIO thumbnails, BitmapFactory sampling) avoids ever
// allocating them. The core decides *which* target applies; only the loader
// knows the view's size, so `View` is resolved by the platform.
//
// Every target is an upper bound: images are never upscaled to reach it.
// The exception is a source with no pixels of its own (SVG), which is drawn
// at the target; see `ResolvedRequest::vectorDecode`.
struct DecodeSize {
  enum class Kind : std::int32_t {
    // Decode every pixel of the source.
    Original = 0,
    // Decode to the view's size in pixels; see `fill`.
    View = 1,
    // Decode to `width` pixels wide, keeping the aspect ratio.
    Width = 2,
  };

  Kind kind = Kind::Original;
  // Kind::Width only: the target width in pixels.
  std::int32_t width = 0;
  // Kind::View only. true: the image must cover the view (the larger of the
  // two scale factors), for `cover` and `stretch`. false: it only has to fit
  // inside it, for `contain`.
  bool fill = false;

  friend bool operator==(const DecodeSize&, const DecodeSize&) = default;
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
// 'cacheOnly' | 'urlCache'). Unknown or empty strings yield std::nullopt; callers treat
// that as Default (Codegen already defaults the view prop). One parser so
// views and the cache module cannot disagree.
[[nodiscard]] std::optional<CachePolicy> parseCachePolicy(std::string_view js);

// One HTTP request header from `source.headers`. Order is preserved.
struct Header {
  std::string name;
  std::string value;

  friend bool operator==(const Header&, const Header&) = default;
};

// Everything a view's props say about which image to load and how. Two equal
// requests are the same load, which is how the views decide whether a prop
// change needs a new one: they compare this, field by field, instead of
// keeping their own list of "props that reload". A field added here takes
// part in that on both platforms without further code.
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
  // Sent with the network request (1.x `source.headers`), e.g. an auth
  // token. Deliberately NOT part of the cache key, as in 1.x: a URL is one
  // cache entry whoever fetched it. Apps that serve per-user content at one
  // URL must pass a per-user `cacheKey`.
  std::vector<Header> headers;
  // The JS `allowDownscaling` prop (default true, expo-image's name and
  // meaning). false always decodes the original, for views that are zoomed
  // or grow after the image has loaded.
  bool allowDownscaling = true;
  ResizeMode resizeMode = ResizeMode::Contain;

  friend bool operator==(const ImageRequest&, const ImageRequest&) = default;
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
  // Validated copies of the request's headers, in order.
  std::vector<Header> headers;
  TierAccess memory;
  TierAccess disk;
  bool allowNetwork = true;
  // true: this request's disk tier is the HTTP cache, and `disk` describes
  // access to that. It is a store of its own, not the key-addressed disk
  // cache the other policies use:
  //   * it is keyed by `url` (HTTP caches know nothing of `cacheKey`, which
  //     still keys the memory tier),
  //   * an entry is served only while the response's `Cache-Control` /
  //     `Expires` say it is fresh, is revalidated when stale, and is never
  //     stored for `no-store`,
  //   * nothing is read from or written to the key-addressed disk cache, so
  //     a later `cacheOnly` load does not see what this request stored.
  // The memory tier holds decoded images and never expires within a process;
  // that is deliberate (a list must not refetch on every scroll) and the
  // same on both platforms.
  bool httpCache = false;
  DecodeSize decode;
  // The size to draw the image at if it turns out to have no pixels of its
  // own (SVG). Only the loader learns that, from the bytes, so both targets
  // are always resolved. It is `decode` as it would be with
  // `allowDownscaling` left on: a vector has no original to keep, and
  // drawing it at its own (often small) size and scaling that up is what
  // the opt-out exists to prevent. `Original` here means the image's own
  // size read as points/dp, so it draws as large as on a 1x screen and as
  // sharp as this one allows.
  DecodeSize vectorDecode;

  friend bool operator==(const ResolvedRequest&, const ResolvedRequest&) =
      default;
};

enum class RequestError : std::int32_t {
  None = 0,
  EmptyUri = 1,
  UnsupportedScheme = 2,
  // A header name that is not an RFC 9110 token, or a value containing CR,
  // LF or NUL. Rejected rather than dropped: passing it on would allow
  // header injection, and silently dropping it would hide an auth bug.
  InvalidHeader = 3,
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
//     RFC 3986, and the two loaders disagree on whether they normalise them);
//     ASCII letters only, and not the userinfo in front of the host,
//   * the fragment is dropped (it never reaches the server).
// Path and query are preserved byte-for-byte because servers may treat them
// case-sensitively.
[[nodiscard]] std::string canonicalCacheKey(std::string_view uri);

// The cache keys a `placeholder.memoryCacheKey` may name, in the order to
// look them up. The prop takes either what a source would be given as
// `cacheKey` or what it would be given as `uri`, and the two are stored
// differently: an explicit key verbatim, a URI in canonical form. So the key
// is tried as written first and then canonicalised (once, if both are the
// same). Empty for an empty key.
[[nodiscard]] std::vector<std::string> memoryCacheKeyCandidates(std::string_view key);

// Turns JS-facing props into the platform-neutral instructions adapters
// execute. Validation lives here so both platforms reject the same inputs.
[[nodiscard]] ResolveResult resolveRequest(const ImageRequest& request);

// A stable, human-readable version string for the core, surfaced in the
// example app so a build can prove it linked the shared C++ code.
[[nodiscard]] std::string_view coreVersion();

}  // namespace turboimage
