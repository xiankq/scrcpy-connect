cmake_minimum_required(VERSION 3.18)
project(media_codec_android LANGUAGES C CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
add_subdirectory(../native native)
add_library(media_codec_plugin SHARED src/main/cpp/media_codec_jni.cpp)
target_link_libraries(media_codec_plugin PRIVATE media_codec_core android log)
target_compile_options(media_codec_plugin PRIVATE -Wall -Wextra)
target_link_options(media_codec_plugin PRIVATE
  "-Wl,-Bsymbolic-functions"
  "-Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/media_codec.map")
set_property(TARGET media_codec_plugin APPEND PROPERTY LINK_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/media_codec.map")

# Dart 直接查找的 FRB 入口必须从同一 Rust 静态库抽取并保留。
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
  "${CMAKE_CURRENT_SOURCE_DIR}/../native/frb_symbols.list")
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/../native/frb_symbols.list" MEDIA_CODEC_FRB_SYMBOLS)
foreach(symbol IN LISTS MEDIA_CODEC_FRB_SYMBOLS)
  target_link_options(media_codec_plugin PRIVATE "-Wl,--undefined=${symbol}")
endforeach()
