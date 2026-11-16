// JNI bridge to the shared C++ core.
//
// Ownership: every jstring/jobject created here is a local reference owned by
// the JVM frame of the calling Kotlin method; nothing is cached across calls,
// so there are no global references to leak.
//
// Threading: `turboimage::resolveRequest` is pure (see ImageRequest.h), so
// this may be called from any thread. Kotlin calls it on the UI thread.

#include <jni.h>

#include <optional>
#include <string>

#include "turboimage/ImageRequest.h"
#include "turboimage/Placeholder.h"
#include "turboimage/Progress.h"

namespace {

std::string toStdString(JNIEnv* env, jstring value) {
  if (value == nullptr) {
    return {};
  }
  const char* chars = env->GetStringUTFChars(value, nullptr);
  std::string out(chars);
  env->ReleaseStringUTFChars(value, chars);
  return out;
}

}  // namespace

// Returns a `com.turboimage.core.ResolvedRequest`, or an
// `com.turboimage.core.ResolveFailure` when the request is invalid. Both
// classes are kept by consumer-rules.pro because R8 cannot see JNI usage.
extern "C" JNIEXPORT jobject JNICALL
Java_com_turboimage_core_TurboImageCore_nativeResolve(JNIEnv* env, jobject /* this */,
                                                       jstring uri, jstring cacheKey,
                                                       jint cachePolicy) {
  const auto key = toStdString(env, cacheKey);
  const auto result = turboimage::resolveRequest({
      .uri = toStdString(env, uri),
      .cacheKey = key.empty() ? std::nullopt : std::optional<std::string>(key),
      .cachePolicy = static_cast<turboimage::CachePolicy>(cachePolicy),
  });

  if (!result.ok()) {
    jclass failureClass = env->FindClass("com/turboimage/core/ResolveFailure");
    jmethodID ctor = env->GetMethodID(failureClass, "<init>", "(I)V");
    return env->NewObject(failureClass, ctor, static_cast<jint>(result.error));
  }

  const auto& r = *result.request;
  jclass resolvedClass = env->FindClass("com/turboimage/core/ResolvedRequest");
  jmethodID ctor =
      env->GetMethodID(resolvedClass, "<init>", "(Ljava/lang/String;Ljava/lang/String;ZZZZZ)V");
  return env->NewObject(resolvedClass, ctor, env->NewStringUTF(r.url.c_str()),
                        env->NewStringUTF(r.cacheKey.c_str()), r.memory.read, r.memory.write,
                        r.disk.read, r.disk.write, r.allowNetwork);
}

// Returns `com.turboimage.core.PlaceholderPixels` (premultiplied RGBA, the
// byte layout of an ARGB_8888 Bitmap), or null if neither hash decodes.
// Called on a background thread; the decode is pure (Placeholder.h).
extern "C" JNIEXPORT jobject JNICALL
Java_com_turboimage_core_TurboImageCore_nativeDecodePlaceholder(JNIEnv* env, jobject /* this */,
                                                                 jstring blurhash,
                                                                 jstring thumbhash) {
  const auto image =
      turboimage::decodePlaceholder(toStdString(env, blurhash), toStdString(env, thumbhash));
  if (!image) {
    return nullptr;
  }
  const auto size = static_cast<jsize>(image->pixels.size());
  jbyteArray bytes = env->NewByteArray(size);
  if (bytes == nullptr) {
    return nullptr;  // OutOfMemoryError is pending; let it propagate.
  }
  env->SetByteArrayRegion(bytes, 0, size, reinterpret_cast<const jbyte*>(image->pixels.data()));
  jclass pixelsClass = env->FindClass("com/turboimage/core/PlaceholderPixels");
  jmethodID ctor = env->GetMethodID(pixelsClass, "<init>", "(II[B)V");
  return env->NewObject(pixelsClass, ctor, image->width, image->height, bytes);
}

// The throttle's state lives in a Kotlin LongArray(3) owned by the view, so
// the per-load state needs no native handle. Read, decide, write back.
extern "C" JNIEXPORT jboolean JNICALL
Java_com_turboimage_core_TurboImageCore_nativeShouldReportProgress(JNIEnv* env, jobject /* this */,
                                                                    jlongArray state,
                                                                    jlong completed, jlong total) {
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
}

// Same LongArray state as nativeShouldReportProgress; see
// ProgressThrottle::finish for why a success may need a final event.
extern "C" JNIEXPORT jboolean JNICALL
Java_com_turboimage_core_TurboImageCore_nativeFinishProgress(JNIEnv* env, jobject /* this */,
                                                              jlongArray state, jlong total) {
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
}

// -1 for unknown/empty, else a `turboimage::CachePolicy` value.
extern "C" JNIEXPORT jint JNICALL
Java_com_turboimage_core_TurboImageCore_nativeParseCachePolicy(JNIEnv* env, jobject /* this */,
                                                                jstring js) {
  const auto policy = turboimage::parseCachePolicy(toStdString(env, js));
  return policy ? static_cast<jint>(*policy) : -1;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_turboimage_core_TurboImageCore_nativeCanonicalCacheKey(JNIEnv* env, jobject /* this */,
                                                                 jstring uri) {
  return env->NewStringUTF(turboimage::canonicalCacheKey(toStdString(env, uri)).c_str());
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_turboimage_core_TurboImageCore_nativeLoadErrorCodeName(JNIEnv* env, jobject /* this */,
                                                                 jint code) {
  const auto name = turboimage::loadErrorCodeName(static_cast<turboimage::LoadErrorCode>(code));
  return env->NewStringUTF(std::string(name).c_str());
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_turboimage_core_TurboImageCore_nativeCoreVersion(JNIEnv* env, jobject /* this */) {
  const auto version = turboimage::coreVersion();
  return env->NewStringUTF(std::string(version).c_str());
}
