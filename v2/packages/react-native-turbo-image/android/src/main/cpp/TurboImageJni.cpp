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

namespace {

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
                         "(Ljava/lang/String;Ljava/lang/String;ZZZZZLjava/lang/String;[Ljava/lang/String;ZIIZ)V");
    return env->NewObject(resolvedClass, ctor, env->NewStringUTF(r.url.c_str()),
                          env->NewStringUTF(r.cacheKey.c_str()), r.memory.read, r.memory.write,
                          r.disk.read, r.disk.write, r.allowNetwork,
                          env->NewStringUTF(r.processorKey.c_str()), fromHeaders(env, r.headers),
                          r.httpCache, static_cast<jint>(r.decode.kind),
                          static_cast<jint>(r.decode.width), r.decode.fill);
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
