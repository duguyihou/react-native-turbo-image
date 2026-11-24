// JNI bridge to the shared C++ core.
//
// Only local references; nothing is cached across calls. The core is pure,
// so any thread is fine. A C++ exception reaching the JVM aborts, so every
// entry point runs through `guarded`, which turns it into a Java exception.

#include <android/bitmap.h>
#include <jni.h>

#include <cstdint>
#include <cstring>
#include <exception>
#include <new>
#include <optional>
#include <string>
#include <vector>

#include "turboimage/ImageRequest.h"
#include "turboimage/Placeholder.h"
#include "turboimage/Processing.h"
#include "turboimage/Progress.h"
#include "turboimage/ViewLifecycle.h"

namespace {

// Enums cross as plain ints; these catch a value renumbered on one side only.
#define TI_ASSERT_ABI(value, expected) \
  static_assert(static_cast<jint>(value) == (expected), "TurboImageCore.kt mirrors " #value)
TI_ASSERT_ABI(turboimage::CachePolicy::Default, 0);
TI_ASSERT_ABI(turboimage::CachePolicy::MemoryOnly, 1);
TI_ASSERT_ABI(turboimage::CachePolicy::NoCache, 2);
TI_ASSERT_ABI(turboimage::CachePolicy::CacheOnly, 3);
TI_ASSERT_ABI(turboimage::CachePolicy::UrlCache, 4);
TI_ASSERT_ABI(turboimage::ResizeMode::Contain, 0);
TI_ASSERT_ABI(turboimage::ResizeMode::Cover, 1);
TI_ASSERT_ABI(turboimage::ResizeMode::Stretch, 2);
TI_ASSERT_ABI(turboimage::ResizeMode::Center, 3);
TI_ASSERT_ABI(turboimage::ResizeMode::ScaleDown, 4);
TI_ASSERT_ABI(turboimage::LoadErrorCode::Unknown, 0);
TI_ASSERT_ABI(turboimage::LoadErrorCode::InvalidRequest, 1);
TI_ASSERT_ABI(turboimage::LoadErrorCode::NotCached, 2);
TI_ASSERT_ABI(turboimage::LoadErrorCode::Network, 3);
TI_ASSERT_ABI(turboimage::LoadErrorCode::Decode, 4);
TI_ASSERT_ABI(turboimage::DecodeSize::Kind::Original, 0);
TI_ASSERT_ABI(turboimage::DecodeSize::Kind::View, 1);
TI_ASSERT_ABI(turboimage::DecodeSize::Kind::Width, 2);
// `Effect.Kind` is decoded by position, so its order is ABI too.
TI_ASSERT_ABI(turboimage::PlaceholderKind::None, 0);
TI_ASSERT_ABI(turboimage::PlaceholderKind::Hash, 1);
TI_ASSERT_ABI(turboimage::PlaceholderKind::MemoryCacheKey, 2);
TI_ASSERT_ABI(turboimage::LifecycleEffect::Kind::CancelLoad, 0);
TI_ASSERT_ABI(turboimage::LifecycleEffect::Kind::ClearImage, 1);
TI_ASSERT_ABI(turboimage::LifecycleEffect::Kind::EmitCancelled, 2);
TI_ASSERT_ABI(turboimage::LifecycleEffect::Kind::EmitCompleted, 3);
TI_ASSERT_ABI(turboimage::LifecycleEffect::Kind::DeliverInvalidRequest, 4);
TI_ASSERT_ABI(turboimage::LifecycleEffect::Kind::StartLoad, 5);
TI_ASSERT_ABI(turboimage::LifecycleEffect::Kind::DeliverSuccess, 6);
TI_ASSERT_ABI(turboimage::LifecycleEffect::Kind::DeliverFailure, 7);
TI_ASSERT_ABI(turboimage::LifecycleEffect::Kind::ShowCachedPlaceholder, 8);
TI_ASSERT_ABI(turboimage::LifecycleEffect::Kind::DecodePlaceholder, 9);
#undef TI_ASSERT_ABI

// State crosses as a LongArray(3); a new field would not round-trip.
static_assert(sizeof(turboimage::ProgressThrottle) == 3 * sizeof(jlong),
              "ProgressThrottle no longer fits the LongArray(3) Kotlin keeps it in");
// Likewise the view lifecycle, a LongArray(5).
static_assert(sizeof(turboimage::ViewLifecycle) == 5 * sizeof(jlong),
              "ViewLifecycle no longer fits the LongArray(5) Kotlin keeps it in");

// A Java exception is already pending; unwind to `guarded` without more JNI calls.
struct JavaExceptionPending {};

void throwJava(JNIEnv* env, const char* className, const char* message) {
  if (env->ExceptionCheck()) {
    return;  // Keep the first exception.
  }
  jclass exceptionClass = env->FindClass(className);
  if (exceptionClass != nullptr) {
    env->ThrowNew(exceptionClass, message);
  }
  // Otherwise FindClass left a NoClassDefFoundError pending.
}

// Runs `body`; if it throws, leaves a Java exception pending and returns `fallback`.
template <typename Result, typename Body>
Result guarded(JNIEnv* env, Result fallback, Body&& body) noexcept {
  try {
    return body();
  } catch (const JavaExceptionPending&) {
    // Already pending.
  } catch (const std::bad_alloc&) {
    throwJava(env, "java/lang/OutOfMemoryError", "TurboImage: the C++ core ran out of memory");
  } catch (const std::exception& e) {
    throwJava(env, "java/lang/RuntimeException", e.what());
  } catch (...) {
    throwJava(env, "java/lang/RuntimeException", "TurboImage: unknown C++ exception");
  }
  return fallback;
}

std::string toStdString(JNIEnv* env, jstring value) {
  if (value == nullptr) {
    return {};
  }
  const char* chars = env->GetStringUTFChars(value, nullptr);
  if (chars == nullptr) {
    throw JavaExceptionPending{};  // OutOfMemoryError from the JVM.
  }
  std::string out(chars);
  env->ReleaseStringUTFChars(value, chars);
  return out;
}

// Colours are a jlong 0xAARRGGBB, or -1 for unset.
std::optional<std::uint32_t> toArgb(jlong value) {
  if (value < 0) {
    return std::nullopt;
  }
  return static_cast<std::uint32_t>(value & 0xffffffff);
}

// `String[]` of alternating names and values <-> core headers.
std::vector<turboimage::Header> toHeaders(JNIEnv* env, jobjectArray flat) {
  std::vector<turboimage::Header> headers;
  const jsize length = flat == nullptr ? 0 : env->GetArrayLength(flat);
  for (jsize i = 0; i + 1 < length; i += 2) {
    auto name = static_cast<jstring>(env->GetObjectArrayElement(flat, i));
    auto value = static_cast<jstring>(env->GetObjectArrayElement(flat, i + 1));
    headers.push_back({.name = toStdString(env, name), .value = toStdString(env, value)});
    env->DeleteLocalRef(name);
    env->DeleteLocalRef(value);
  }
  return headers;
}

jobjectArray fromHeaders(JNIEnv* env, const std::vector<turboimage::Header>& headers) {
  jclass stringClass = env->FindClass("java/lang/String");
  auto flat = env->NewObjectArray(static_cast<jsize>(headers.size() * 2), stringClass, nullptr);
  for (std::size_t i = 0; i < headers.size(); ++i) {
    jstring name = env->NewStringUTF(headers[i].name.c_str());
    jstring value = env->NewStringUTF(headers[i].value.c_str());
    env->SetObjectArrayElement(flat, static_cast<jsize>(2 * i), name);
    env->SetObjectArrayElement(flat, static_cast<jsize>(2 * i + 1), value);
    env->DeleteLocalRef(name);
    env->DeleteLocalRef(value);
  }
  return flat;
}

}  // namespace

// Returns `ResolvedRequest` or `ResolveFailure` (kept in consumer-rules.pro).
extern "C" JNIEXPORT jobject JNICALL
Java_com_turboimage_core_TurboImageCore_nativeResolve(JNIEnv* env, jobject /* this */,
                                                       jstring uri, jstring cacheKey,
                                                       jint cachePolicy, jdouble resize,
                                                       jdouble blur, jlong monochrome,
                                                       jlong tint, jdouble pixelRatio,
                                                       jobjectArray headers,
                                                       jboolean allowDownscaling,
                                                       jint resizeMode) {
  return guarded(env, static_cast<jobject>(nullptr), [&]() -> jobject {
    const auto key = toStdString(env, cacheKey);
    const auto result = turboimage::resolveRequest({
        .uri = toStdString(env, uri),
        .cacheKey = key.empty() ? std::nullopt : std::optional<std::string>(key),
        .cachePolicy = static_cast<turboimage::CachePolicy>(cachePolicy),
        .processing = {.resize = resize,
                       .blur = blur,
                       .monochrome = toArgb(monochrome),
                       .tint = toArgb(tint)},
        .pixelRatio = pixelRatio,
        .headers = toHeaders(env, headers),
        .allowDownscaling = allowDownscaling == JNI_TRUE,
        .resizeMode = static_cast<turboimage::ResizeMode>(resizeMode),
    });

    if (!result.ok()) {
      jclass failureClass = env->FindClass("com/turboimage/core/ResolveFailure");
      jmethodID ctor = env->GetMethodID(failureClass, "<init>", "(I)V");
      return env->NewObject(failureClass, ctor, static_cast<jint>(result.error));
    }

    const auto& r = *result.request;
    jclass resolvedClass = env->FindClass("com/turboimage/core/ResolvedRequest");
    jmethodID ctor =
        env->GetMethodID(resolvedClass, "<init>",
                         "(Ljava/lang/String;Ljava/lang/String;ZZZZZLjava/lang/String;[Ljava/lang/String;ZIIZIIZ)V");
    return env->NewObject(resolvedClass, ctor, env->NewStringUTF(r.url.c_str()),
                          env->NewStringUTF(r.cacheKey.c_str()), r.memory.read, r.memory.write,
                          r.disk.read, r.disk.write, r.allowNetwork,
                          env->NewStringUTF(r.processorKey.c_str()), fromHeaders(env, r.headers),
                          r.httpCache, static_cast<jint>(r.decode.kind),
                          static_cast<jint>(r.decode.width), r.decode.fill,
                          static_cast<jint>(r.vectorDecode.kind),
                          static_cast<jint>(r.vectorDecode.width), r.vectorDecode.fill);
  });
}

namespace {

// Wraps core pixels as `PlaceholderPixels` (premultiplied RGBA plus a size).
jobject toPixels(JNIEnv* env, const turboimage::RgbaImage& image) {
  const auto size = static_cast<jsize>(image.pixels.size());
  jbyteArray bytes = env->NewByteArray(size);
  if (bytes == nullptr) {
    return nullptr;  // OutOfMemoryError is pending; let it propagate.
  }
  env->SetByteArrayRegion(bytes, 0, size, reinterpret_cast<const jbyte*>(image.pixels.data()));
  jclass pixelsClass = env->FindClass("com/turboimage/core/PlaceholderPixels");
  jmethodID ctor = env->GetMethodID(pixelsClass, "<init>", "(II[B)V");
  return env->NewObject(pixelsClass, ctor, image.width, image.height, bytes);
}

// RAII lock on a Bitmap's pixels, so a throw can't leave it locked.
class LockedPixels {
 public:
  LockedPixels(JNIEnv* env, jobject bitmap) : env_(env), bitmap_(bitmap) {
    if (AndroidBitmap_lockPixels(env, bitmap, &pixels_) != ANDROID_BITMAP_RESULT_SUCCESS) {
      pixels_ = nullptr;
    }
  }
  ~LockedPixels() {
    if (pixels_ != nullptr) {
      AndroidBitmap_unlockPixels(env_, bitmap_);
    }
  }
  LockedPixels(const LockedPixels&) = delete;
  LockedPixels& operator=(const LockedPixels&) = delete;

  [[nodiscard]] std::uint8_t* data() const { return static_cast<std::uint8_t*>(pixels_); }

 private:
  JNIEnv* env_;
  jobject bitmap_;
  void* pixels_ = nullptr;
};

// `Bitmap.createBitmap(width, height, ARGB_8888)`; null with an OOM pending.
jobject createArgb8888Bitmap(JNIEnv* env, int width, int height) {
  jclass bitmapClass = env->FindClass("android/graphics/Bitmap");
  jclass configClass = env->FindClass("android/graphics/Bitmap$Config");
  jfieldID argb8888 =
      env->GetStaticFieldID(configClass, "ARGB_8888", "Landroid/graphics/Bitmap$Config;");
  jobject config = env->GetStaticObjectField(configClass, argb8888);
  jmethodID createBitmap = env->GetStaticMethodID(
      bitmapClass, "createBitmap", "(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;");
  jobject bitmap = env->CallStaticObjectMethod(bitmapClass, createBitmap, width, height, config);
  return env->ExceptionCheck() ? nullptr : bitmap;
}

}  // namespace

// Applies `processorKey` to an ARGB_8888 Bitmap, returning a new one; null
// if the key or Bitmap is unusable. Copies row by row: stride may exceed
// width × 4.
extern "C" JNIEXPORT jobject JNICALL
Java_com_turboimage_core_TurboImageCore_nativeProcess(JNIEnv* env, jobject /* this */,
                                                       jobject input, jstring processorKey) {
  return guarded(env, static_cast<jobject>(nullptr), [&]() -> jobject {
    AndroidBitmapInfo info{};
    if (AndroidBitmap_getInfo(env, input, &info) != ANDROID_BITMAP_RESULT_SUCCESS ||
        info.format != ANDROID_BITMAP_FORMAT_RGBA_8888) {
      return nullptr;
    }
    const std::size_t rowBytes = static_cast<std::size_t>(info.width) * 4;
    turboimage::RgbaImage image{
        .width = static_cast<int>(info.width), .height = static_cast<int>(info.height), .pixels = {}};
    image.pixels.resize(rowBytes * info.height);
    {
      const LockedPixels source(env, input);
      if (source.data() == nullptr) {
        return nullptr;
      }
      for (std::uint32_t row = 0; row < info.height; ++row) {
        std::memcpy(image.pixels.data() + row * rowBytes, source.data() + row * info.stride, rowBytes);
      }
    }

    const auto processed = turboimage::processImage(std::move(image), toStdString(env, processorKey));
    if (!processed) {
      return nullptr;
    }

    jobject output = createArgb8888Bitmap(env, processed->width, processed->height);
    if (output == nullptr) {
      throw JavaExceptionPending{};
    }
    AndroidBitmapInfo outputInfo{};
    if (AndroidBitmap_getInfo(env, output, &outputInfo) != ANDROID_BITMAP_RESULT_SUCCESS) {
      return nullptr;
    }
    const std::size_t outputRowBytes = static_cast<std::size_t>(processed->width) * 4;
    const LockedPixels destination(env, output);
    if (destination.data() == nullptr) {
      return nullptr;
    }
    for (int row = 0; row < processed->height; ++row) {
      std::memcpy(destination.data() + static_cast<std::size_t>(row) * outputInfo.stride,
                  processed->pixels.data() + static_cast<std::size_t>(row) * outputRowBytes,
                  outputRowBytes);
    }
    return output;
  });
}

// Returns `PlaceholderPixels`, or null if neither hash decodes.
extern "C" JNIEXPORT jobject JNICALL
Java_com_turboimage_core_TurboImageCore_nativeDecodePlaceholder(JNIEnv* env, jobject /* this */,
                                                                 jstring blurhash,
                                                                 jstring thumbhash) {
  return guarded(env, static_cast<jobject>(nullptr), [&]() -> jobject {
    const auto image =
        turboimage::decodePlaceholder(toStdString(env, blurhash), toStdString(env, thumbhash));
    return image ? toPixels(env, *image) : nullptr;
  });
}

// State lives in a Kotlin LongArray(3): read, decide, write back.
extern "C" JNIEXPORT jboolean JNICALL
Java_com_turboimage_core_TurboImageCore_nativeShouldReportProgress(JNIEnv* env, jobject /* this */,
                                                                    jlongArray state,
                                                                    jlong completed, jlong total) {
  return guarded(env, static_cast<jboolean>(JNI_FALSE), [&]() -> jboolean {
    jlong fields[3];
    env->GetLongArrayRegion(state, 0, 3, fields);
    turboimage::ProgressThrottle throttle{
        .lastPercent = fields[0], .lastReportedBytes = fields[1], .reportedCompletion = fields[2]};
    const bool report = throttle.shouldReport(completed, total);
    fields[0] = throttle.lastPercent;
    fields[1] = throttle.lastReportedBytes;
    fields[2] = throttle.reportedCompletion;
    env->SetLongArrayRegion(state, 0, 3, fields);
    return report ? JNI_TRUE : JNI_FALSE;
  });
}

// Same state; see ProgressThrottle::finish.
extern "C" JNIEXPORT jboolean JNICALL
Java_com_turboimage_core_TurboImageCore_nativeFinishProgress(JNIEnv* env, jobject /* this */,
                                                              jlongArray state, jlong total) {
  return guarded(env, static_cast<jboolean>(JNI_FALSE), [&]() -> jboolean {
    jlong fields[3];
    env->GetLongArrayRegion(state, 0, 3, fields);
    turboimage::ProgressThrottle throttle{
        .lastPercent = fields[0], .lastReportedBytes = fields[1], .reportedCompletion = fields[2]};
    const bool report = throttle.finish(total);
    fields[0] = throttle.lastPercent;
    fields[1] = throttle.lastReportedBytes;
    fields[2] = throttle.reportedCompletion;
    env->SetLongArrayRegion(state, 0, 3, fields);
    return report ? JNI_TRUE : JNI_FALSE;
  });
}

// -1 for unknown/empty, else a `turboimage::CachePolicy` value.
extern "C" JNIEXPORT jint JNICALL
Java_com_turboimage_core_TurboImageCore_nativeParseCachePolicy(JNIEnv* env, jobject /* this */,
                                                                jstring js) {
  return guarded(env, static_cast<jint>(-1), [&]() -> jint {
    const auto policy = turboimage::parseCachePolicy(toStdString(env, js));
    return policy ? static_cast<jint>(*policy) : -1;
  });
}

// Keys a `memoryCacheKey` placeholder may name, in lookup order.
extern "C" JNIEXPORT jobjectArray JNICALL
Java_com_turboimage_core_TurboImageCore_nativeMemoryCacheKeyCandidates(JNIEnv* env,
                                                                        jobject /* this */,
                                                                        jstring key) {
  return guarded(env, static_cast<jobjectArray>(nullptr), [&]() -> jobjectArray {
    const auto candidates = turboimage::memoryCacheKeyCandidates(toStdString(env, key));
    jclass stringClass = env->FindClass("java/lang/String");
    auto array = env->NewObjectArray(static_cast<jsize>(candidates.size()), stringClass, nullptr);
    if (array == nullptr) {
      throw JavaExceptionPending{};
    }
    for (std::size_t i = 0; i < candidates.size(); ++i) {
      jstring candidate = env->NewStringUTF(candidates[i].c_str());
      env->SetObjectArrayElement(array, static_cast<jsize>(i), candidate);
      env->DeleteLocalRef(candidate);
    }
    return array;
  });
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_turboimage_core_TurboImageCore_nativeLoadErrorCodeName(JNIEnv* env, jobject /* this */,
                                                                 jint code) {
  return guarded(env, static_cast<jstring>(nullptr), [&]() -> jstring {
    const auto name = turboimage::loadErrorCodeName(static_cast<turboimage::LoadErrorCode>(code));
    return env->NewStringUTF(std::string(name).c_str());
  });
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_turboimage_core_TurboImageCore_nativeCoreVersion(JNIEnv* env, jobject /* this */) {
  return guarded(env, static_cast<jstring>(nullptr), [&]() -> jstring {
    const auto version = turboimage::coreVersion();
    return env->NewStringUTF(std::string(version).c_str());
  });
}

// ---------------------------------------------------------------------------
// View lifecycle (turboimage/ViewLifecycle.h).
//
// State lives in a Kotlin LongArray(5): read, step, write back. Effects
// return as (kind, value) pairs, in order.

namespace {

constexpr jsize kLifecycleFields = 5;

// Runs `step` on the lifecycle held in `state` and stores the result.
template <typename Step>
auto withLifecycle(JNIEnv* env, jlongArray state, Step&& step) {
  jlong fields[kLifecycleFields];
  env->GetLongArrayRegion(state, 0, kLifecycleFields, fields);
  turboimage::ViewLifecycle lifecycle;
  lifecycle.showing = fields[0];
  lifecycle.inFlight = fields[1];
  lifecycle.lastToken = fields[2];
  lifecycle.placeholderGeneration = fields[3];
  lifecycle.upgrading = fields[4];
  auto result = step(lifecycle);
  fields[0] = lifecycle.showing;
  fields[1] = lifecycle.inFlight;
  fields[2] = lifecycle.lastToken;
  fields[3] = lifecycle.placeholderGeneration;
  fields[4] = lifecycle.upgrading;
  env->SetLongArrayRegion(state, 0, kLifecycleFields, fields);
  return result;
}

jlongArray toEffects(JNIEnv* env, const turboimage::LifecycleEffects& effects) {
  std::vector<jlong> flat;
  flat.reserve(effects.size() * 2);
  for (const auto& effect : effects) {
    flat.push_back(static_cast<jlong>(effect.kind));
    flat.push_back(effect.value);
  }
  jlongArray array = env->NewLongArray(static_cast<jsize>(flat.size()));
  if (array == nullptr) {
    throw JavaExceptionPending{};  // OutOfMemoryError from the JVM.
  }
  env->SetLongArrayRegion(array, 0, static_cast<jsize>(flat.size()), flat.data());
  return array;
}

turboimage::LifecycleProps toLifecycleProps(jint placeholder, jboolean showPlaceholderOnFailure) {
  return {.placeholder = static_cast<turboimage::PlaceholderKind>(placeholder),
          .showPlaceholderOnFailure = showPlaceholderOnFailure == JNI_TRUE};
}

}  // namespace

extern "C" JNIEXPORT jlongArray JNICALL
Java_com_turboimage_core_TurboImageCore_nativeLifecycleReload(
    JNIEnv* env, jobject /* this */, jlongArray state, jboolean recyclingKeyChanged,
    jboolean imageOnScreen, jboolean requestValid, jint placeholder,
    jboolean showPlaceholderOnFailure) {
  return guarded(env, static_cast<jlongArray>(nullptr), [&]() -> jlongArray {
    return toEffects(env, withLifecycle(env, state, [&](turboimage::ViewLifecycle& lifecycle) {
      return lifecycle.reload(recyclingKeyChanged == JNI_TRUE, imageOnScreen == JNI_TRUE,
                              requestValid == JNI_TRUE,
                              toLifecycleProps(placeholder, showPlaceholderOnFailure));
    }));
  });
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_turboimage_core_TurboImageCore_nativeLifecycleIsInFlight(JNIEnv* env, jobject /* this */,
                                                                   jlongArray state, jlong token) {
  return guarded(env, static_cast<jboolean>(JNI_FALSE), [&]() -> jboolean {
    return withLifecycle(env, state, [&](turboimage::ViewLifecycle& lifecycle) {
      return lifecycle.isInFlight(token);
    }) ? JNI_TRUE : JNI_FALSE;
  });
}

extern "C" JNIEXPORT jlongArray JNICALL
Java_com_turboimage_core_TurboImageCore_nativeLifecycleLoadSucceeded(JNIEnv* env,
                                                                      jobject /* this */,
                                                                      jlongArray state,
                                                                      jlong token) {
  return guarded(env, static_cast<jlongArray>(nullptr), [&]() -> jlongArray {
    return toEffects(env, withLifecycle(env, state, [&](turboimage::ViewLifecycle& lifecycle) {
      return lifecycle.loadSucceeded(token);
    }));
  });
}

extern "C" JNIEXPORT jlongArray JNICALL
Java_com_turboimage_core_TurboImageCore_nativeLifecycleLoadFailed(
    JNIEnv* env, jobject /* this */, jlongArray state, jlong token, jint placeholder,
    jboolean showPlaceholderOnFailure) {
  return guarded(env, static_cast<jlongArray>(nullptr), [&]() -> jlongArray {
    return toEffects(env, withLifecycle(env, state, [&](turboimage::ViewLifecycle& lifecycle) {
      return lifecycle.loadFailed(token, toLifecycleProps(placeholder, showPlaceholderOnFailure));
    }));
  });
}

extern "C" JNIEXPORT jlongArray JNICALL
Java_com_turboimage_core_TurboImageCore_nativeLifecycleApplyPlaceholder(
    JNIEnv* env, jobject /* this */, jlongArray state, jint placeholder,
    jboolean showPlaceholderOnFailure) {
  return guarded(env, static_cast<jlongArray>(nullptr), [&]() -> jlongArray {
    return toEffects(env, withLifecycle(env, state, [&](turboimage::ViewLifecycle& lifecycle) {
      return lifecycle.applyPlaceholder(toLifecycleProps(placeholder, showPlaceholderOnFailure));
    }));
  });
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_turboimage_core_TurboImageCore_nativeLifecyclePlaceholderDecoded(
    JNIEnv* env, jobject /* this */, jlongArray state, jlong generation, jint placeholder,
    jboolean showPlaceholderOnFailure) {
  return guarded(env, static_cast<jboolean>(JNI_FALSE), [&]() -> jboolean {
    return withLifecycle(env, state, [&](turboimage::ViewLifecycle& lifecycle) {
      return lifecycle.placeholderDecoded(generation,
                                          toLifecycleProps(placeholder, showPlaceholderOnFailure));
    }) ? JNI_TRUE : JNI_FALSE;
  });
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_turboimage_core_TurboImageCore_nativeLifecycleStartUpgrade(JNIEnv* env,
                                                                     jobject /* this */,
                                                                     jlongArray state) {
  return guarded(env, static_cast<jlong>(0), [&]() -> jlong {
    return withLifecycle(env, state,
                         [&](turboimage::ViewLifecycle& lifecycle) { return lifecycle.startUpgrade(); });
  });
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_turboimage_core_TurboImageCore_nativeLifecycleIsUpgrading(JNIEnv* env,
                                                                    jobject /* this */,
                                                                    jlongArray state, jlong token) {
  return guarded(env, static_cast<jboolean>(JNI_FALSE), [&]() -> jboolean {
    return withLifecycle(env, state, [&](turboimage::ViewLifecycle& lifecycle) {
      return lifecycle.isUpgrading(token);
    }) ? JNI_TRUE : JNI_FALSE;
  });
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_turboimage_core_TurboImageCore_nativeLifecycleUpgradeSucceeded(JNIEnv* env,
                                                                         jobject /* this */,
                                                                         jlongArray state,
                                                                         jlong token) {
  return guarded(env, static_cast<jboolean>(JNI_FALSE), [&]() -> jboolean {
    return withLifecycle(env, state, [&](turboimage::ViewLifecycle& lifecycle) {
      return lifecycle.upgradeSucceeded(token);
    }) ? JNI_TRUE : JNI_FALSE;
  });
}

extern "C" JNIEXPORT void JNICALL
Java_com_turboimage_core_TurboImageCore_nativeLifecycleUpgradeFailed(JNIEnv* env,
                                                                      jobject /* this */,
                                                                      jlongArray state,
                                                                      jlong token) {
  guarded(env, 0, [&]() -> int {
    withLifecycle(env, state, [&](turboimage::ViewLifecycle& lifecycle) {
      lifecycle.upgradeFailed(token);
      return 0;
    });
    return 0;
  });
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_turboimage_core_TurboImageCore_nativeNeedsLargerDecode(
    JNIEnv* env, jobject /* this */, jdouble decodedWidth, jdouble decodedHeight,
    jdouble loadedForWidth, jdouble loadedForHeight, jdouble nowWidth, jdouble nowHeight,
    jboolean fill) {
  return guarded(env, static_cast<jboolean>(JNI_FALSE), [&]() -> jboolean {
    return turboimage::needsLargerDecode({decodedWidth, decodedHeight},
                                         {loadedForWidth, loadedForHeight},
                                         {nowWidth, nowHeight}, fill == JNI_TRUE)
               ? JNI_TRUE
               : JNI_FALSE;
  });
}

extern "C" JNIEXPORT jlongArray JNICALL
Java_com_turboimage_core_TurboImageCore_nativeLifecycleDrop(JNIEnv* env, jobject /* this */,
                                                             jlongArray state) {
  return guarded(env, static_cast<jlongArray>(nullptr), [&]() -> jlongArray {
    return toEffects(env, withLifecycle(env, state, [&](turboimage::ViewLifecycle& lifecycle) {
      return lifecycle.drop();
    }));
  });
}

// (x, y, width, height); the box itself if the core throws.
extern "C" JNIEXPORT jdoubleArray JNICALL
Java_com_turboimage_core_TurboImageCore_nativePlaceImage(JNIEnv* env, jobject /* this */,
                                                          jdouble imageWidth, jdouble imageHeight,
                                                          jdouble boxWidth, jdouble boxHeight,
                                                          jint resizeMode, jdouble positionX,
                                                          jdouble positionY) {
  return guarded(env, static_cast<jdoubleArray>(nullptr), [&]() -> jdoubleArray {
    const auto placed = turboimage::placeImage(
        {imageWidth, imageHeight}, {boxWidth, boxHeight},
        static_cast<turboimage::ResizeMode>(resizeMode), {.x = positionX, .y = positionY});
    const jdouble values[4] = {placed.x, placed.y, placed.width, placed.height};
    jdoubleArray array = env->NewDoubleArray(4);
    if (array == nullptr) {
      throw JavaExceptionPending{};
    }
    env->SetDoubleArrayRegion(array, 0, 4, values);
    return array;
  });
}
