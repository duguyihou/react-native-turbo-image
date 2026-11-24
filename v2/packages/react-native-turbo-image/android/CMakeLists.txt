# Android native build: the shared C++ core (../cpp, same sources as iOS,
# RFC rule 4) plus a thin JNI bridge. No React Native dependency here.

cmake_minimum_required(VERSION 3.22)
project(turboimage_android LANGUAGES CXX)

add_subdirectory(
  ${CMAKE_CURRENT_SOURCE_DIR}/../cpp
  ${CMAKE_CURRENT_BINARY_DIR}/turboimage_core
)

add_library(turboimage SHARED src/main/cpp/TurboImageJni.cpp)
# jnigraphics: lock Bitmap pixels for in-place processing.
target_link_libraries(turboimage PRIVATE turboimage_core jnigraphics)
target_compile_options(turboimage PRIVATE -Wall -Wextra)
# Same switch as the core; set from Gradle with
# `turboImage.warningsAsErrors=true`.
if(TURBOIMAGE_WARNINGS_AS_ERRORS)
  target_compile_options(turboimage PRIVATE -Werror)
endif()
# 16 KB page alignment, required for Android 15+.
target_link_options(turboimage PRIVATE "-Wl,-z,max-page-size=16384")
