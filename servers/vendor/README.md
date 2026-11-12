# scrcpy server

固定 [scrcpy 5.0.1](https://github.com/Genymobile/scrcpy/tree/a60891aea193d92e7e5c3942700eca63f9d19a5f)，Java/协议保持上游，仅启用 core-library desugaring 支持 API 21–23。原始 release 来源、构建输入和摘要见 [manifest](manifest.json)。

```sh
dart --disable-dart-dev servers/build.dart --check vendor
dart --disable-dart-dev servers/build.dart --rebuild vendor
dart --disable-dart-dev servers/build.dart --update vendor assets
```

根目录先 `flutter pub get`。`--check` 离线核对；`--rebuild` 临时编译比较；`--update` 更新受控产物。重建需要 JDK 21、SDK 36、build-tools 37.0.0。`JAVA_HOME/ANDROID_HOME` 选择工具链；`--source` 接固定摘要的本地归档，`--gradle` 选匹配安装，`--offline` 使用依赖缓存。

## 许可证与对应源码

- scrcpy：[Apache-2.0](LICENSE-scrcpy)。
- desugar_jdk_libs 2.1.5：[GPLv2+Classpath Exception](LICENSE-desugar_jdk_libs)、[ASSEMBLY_EXCEPTION](ASSEMBLY_EXCEPTION-desugar_jdk_libs)、[附加声明](ADDITIONAL_LICENSE_INFO-desugar_jdk_libs)。固定提交 [73170c3](https://github.com/google/desugar_jdk_libs/tree/73170c345e6a762fc6a1f0301bb15218850023ef) 的完整[对应源码归档](desugar_jdk_libs-2.1.5-source.tar.gz)，摘要见 manifest。
- configuration：[BSD-3-Clause](LICENSE-desugar_jdk_libs_configuration)。

许可证嵌入 JAR；发布回填库二进制时同时提供固定完整源码归档和构建脚本。
