cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "media_codec")
project(${PROJECT_NAME} LANGUAGES CXX)
set(PLUGIN_NAME "media_codec_plugin")
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../native" "${CMAKE_CURRENT_BINARY_DIR}/core")
add_library(${PLUGIN_NAME} SHARED media_codec_plugin.cpp)
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_features(${PLUGIN_NAME} PUBLIC cxx_std_17)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL NOMINMAX)
target_include_directories(${PLUGIN_NAME} INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin media_codec_core d3d11 dxgi ole32 uuid)
# Rust staticlib 的 FRB 入口由最终插件 DLL 导出，不能另建解码器动态库。
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
  "${CMAKE_CURRENT_SOURCE_DIR}/../native/frb_symbols.list")
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/../native/frb_symbols.list" MEDIA_CODEC_FRB_SYMBOLS)
foreach(symbol IN LISTS MEDIA_CODEC_FRB_SYMBOLS)
  target_link_options(${PLUGIN_NAME} PRIVATE "/INCLUDE:${symbol}" "/EXPORT:${symbol}")
endforeach()
# Rust 与固定 C 静态库请求 release DLL CRT；Flutter Debug DLL 应同时从 wrapper 选择的 debug CRT 解析 C 分配接口，
# 避免同一模块导入两个 CRT 堆。
target_link_options(${PLUGIN_NAME} PRIVATE
  "$<$<AND:$<CXX_COMPILER_ID:MSVC>,$<CONFIG:Debug>>:/NODEFAULTLIB:MSVCRT>")
get_target_property(MC_FFMPEG_INCLUDE mc_ffmpeg INTERFACE_INCLUDE_DIRECTORIES)
get_filename_component(MC_FFMPEG_PREFIX "${MC_FFMPEG_INCLUDE}" DIRECTORY)
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/licenses")
file(GLOB_RECURSE MC_DEPENDENCY_NOTICES LIST_DIRECTORIES false
  "${MC_FFMPEG_PREFIX}/share/media_codec/*")
set(MC_BUNDLED_NOTICES "")
foreach(notice IN LISTS MC_DEPENDENCY_NOTICES)
  get_filename_component(notice_name "${notice}" NAME)
  set(notice_copy "${CMAKE_CURRENT_BINARY_DIR}/licenses/media_codec-${notice_name}")
  configure_file("${notice}" "${notice_copy}" COPYONLY)
  list(APPEND MC_BUNDLED_NOTICES "${notice_copy}")
endforeach()
set(media_codec_bundled_libraries "${MC_BUNDLED_NOTICES}" PARENT_SCOPE)

target_compile_options(${PLUGIN_NAME} PRIVATE "$<$<CXX_COMPILER_ID:MSVC>:/utf-8>")
