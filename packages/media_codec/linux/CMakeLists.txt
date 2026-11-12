cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "media_codec")
project(${PROJECT_NAME} LANGUAGES CXX)
set(PLUGIN_NAME "media_codec_plugin")
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../native" "${CMAKE_CURRENT_BINARY_DIR}/core")
find_package(PkgConfig REQUIRED)
pkg_check_modules(MC_EPOXY REQUIRED IMPORTED_TARGET epoxy)
add_library(${PLUGIN_NAME} SHARED media_codec_plugin.cc gpu_texture.cc)
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden
  BUILD_WITH_INSTALL_RPATH TRUE INSTALL_RPATH "$ORIGIN")
target_compile_features(${PLUGIN_NAME} PUBLIC cxx_std_17)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
# 导出同一 Rust 核心的 FRB 入口，其余静态依赖保持隐藏。
target_link_options(${PLUGIN_NAME} PRIVATE
  "-Wl,-Bsymbolic-functions"
  "-Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/media_codec.map")
set_property(TARGET ${PLUGIN_NAME} APPEND PROPERTY LINK_DEPENDS
  "${CMAKE_CURRENT_SOURCE_DIR}/media_codec.map")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
  "${CMAKE_CURRENT_SOURCE_DIR}/../native/frb_symbols.list")
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/../native/frb_symbols.list" MEDIA_CODEC_FRB_SYMBOLS)
foreach(symbol IN LISTS MEDIA_CODEC_FRB_SYMBOLS)
  target_link_options(${PLUGIN_NAME} PRIVATE "-Wl,--undefined=${symbol}")
endforeach()
target_include_directories(${PLUGIN_NAME} INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter PkgConfig::GTK PkgConfig::MC_EPOXY media_codec_core)
# FFmpeg 的 VA-API 对象具有 ELF 依赖，即使运行时回退为 CUDA 或软件解码也不例外。
# 随插件分发小型 VA 调度库，使目标机器无需预装 libva；GPU 专属 VA 驱动、libcuda 和 libnvcuvid 仍由驱动提供。
pkg_check_modules(MC_VA_RUNTIME REQUIRED libva libva-drm)
find_program(MC_READELF NAMES readelf llvm-readelf REQUIRED)
set(MC_RUNTIME_DIR "${CMAKE_CURRENT_BINARY_DIR}/runtime")
file(MAKE_DIRECTORY "${MC_RUNTIME_DIR}")
set(MC_BUNDLED_RUNTIME "")
foreach(component va va-drm)
  find_library(MC_RUNTIME_${component} NAMES ${component}
    HINTS ${MC_VA_RUNTIME_LIBRARY_DIRS} REQUIRED)
  get_filename_component(real_library "${MC_RUNTIME_${component}}" REALPATH)
  execute_process(COMMAND "${MC_READELF}" -d "${real_library}"
    RESULT_VARIABLE readelf_result OUTPUT_VARIABLE dynamic_section)
  if(NOT readelf_result EQUAL 0)
    message(FATAL_ERROR "Cannot inspect runtime library ${real_library}")
  endif()
  string(REGEX MATCH "\\(SONAME\\)[^\n]*\\[([^]]+)\\]" soname_match "${dynamic_section}")
  if(NOT CMAKE_MATCH_1)
    message(FATAL_ERROR "VA runtime library lacks ELF SONAME: ${real_library}")
  endif()
  set(runtime_copy "${MC_RUNTIME_DIR}/${CMAKE_MATCH_1}")
  configure_file("${real_library}" "${runtime_copy}" COPYONLY)
  list(APPEND MC_BUNDLED_RUNTIME "${runtime_copy}")
endforeach()

set(MEDIA_CODEC_VA_LICENSE "" CACHE FILEPATH "libva distribution copyright/license file")
if(NOT MEDIA_CODEC_VA_LICENSE)
  find_file(MEDIA_CODEC_VA_DISTRIBUTION_LICENSE NAMES copyright COPYING LICENSE
    PATHS "$ENV{PKG_CONFIG_SYSROOT_DIR}/usr/share/doc/libva2"
      /usr/share/doc/libva2 /usr/share/licenses/libva /usr/share/doc/libva
    NO_DEFAULT_PATH)
  set(MEDIA_CODEC_VA_LICENSE "${MEDIA_CODEC_VA_DISTRIBUTION_LICENSE}")
endif()
if(NOT EXISTS "${MEDIA_CODEC_VA_LICENSE}")
  message(FATAL_ERROR "Bundling libva requires its distribution license; set MEDIA_CODEC_VA_LICENSE")
endif()
configure_file("${MEDIA_CODEC_VA_LICENSE}" "${MC_RUNTIME_DIR}/media_codec-libva-COPYRIGHT" COPYONLY)
list(APPEND MC_BUNDLED_RUNTIME "${MC_RUNTIME_DIR}/media_codec-libva-COPYRIGHT")
get_target_property(MC_FFMPEG_INCLUDE mc_ffmpeg INTERFACE_INCLUDE_DIRECTORIES)
get_filename_component(MC_FFMPEG_PREFIX "${MC_FFMPEG_INCLUDE}" DIRECTORY)
file(GLOB_RECURSE MC_DEPENDENCY_NOTICES LIST_DIRECTORIES false
  "${MC_FFMPEG_PREFIX}/share/media_codec/*")
foreach(notice IN LISTS MC_DEPENDENCY_NOTICES)
  get_filename_component(notice_name "${notice}" NAME)
  configure_file("${notice}" "${MC_RUNTIME_DIR}/media_codec-${notice_name}" COPYONLY)
  list(APPEND MC_BUNDLED_RUNTIME "${MC_RUNTIME_DIR}/media_codec-${notice_name}")
endforeach()
# 使用 Flutter 的随包文件安装，它在应用清理旧 bundle 后执行；插件局部 install() 规则会在清理前执行。
set(media_codec_bundled_libraries "${MC_BUNDLED_RUNTIME}" PARENT_SCOPE)
