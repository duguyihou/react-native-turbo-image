// TurboImage core: what an image request means, shared by both platforms.
//
// Adapters (Nuke, Coil) do not read JS props; they translate a
// `ResolvedRequest` into loader options, so cache keys and tiers cannot
// drift between platforms (RFC rules 2 and 3).
//
// All types are plain values and all functions are pure and thread-safe.
// Standard library only: no RN, Apple, JNI or Android headers in `cpp/`.

#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "turboimage/Processing.h"

namespace turboimage {

// The JS cache policy. Values are pinned ABI shared with JNI and ObjC++.
enum class CachePolicy : std::int32_t {
  // Memory + disk, then network.
  Default = 0,
  // Memory and network; never disk.
  MemoryOnly = 1,
  // No cache reads or writes; always network.
  NoCache = 2,
  // Memory or disk only; never network.
  CacheOnly = 3,
  // Disk tier is the platform HTTP cache, which obeys `Cache-Control`.
  // See `ResolvedRequest::httpCache`.
  UrlCache = 4,
};

// The JS `resizeMode`. Drives `DecodeSize` and `placeImage`. Pinned ABI.
enum class ResizeMode : std::int32_t {
  Contain = 0,
  Cover = 1,
  Stretch = 2,
  Center = 3,
  // `center` if the image fits, else `contain` (CSS `scale-down`).
  ScaleDown = 4,
};

// How large the loader should decode the image. Every target is an upper
// bound (never upscale), except for vector sources; see `vectorDecode`.
// `View` is resolved by the platform, which knows the view's size.
struct DecodeSize {
  enum class Kind : std::int32_t {
    // Every pixel of the source.
    Original = 0,
    // The view's size in pixels; see `fill`.
    View = 1,
    // `width` pixels wide, keeping aspect ratio.
    Width = 2,
  };

  Kind kind = Kind::Original;
  // Kind::Width only: target width in pixels.
  std::int32_t width = 0;
  // Kind::View only. true: cover the view (cover, stretch); false: fit it.
  bool fill = false;

  friend bool operator==(const DecodeSize&, const DecodeSize&) = default;
};

// A view's or an image's size in pixels.
struct PixelSize {
  double width = 0;
  double height = 0;
};

// The rect a view draws the whole image into, in the box's units. It may
// overflow the box; the view clips.
struct PlacedRect {
  double x = 0;
  double y = 0;
  double width = 0;
  double height = 0;
  friend bool operator==(const PlacedRect&, const PlacedRect&) = default;
};

// `contentPosition` as fractions of the free space (CSS `object-position`):
// 0 = left/top, 0.5 = centre, 1 = right/bottom. Clamped to [0, 1].
struct ContentPosition {
  double x = 0.5;
  double y = 0.5;
  friend bool operator==(const ContentPosition&, const ContentPosition&) = default;
};

// The rect `image` is drawn in inside `box` (origin 0,0) for `resizeMode`
// and `position`. Views use this when the platform has no matching mode, so
// both platforms place images the same way. Unknown sizes give the box.
[[nodiscard]] PlacedRect placeImage(PixelSize image, PixelSize box, ResizeMode resizeMode,
                                    ContentPosition position);

// Whether a view that grew should reload its image at the new size
// (`DecodeSize::Kind::View` only). True when the view would draw the image
// at more than 1.5x its pixels (a ratio, so animated resizes do not reload
// every frame) and the image was actually downscaled for its old size.
[[nodiscard]] bool needsLargerDecode(PixelSize decoded, PixelSize loadedFor, PixelSize now, bool fill);

// Read/write access to one cache tier. Two booleans because both Coil and
// Nuke model reads and writes separately.
struct TierAccess {
  bool read = true;
  bool write = true;

  friend bool operator==(const TierAccess&, const TierAccess&) = default;
};

// Parses the JS spelling ('default' | 'memoryOnly' | 'noCache' |
// 'cacheOnly' | 'urlCache'). Unknown or empty gives nullopt (treat as Default).
[[nodiscard]] std::optional<CachePolicy> parseCachePolicy(std::string_view js);

// One HTTP request header from `source.headers`. Order is preserved.
struct Header {
  std::string name;
  std::string value;

  friend bool operator==(const Header&, const Header&) = default;
};

// Everything a view's props say about which image to load and how. Views
// reload when this changes, so a new field here triggers reloads on both
// platforms for free.
struct ImageRequest {
  std::string uri;
  // Overrides the URI-derived cache key (e.g. for rotating signed URLs).
  std::optional<std::string> cacheKey;
  CachePolicy cachePolicy = CachePolicy::Default;
  // Processors and the screen scale that converts `resize` to pixels.
  ProcessingOptions processing;
  double pixelRatio = 1;
  // Sent with the request. Not part of the cache key: use a per-user
  // `cacheKey` for per-user content at one URL.
  std::vector<Header> headers;
  // JS `allowDownscaling` (default true). false always decodes the original.
  bool allowDownscaling = true;
  ResizeMode resizeMode = ResizeMode::Contain;

  friend bool operator==(const ImageRequest&, const ImageRequest&) = default;
};

struct ResolvedRequest {
  std::string url;
  // Key for both memory and disk caches. Names the original image;
  // adapters add `processorKey` so each variant gets its own memory entry
  // while disk keeps one copy of the original.
  std::string cacheKey;
  // Empty when there is no processing (see Processing.h).
  std::string processorKey;
  // Validated headers, in order.
  std::vector<Header> headers;
  TierAccess memory;
  TierAccess disk;
  bool allowNetwork = true;
  // true: the disk tier is the HTTP cache, keyed by `url` and obeying
  // `Cache-Control`; the key-addressed disk cache is not touched, so a later
  // `cacheOnly` load will not see it. Memory still uses `cacheKey`.
  bool httpCache = false;
  DecodeSize decode;
  // Decode target if the source turns out to be a vector (SVG); only the
  // loader can tell. Ignores `allowDownscaling = false` (a vector has no
  // original to keep); `Original` here means its own size in points/dp.
  DecodeSize vectorDecode;

  friend bool operator==(const ResolvedRequest&, const ResolvedRequest&) =
      default;
};

enum class RequestError : std::int32_t {
  None = 0,
  EmptyUri = 1,
  UnsupportedScheme = 2,
  // Header name not an RFC 9110 token, or a value with anything but tab and
  // printable ASCII (CR, LF and NUL included).
  // Rejected, not dropped: prevents injection without hiding auth bugs.
  InvalidHeader = 3,
};

struct ResolveResult {
  std::optional<ResolvedRequest> request;
  RequestError error = RequestError::None;

  [[nodiscard]] bool ok() const { return request.has_value(); }
};

// Why a load failed (JS `onError.code`). Adapters map loader errors into
// these so both platforms report the same code. Pinned ABI.
enum class LoadErrorCode : std::int32_t {
  Unknown = 0,
  // The core rejected the request before any loader ran.
  InvalidRequest = 1,
  // Network forbidden and no cache tier had the image.
  NotCached = 2,
  // Transport failure, or a gateway timeout (HTTP 504): may recover.
  Network = 3,
  // Bytes arrived but could not be decoded.
  Decode = 4,
  // The server answered with an error status other than 504 (a 404, say):
  // asking again gets the same answer.
  Http = 5,
};

// The stable JS spelling of a `LoadErrorCode`.
[[nodiscard]] std::string_view loadErrorCodeName(LoadErrorCode code);

// Canonical cache-key form of a URI: lower-case ASCII scheme and host (not
// userinfo), fragment dropped. Path and query are kept byte for byte.
[[nodiscard]] std::string canonicalCacheKey(std::string_view uri);

// Whether two URIs share an origin: scheme, host and port, ignoring case
// and userinfo, with a missing port read as the scheme's default (80 for
// http, 443 for https). A URI without "scheme://" shares none. Decides
// whether `placeholder.uri` gets the source's headers.
[[nodiscard]] bool sameOrigin(std::string_view a, std::string_view b);

// Keys to try, in order, for `placeholder.memoryCacheKey`: as written
// (an explicit `cacheKey`), then canonicalised (a URI). Deduplicated;
// empty for an empty key.
[[nodiscard]] std::vector<std::string> memoryCacheKeyCandidates(std::string_view key);

// Who the resolved request is for. Pinned ABI (crosses JNI as an int).
enum class RequestPurpose : std::int32_t {
  // A view: load, decode and show.
  Display = 0,
  // `TurboImage.prefetch`: store the bytes and decode nothing, unless only
  // memory would keep them.
  Prefetch = 1,
};

// Validates JS props and turns them into adapter instructions.
[[nodiscard]] ResolveResult resolveRequest(
    const ImageRequest& request,
    RequestPurpose purpose = RequestPurpose::Display);

// Core version string, shown in the example app to prove the C++ is linked.
[[nodiscard]] std::string_view coreVersion();

}  // namespace turboimage
