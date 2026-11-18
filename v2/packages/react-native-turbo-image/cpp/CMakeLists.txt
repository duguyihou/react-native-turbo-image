# TurboImage C++ core.
#
# This is the one build description for the shared core. It is consumed in
# three ways, and must stay valid for all of them:
#
#   1. Standalone (host machine, CI): builds the library + GoogleTest suite.
#        cmake -S cpp -B build/core -DTURBOIMAGE_BUILD_TESTS=ON
#   2. Android: `android/CMakeLists.txt` pulls it in with add_subdirectory()
#      and links it into the JNI library. Tests are off there, and so is
#      TURBOIMAGE_WARNINGS_AS_ERRORS unless the app asks for it.
#   3. iOS does NOT use CMake. Package.swift and the podspec compile the same
#      `src/` and `include/` trees directly. If you add a source file here,
#      nothing else needs to change on iOS because both manifests glob
#      `cpp/src`; but if you add a compile definition, mirror it in
#      Package.swift *and* TurboImage.podspec (RFC rule 6).

cmake_minimum_required(VERSION 3.22)
project(TurboImageCore VERSION 2.0.0 LANGUAGES CXX)

option(TURBOIMAGE_BUILD_TESTS "Build the GoogleTest suite" OFF)
# Off by default because apps compile this with their own NDK: a compiler
# newer than the ones this was written against may warn about code that is
# fine, and that must not break an app's build. This repository turns it on
# everywhere it builds the core (the core tests, the example app, CI).
option(TURBOIMAGE_WARNINGS_AS_ERRORS "Treat compiler warnings as errors" OFF)
# For the core's own test runs (CI has a leg for it). Directory-wide, and
# set before GoogleTest is fetched, so the test binary and everything linked
# into it are instrumented alike.
option(TURBOIMAGE_SANITIZE "Build with AddressSanitizer and UBSan" OFF)
if(TURBOIMAGE_SANITIZE)
  add_compile_options(-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer)
  add_link_options(-fsanitize=address,undefined)
endif()

add_library(turboimage_core STATIC
  src/ImageRequest.cpp
  src/Placeholder.cpp
  src/Processing.cpp
  src/Progress.cpp
)
target_include_directories(turboimage_core PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}/include
)
# C++20 is a public requirement: the headers use designated initialisers and
# defaulted comparison operators.
target_compile_features(turboimage_core PUBLIC cxx_std_20)
set_target_properties(turboimage_core PROPERTIES
  CXX_EXTENSIONS OFF
  POSITION_INDEPENDENT_CODE ON   # linked into an Android .so
)
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
  target_compile_options(turboimage_core PRIVATE -Wall -Wextra -Wpedantic)
  if(TURBOIMAGE_WARNINGS_AS_ERRORS)
    target_compile_options(turboimage_core PRIVATE -Werror)
  endif()
endif()

if(TURBOIMAGE_BUILD_TESTS)
  include(FetchContent)
  # Pinned (RFC rule 7). Bumping this is a deliberate, reviewed change.
  FetchContent_Declare(
    googletest
    URL https://github.com/google/googletest/archive/refs/tags/v1.17.0.tar.gz
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  )
  set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)
  FetchContent_MakeAvailable(googletest)

  enable_testing()
  add_executable(turboimage_core_tests
    tests/ImageRequestTest.cpp
    tests/PlaceholderTest.cpp
    tests/ProcessingTest.cpp
    tests/ProgressTest.cpp
  )
  # PlaceholderGoldens.inc lives next to the tests.
  target_include_directories(turboimage_core_tests PRIVATE tests)
  target_link_libraries(turboimage_core_tests PRIVATE turboimage_core GTest::gtest_main)
  if(ANDROID)
    # Devices with 16 KB pages (Android 15+, incl. current emulator images)
    # cannot load an ELF with 4 KB segment alignment; it segfaults before
    # main. Same flag as the app's libturboimage.so (android/CMakeLists.txt).
    target_link_options(turboimage_core_tests PRIVATE "-Wl,-z,max-page-size=16384")
  endif()
  include(GoogleTest)
  # PRE_TEST: discover at ctest time, not build time, so the suite can be
  # cross-compiled (Android NDK) and run on a device with adb.
  gtest_discover_tests(turboimage_core_tests DISCOVERY_MODE PRE_TEST)
endif()
