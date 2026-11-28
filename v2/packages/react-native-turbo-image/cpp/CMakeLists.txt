# TurboImage C++ core.
#
# Used standalone for tests (cmake -S cpp -B build/core
# -DTURBOIMAGE_BUILD_TESTS=ON) and by android/CMakeLists.txt. iOS compiles
# the same sources from Package.swift and the podspec (both glob `cpp/src`);
# mirror any compile definition there too (RFC rule 6).

cmake_minimum_required(VERSION 3.22)
project(TurboImageCore VERSION 2.0.0 LANGUAGES CXX)

option(TURBOIMAGE_BUILD_TESTS "Build the GoogleTest suite" OFF)
# Off by default so a newer NDK's warnings cannot break an app's build; this
# repo turns it on everywhere it builds.
option(TURBOIMAGE_WARNINGS_AS_ERRORS "Treat compiler warnings as errors" OFF)
# For core test runs. Directory-wide and before GoogleTest, so everything
# linked is instrumented alike.
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
  src/ViewLifecycle.cpp
)
target_include_directories(turboimage_core PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}/include
)
# Public: the headers use designated initialisers and defaulted comparisons.
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
  # Pinned (RFC rule 7).
  FetchContent_Declare(
    googletest
    URL https://github.com/google/googletest/archive/refs/tags/v1.17.0.tar.gz
    # Tags can move; the hash pins the bytes.
    URL_HASH SHA256=65fab701d9829d38cb77c14acdc431d2108bfdbf8979e40eb8ae567edf10b27c
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
    tests/ViewLifecycleTest.cpp
  )
  # PlaceholderGoldens.inc lives next to the tests.
  target_include_directories(turboimage_core_tests PRIVATE tests)
  target_link_libraries(turboimage_core_tests PRIVATE turboimage_core GTest::gtest_main)
  if(ANDROID)
    # 16 KB page devices (Android 15+) cannot load 4 KB-aligned ELFs.
    target_link_options(turboimage_core_tests PRIVATE "-Wl,-z,max-page-size=16384")
  endif()
  include(GoogleTest)
  # PRE_TEST: discover at ctest time so the suite can be cross-compiled and
  # run on a device.
  gtest_discover_tests(turboimage_core_tests DISCOVERY_MODE PRE_TEST)
endif()
