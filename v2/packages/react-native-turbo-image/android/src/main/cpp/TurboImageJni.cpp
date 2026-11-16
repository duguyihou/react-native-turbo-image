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

extern "C" JNIEXPORT jstring JNICALL
Java_com_turboimage_core_TurboImageCore_nativeCoreVersion(JNIEnv* env, jobject /* this */) {
  const auto version = turboimage::coreVersion();
  return env->NewStringUTF(std::string(version).c_str());
}
