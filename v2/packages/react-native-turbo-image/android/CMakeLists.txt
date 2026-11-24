# Android native build: the shared C++ core + a thin JNI bridge.
#
# The core is pulled in from ../cpp, the *same* sources iOS compiles; there
# is no Android copy of the C++ (RFC rule 4). This library has no React
# Native dependency: Fabric glue on Android is Kotlin and uses the codegen
# output that the app's autolinking build compiles separately.

cmake_minimum_required(VERSION 3.22)
project(turboimage_android LANGUAGES CXX)

add_subdirectory(
  ${CMAKE_CURRENT_SOURCE_DIR}/../cpp
  ${CMAKE_CURRENT_BINARY_DIR}/turboimage_core
)

add_library(turboimage SHARED src/main/cpp/TurboImageJni.cpp)
# jnigraphics: AndroidBitmap_lockPixels, so processing reads and writes
# Bitmap pixels in place (nativeProcess).
target_link_libraries(turboimage PRIVATE turboimage_core jnigraphics)
target_compile_options(turboimage PRIVATE -Wall -Wextra)
# Same switch as the core (see ../cpp/CMakeLists.txt for why it is off in an
# app's build). Set from Gradle with `turboImage.warningsAsErrors=true`.
if(TURBOIMAGE_WARNINGS_AS_ERRORS)
  target_compile_options(turboimage PRIVATE -Werror)
endif()
# 16 KB page-size alignment, required for Play on Android 15+ devices.
target_link_options(turboimage PRIVATE "-Wl,-z,max-page-size=16384")
