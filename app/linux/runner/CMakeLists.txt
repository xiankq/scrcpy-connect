cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# 定义应用目标；修改名称须改顶层 CMakeLists.txt 的 BINARY_NAME，否则 flutter run 失效。新源文件在此加入。
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# 应用标准构建设置；有不同要求时可移除。
apply_standard_settings(${BINARY_NAME})

# 添加应用 ID 的预处理定义。
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# 添加依赖库，应用专用依赖也在此加入。
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
