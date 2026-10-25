# 应用安装锁文件指定的精确官方可执行产物。
function(adb_resolve_flutter_root)
  include("${CMAKE_CURRENT_SOURCE_DIR}/flutter/ephemeral/generated_config.cmake")
  set(ADB_FLUTTER_ROOT "${FLUTTER_ROOT}" PARENT_SCOPE)
endfunction()
adb_resolve_flutter_root()
get_filename_component(ADB_PACKAGE "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
get_filename_component(ADB_WORKSPACE "${ADB_PACKAGE}/../.." ABSOLUTE)
if(WIN32)
  set(ADB_PLATFORM windows)
  set(ADB_DART "${ADB_FLUTTER_ROOT}/bin/cache/dart-sdk/bin/dart.exe")
else()
  set(ADB_PLATFORM linux)
  set(ADB_DART "${ADB_FLUTTER_ROOT}/bin/cache/dart-sdk/bin/dart")
endif()
set(ADB_DIRECTORY "${ADB_WORKSPACE}/.dart_tool/adb/${ADB_PLATFORM}")
execute_process(COMMAND "${ADB_DART}" "${ADB_PACKAGE}/tool/prepare_adb.dart"
  --platform "${ADB_PLATFORM}" --output "${ADB_DIRECTORY}"
  WORKING_DIRECTORY "${ADB_WORKSPACE}"
  RESULT_VARIABLE ADB_PREPARE_RESULT)
if(NOT ADB_PREPARE_RESULT EQUAL 0)
  message(FATAL_ERROR "Pinned official ADB preparation failed")
endif()
install(DIRECTORY "${ADB_DIRECTORY}/"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/adb" USE_SOURCE_PERMISSIONS COMPONENT Runtime)
