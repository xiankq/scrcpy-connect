# Flutter 提供目标平台与本次构建使用的 Dart SDK。
get_directory_property(adb_flutter_root DIRECTORY flutter DEFINITION FLUTTER_ROOT)
set(adb_platform "${FLUTTER_TARGET_PLATFORM}")
if(WIN32)
  set(adb_platform windows)
elseif(adb_platform STREQUAL "linux-x64")
  set(adb_platform linux)
endif()
install(CODE "
  execute_process(
    COMMAND \"${adb_flutter_root}/bin/cache/dart-sdk/bin/dart${CMAKE_EXECUTABLE_SUFFIX}\"
      \"${CMAKE_CURRENT_LIST_DIR}/prepare_adb.dart\" --platform ${adb_platform}
      --output \"${BUILD_BUNDLE_DIR}/platform-tools\"
    RESULT_VARIABLE adb_result
  )
  if(NOT adb_result STREQUAL \"0\")
    message(FATAL_ERROR \"Could not bundle ADB: \${adb_result}\")
  endif()
" COMPONENT Runtime)
