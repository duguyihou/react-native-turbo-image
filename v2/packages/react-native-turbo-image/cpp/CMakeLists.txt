# TurboImage C++ core.
#
# This is the one build description for the shared core. It is consumed in
# three ways, and must stay valid for all of them:
#
#   1. Standalone (host machine, CI): builds the library + GoogleTest suite.
#        cmake -S cpp -B build/core -DTURBOIMAGE_BUILD_TESTS=ON
#   2. Android: `android/CMakeLists.txt` pulls it in with add_subdirectory()
#      and links it into the JNI library. Tests are off there.
#   3. iOS does NOT use CMake. Package.swift and the podspec compile the same
#      `src/` and `include/` trees directly. If you add a source file here,
#      nothing else needs to change on iOS because both manifests glob
#      `cpp/src`; but if you add a compile definition, mirror it in
#      Package.swift *and* TurboImage.podspec (RFC rule 6).

cmake_minimum_required(VERSION 3.22)
project(TurboImageCore VERSION 2.0.0 LANGUAGES CXX)

option(TURBOIMAGE_BUILD_TESTS "Build the GoogleTest suite" OFF)

add_library(turboimage_core STATIC
  src/ImageRequest.cpp
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
  target_compile_options(turboimage_core PRIVATE -Wall -Wextra -Wpedantic -Werror)
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
  add_executable(turboimage_core_tests tests/ImageRequestTest.cpp)
  target_link_libraries(turboimage_core_tests PRIVATE turboimage_core GTest::gtest_main)
  include(GoogleTest)
  gtest_discover_tests(turboimage_core_tests)
endif()
