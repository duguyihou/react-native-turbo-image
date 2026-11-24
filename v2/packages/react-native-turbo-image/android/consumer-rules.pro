# Applied to the app's R8 pass. TurboImageJni.cpp builds these classes by
# name and constructor signature, so R8 must not rename or strip them.
-keep class com.turboimage.core.ResolvedRequest { <init>(java.lang.String, java.lang.String, boolean, boolean, boolean, boolean, boolean, java.lang.String, java.lang.String[], boolean, int, int, boolean, int, int, boolean); }
-keep class com.turboimage.core.ResolveFailure { <init>(int); }
-keep class com.turboimage.core.PlaceholderPixels { <init>(int, int, byte[]); }
-keepclasseswithmembernames,includedescriptorclasses class com.turboimage.core.TurboImageCore {
    native <methods>;
}
