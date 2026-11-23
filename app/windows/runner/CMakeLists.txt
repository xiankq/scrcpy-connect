cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# 定义应用目标；修改名称须改顶层 CMakeLists.txt 的 BINARY_NAME，否则 flutter run 失效。新源文件在此加入。
add_executable(${BINARY_NAME} WIN32
  "desktop_window_chrome.cpp"
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# 应用标准构建设置；有不同要求时可移除。
apply_standard_settings(${BINARY_NAME})
target_compile_features(${BINARY_NAME} PRIVATE cxx_std_20)

# 添加构建版本的预处理定义。
target_compile_definitions(${BINARY_NAME} PRIVATE "APP_EXECUTABLE_NAME=\"${BINARY_NAME}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# 禁用与 C++ 标准库函数冲突的 Windows 宏。
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# 添加依赖库和包含目录，应用专用依赖也在此加入。
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib" "comctl32.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# 运行 Flutter 工具负责的构建步骤，必须保留。
add_dependencies(${BINARY_NAME} flutter_assemble)
