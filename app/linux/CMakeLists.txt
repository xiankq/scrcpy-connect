# 项目级配置。
cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# 应用可执行文件名称，同时决定磁盘上的文件名。
set(BINARY_NAME "interconnect")
set(APP_DISPLAY_NAME "邻接")
# 应用唯一 GTK 标识，参考 https://wiki.gnome.org/HowDoI/ChooseApplicationID。
set(APPLICATION_ID "dev.scrcpyconnect.scrcpy_connect")

# 明确启用现代 CMake 行为，避免新版 CMake 警告。
cmake_policy(SET CMP0063 NEW)

# 从可执行文件相对路径 lib/ 加载随包库。
set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# 交叉编译的根文件系统。
if(FLUTTER_TARGET_PLATFORM_SYSROOT)
  set(CMAKE_SYSROOT ${FLUTTER_TARGET_PLATFORM_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH ${CMAKE_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
  set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
endif()

# 定义构建配置选项。
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Debug" CACHE
    STRING "Flutter build mode" FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
    "Debug" "Profile" "Release")
endif()

# 多数目标共用的编译设置，插件默认也调用此函数；新增选项优先加到具体目标。
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_14)
  target_compile_options(${TARGET} PRIVATE -Wall -Werror)
  target_compile_options(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")
  target_compile_definitions(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")
endfunction()

# Flutter 库与工具构建规则。
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# 系统级依赖。
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)

# 应用构建入口见 runner/CMakeLists.txt。
add_subdirectory("runner")

# 运行 Flutter 工具负责的构建步骤，必须保留。
add_dependencies(${BINARY_NAME} flutter_assemble)

# 仅安装生成的包内可执行文件拥有正确资源相对路径；将未打包副本放入子目录，避免误运行。
set_target_properties(${BINARY_NAME}
  PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/intermediates_do_not_run"
)


# 生成的插件构建规则，负责构建插件并加入应用。
include(flutter/generated_plugins.cmake)


# Flutter 的安装目标只生成可迁移包。系统安装由发行版安装包负责。
set(BUILD_BUNDLE_DIR "${PROJECT_BINARY_DIR}/bundle")
set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}")

# 每次开始时清理构建包目录。
install(CODE "
  file(REMOVE_RECURSE \"${BUILD_BUNDLE_DIR}/\")
  " COMPONENT Runtime)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)
include("${CMAKE_CURRENT_SOURCE_DIR}/../../packages/adb/tool/bundle_adb.cmake")

configure_file(interconnect.desktop.in "${CMAKE_CURRENT_BINARY_DIR}/${APPLICATION_ID}.desktop" @ONLY)
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/${APPLICATION_ID}.desktop"
  DESTINATION "share/applications" COMPONENT Runtime)
install(FILES interconnect.metainfo.xml DESTINATION "share/metainfo"
  RENAME "${APPLICATION_ID}.metainfo.xml" COMPONENT Runtime)
install(FILES runner/interconnect.svg
  DESTINATION "share/icons/hicolor/scalable/apps"
  RENAME "${APPLICATION_ID}.svg" COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})
  install(FILES "${bundled_library}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endforeach(bundled_library)

# 复制全部包的 build.dart 提供的原生产物。
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/linux/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# 每次构建完整复制资源目录，避免保留上次安装的旧文件。
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# 仅非调试构建安装 AOT 库。
if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
  install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()
