# The application installs the exact official executable selected by its lock.
function(flutter_adb_resolve_flutter_root)
  include("${CMAKE_CURRENT_SOURCE_DIR}/flutter/ephemeral/generated_config.cmake")
  set(FLUTTER_ADB_FLUTTER_ROOT "${FLUTTER_ROOT}" PARENT_SCOPE)
endfunction()
flutter_adb_resolve_flutter_root()
get_filename_component(FLUTTER_ADB_PACKAGE "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
get_filename_component(FLUTTER_ADB_WORKSPACE "${FLUTTER_ADB_PACKAGE}/../.." ABSOLUTE)
if(WIN32)
  set(FLUTTER_ADB_PLATFORM windows)
  set(FLUTTER_ADB_DART "${FLUTTER_ADB_FLUTTER_ROOT}/bin/cache/dart-sdk/bin/dart.exe")
else()
  set(FLUTTER_ADB_PLATFORM linux)
  set(FLUTTER_ADB_DART "${FLUTTER_ADB_FLUTTER_ROOT}/bin/cache/dart-sdk/bin/dart")
endif()
set(FLUTTER_ADB_DIRECTORY "${FLUTTER_ADB_WORKSPACE}/.dart_tool/flutter_adb/${FLUTTER_ADB_PLATFORM}")
execute_process(COMMAND "${FLUTTER_ADB_DART}" "${FLUTTER_ADB_PACKAGE}/tool/prepare_adb.dart"
  --platform "${FLUTTER_ADB_PLATFORM}" --output "${FLUTTER_ADB_DIRECTORY}"
  WORKING_DIRECTORY "${FLUTTER_ADB_WORKSPACE}"
  RESULT_VARIABLE FLUTTER_ADB_PREPARE_RESULT)
if(NOT FLUTTER_ADB_PREPARE_RESULT EQUAL 0)
  message(FATAL_ERROR "Pinned official ADB preparation failed")
endif()
install(DIRECTORY "${FLUTTER_ADB_DIRECTORY}/"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/adb" USE_SOURCE_PERMISSIONS COMPONENT Runtime)
