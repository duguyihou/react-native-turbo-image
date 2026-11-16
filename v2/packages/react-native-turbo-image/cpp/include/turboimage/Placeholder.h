// TurboImage core: placeholder decoders (blurhash, thumbhash).
//
// 1.x shipped four hand ports of these algorithms (Swift and Kotlin, one
// each per format). 2.0 decodes in this one C++ implementation on both
// platforms (RFC rule 4). Output is verified byte for byte against the
// canonical JS references (see cpp/tests/tools/generate-placeholder-goldens.mjs).
//
// Ownership contract: results are value types that own their pixel buffer.
//
// Threading contract: pure functions, safe on any thread. Decoding costs up
// to ~1 ms (blurhash 9x9 at 32x32), so platforms call these OFF the main
// thread and apply the result on main behind an identity check.
//
// Input contract: inputs come from JS and are untrusted. Malformed input
// returns std::nullopt; it never reads out of bounds. (The JS references
// do not validate thumbhash lengths at all.)

#pragma once

#include <cstdint>
#include <optional>
#include <string_view>
#include <vector>

namespace turboimage {

struct RgbaImage {
  int width = 0;
  int height = 0;
  // Row-major RGBA8, 4 * width * height bytes. Whether alpha is straight or
  // premultiplied is documented per function.
  std::vector<std::uint8_t> pixels;
};

// Decodes a blurhash into a straight-alpha (always opaque) image of the
// requested size. `width`/`height` must be in [1, 128]; placeholders are
// upscaled by the view, so larger sizes only burn CPU.
[[nodiscard]] std::optional<RgbaImage> decodeBlurhash(std::string_view hash,
                                                      int width, int height);

// Decodes a base64-encoded thumbhash into a straight-alpha image. The output
// size is derived from the hash's aspect ratio, with the long edge at 32 px.
[[nodiscard]] std::optional<RgbaImage> decodeThumbhash(
    std::string_view base64Hash);

// Converts straight alpha to premultiplied alpha in place, which is what
// both CGImage (premultipliedLast) and Android's ARGB_8888 Bitmap expect.
void premultiplyAlpha(RgbaImage& image);

// What the views call: decodes whichever hash is non-empty (blurhash wins
// if both are set, matching JS-side validation that allows only one) and
// returns premultiplied pixels ready for the platform image type.
[[nodiscard]] std::optional<RgbaImage> decodePlaceholder(
    std::string_view blurhash, std::string_view thumbhash);

}  // namespace turboimage
