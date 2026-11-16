# Applied to the *app's* R8 pass.
#
# The JNI bridge (src/main/cpp/TurboImageJni.cpp) constructs these classes by
# name with fixed constructor signatures. R8 cannot see that, so without
# these rules a release build would rename or strip them and crash on the
# first image load. The example app's release build exercises this in CI.
-keep class com.turboimage.core.ResolvedRequest { <init>(java.lang.String, java.lang.String, boolean, boolean, boolean, boolean, boolean); }
-keep class com.turboimage.core.ResolveFailure { <init>(int); }
-keep class com.turboimage.core.PlaceholderPixels { <init>(int, int, byte[]); }
-keepclasseswithmembernames,includedescriptorclasses class com.turboimage.core.TurboImageCore {
    native <methods>;
}
