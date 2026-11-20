// JNI bridge to the shared C++ core.
//
// Ownership: every jstring/jobject created here is a local reference owned by
// the JVM frame of the calling Kotlin method; nothing is cached across calls,
// so there are no global references to leak.
//
// Threading: `turboimage::resolveRequest` is pure (see ImageRequest.h), so
// this may be called from any thread. Kotlin calls it on the UI thread.
//
// Exceptions: a C++ exception that unwinds into the JVM aborts the process,
// so every entry point runs its body through `guarded` below, which turns it
// into a Java exception. The core reports bad input through return values;
// what can throw is allocation (a blur of a large bitmap needs several
// copies of it), and Kotlin can handle a Java OutOfMemoryError.

#include <jni.h>

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

// The integers Kotlin holds for the core's enums (TurboImageCore.kt:
// `CachePolicy`, `ResizeMode`, `LoadErrorCode`, `CoreAbi`). They cross this
// bridge as plain integers and are cast, so nothing else would notice a value
// renumbered on one side only. A failure here means: change TurboImageCore.kt
// to match, then this list.
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
TI_ASSERT_ABI(turboimage::LoadErrorCode::Unknown, 0);
TI_ASSERT_ABI(turboimage::LoadErrorCode::InvalidRequest, 1);
TI_ASSERT_ABI(turboimage::LoadErrorCode::NotCached, 2);
TI_ASSERT_ABI(turboimage::LoadErrorCode::Network, 3);
TI_ASSERT_ABI(turboimage::LoadErrorCode::Decode, 4);
TI_ASSERT_ABI(turboimage::DecodeSize::Kind::Original, 0);
TI_ASSERT_ABI(turboimage::DecodeSize::Kind::View, 1);
TI_ASSERT_ABI(turboimage::DecodeSize::Kind::Width, 2);
// `TurboImageCore.ViewLifecycle`: `PlaceholderKind` and `Effect.Kind`, the
// latter decoded by position, so its order is part of the ABI too.
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

// The throttle's state crosses as a LongArray(3), field by field (see
// nativeShouldReportProgress). A fourth field would silently not round-trip.
static_assert(sizeof(turboimage::ProgressThrottle) == 3 * sizeof(jlong),
              "ProgressThrottle no longer fits the LongArray(3) Kotlin keeps it in");
// Likewise the view lifecycle, a LongArray(4) (see `withLifecycle`).
static_assert(sizeof(turboimage::ViewLifecycle) == 4 * sizeof(jlong),
              "ViewLifecycle no longer fits the LongArray(4) Kotlin keeps it in");

// Thrown when a JNI call failed and left its own Java exception pending.
// No further JNI calls are allowed in that state, so this unwinds to
// `guarded`, which returns to the JVM and lets that exception propagate.
struct JavaExceptionPending {};

void throwJava(JNIEnv* env, const char* className, const char* message) {
  if (env->ExceptionCheck()) {
    return;  // Keep the first exception.
  }
  jclass exceptionClass = env->FindClass(className);
  if (exceptionClass != nullptr) {
    env->ThrowNew(exceptionClass, message);
  }
  // Otherwise FindClass left a NoClassDefFoundError pending, which will do.
}

// Runs `body` and returns its result. If it throws, a Java exception is left
// pending and `fallback` is returned (the JVM ignores the return value of a
// native method that raised).
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

// Kotlin passes colours as a jlong: the 0xAARRGGBB value, or -1 for "unset"
// (a jint cannot express both every ARGB value and "absent").
std::optional<std::uint32_t> toArgb(jlong value) {
  if (value < 0) {
    return std::nullopt;
  }
  return static_cast<std::uint32_t>(value & 0xffffffff);
}

// `String[]` of alternating names and values <-> core headers. A trailing
// odd element is ignored (Kotlin always passes pairs).
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

// Returns a `com.turboimage.core.ResolvedRequest`, or an
// `com.turboimage.core.ResolveFailure` when the request is invalid. Both
// classes are kept by consumer-rules.pro because R8 cannot see JNI usage.
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

// Wraps core pixels as `com.turboimage.core.PlaceholderPixels` (the class is
// just "premultiplied RGBA plus a size"; it predates processing).
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

}  // namespace

// Runs the processors a `processorKey` describes over premultiplied RGBA
// (an ARGB_8888 Bitmap's memory layout). Null when the key or buffer is
// invalid. Called on Coil's decode dispatcher; pure (Processing.h).
extern "C" JNIEXPORT jobject JNICALL
Java_com_turboimage_core_TurboImageCore_nativeProcess(JNIEnv* env, jobject /* this */,
                                                       jbyteArray rgba, jint width, jint height,
                                                       jstring processorKey) {
  return guarded(env, static_cast<jobject>(nullptr), [&]() -> jobject {
    turboimage::RgbaImage image{.width = width, .height = height, .pixels = {}};
    image.pixels.resize(static_cast<std::size_t>(env->GetArrayLength(rgba)));
    env->GetByteArrayRegion(rgba, 0, static_cast<jsize>(image.pixels.size()),
                            reinterpret_cast<jbyte*>(image.pixels.data()));
    const auto processed = turboimage::processImage(std::move(image), toStdString(env, processorKey));
    return processed ? toPixels(env, *processed) : nullptr;
  });
}

// Returns `com.turboimage.core.PlaceholderPixels` (premultiplied RGBA, the
// byte layout of an ARGB_8888 Bitmap), or null if neither hash decodes.
// Called on a background thread; the decode is pure (Placeholder.h).
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

// The throttle's state lives in a Kotlin LongArray(3) owned by the view, so
// the per-load state needs no native handle. Read, decide, write back.
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

// Same LongArray state as nativeShouldReportProgress; see
// ProgressThrottle::finish for why a success may need a final event.
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

// `String[]` of the keys a `memoryCacheKey` placeholder may name, in lookup
// order (see memoryCacheKeyCandidates in ImageRequest.h).
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
// The state lives in a Kotlin LongArray(4) owned by the view, as with the
// progress throttle: read, take one step, write back. Effects go back as a
// LongArray of (kind, value) pairs, in the order the view must carry them
// out.

namespace {

constexpr jsize kLifecycleFields = 4;

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
  auto result = step(lifecycle);
  fields[0] = lifecycle.showing;
  fields[1] = lifecycle.inFlight;
  fields[2] = lifecycle.lastToken;
  fields[3] = lifecycle.placeholderGeneration;
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

extern "C" JNIEXPORT jlongArray JNICALL
Java_com_turboimage_core_TurboImageCore_nativeLifecycleDrop(JNIEnv* env, jobject /* this */,
                                                             jlongArray state) {
  return guarded(env, static_cast<jlongArray>(nullptr), [&]() -> jlongArray {
    return toEffects(env, withLifecycle(env, state, [&](turboimage::ViewLifecycle& lifecycle) {
      return lifecycle.drop();
    }));
  });
}
