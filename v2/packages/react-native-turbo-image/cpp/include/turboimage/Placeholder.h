// TurboImage core: blurhash and thumbhash decoders, shared by both
// platforms (RFC rule 4). Output matches the JS references byte for byte
// (see cpp/tests/tools/generate-placeholder-goldens.mjs).
//
// Pure functions, safe on any thread; call them off the main thread.
// Input is untrusted: malformed input returns nullopt, never reads out of
// bounds.

#pragma once

#include <cstdint>
#include <optional>
#include <string_view>
#include <vector>

namespace turboimage {

struct RgbaImage {
  int width = 0;
  int height = 0;
  // Row-major RGBA8, 4 * width * height bytes. Alpha mode is per function.
  std::vector<std::uint8_t> pixels;
};

// Decodes a blurhash into an opaque image. `width`/`height` must be in
// [1, 128]; the view upscales placeholders anyway.
[[nodiscard]] std::optional<RgbaImage> decodeBlurhash(std::string_view hash,
                                                      int width, int height);

// Decodes a base64 thumbhash into a straight-alpha image, long edge 32 px.
[[nodiscard]] std::optional<RgbaImage> decodeThumbhash(
    std::string_view base64Hash);

// Straight to premultiplied alpha in place, as CGImage and Android
// ARGB_8888 expect.
void premultiplyAlpha(RgbaImage& image);

// What views call: decodes whichever hash is non-empty (blurhash wins) and
// returns premultiplied pixels.
[[nodiscard]] std::optional<RgbaImage> decodePlaceholder(
    std::string_view blurhash, std::string_view thumbhash);

}  // namespace turboimage
