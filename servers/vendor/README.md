# scrcpy server

使用固定版本 [scrcpy 5.0.1](https://github.com/Genymobile/scrcpy/tree/a60891aea193d92e7e5c3942700eca63f9d19a5f)。Java 代码和协议与上游一致，唯一改动是启用 core-library desugaring，让它能在 Android API 21–23 上运行。上游 release 来源、构建输入和摘要记录在 [manifest](manifest.json)。

## 构建

先在仓库根目录运行 `flutter pub get`。

```sh
# 离线核对已提交产物与 manifest
dart --disable-dart-dev servers/build.dart --check vendor
# 在临时目录重新编译并比较，不替换产物
dart --disable-dart-dev servers/build.dart --rebuild vendor
# 更新已提交的产物和共享资源
dart --disable-dart-dev servers/build.dart --update vendor assets
```

重建需要 OpenJDK 21、Android SDK platform 36、build-tools 37.0.0。

| 选项 / 环境变量 | 作用 |
| --- | --- |
| `JAVA_HOME`、`ANDROID_HOME` | 指定 JDK 和 Android SDK |
| `--source <归档>` | 使用本地的上游源码归档，摘要必须与 manifest 一致 |
| `--gradle <路径>` | 使用指定的 Gradle 可执行文件，版本须与 manifest 一致 |
| `--offline` | 只用本地依赖缓存，不联网 |

## 许可证与对应源码

- scrcpy：[Apache-2.0](LICENSE-scrcpy)。
- desugar_jdk_libs 2.1.5：[GPLv2+Classpath Exception](LICENSE-desugar_jdk_libs)、[ASSEMBLY_EXCEPTION](ASSEMBLY_EXCEPTION-desugar_jdk_libs)、[附加声明](ADDITIONAL_LICENSE_INFO-desugar_jdk_libs)。固定提交 [73170c3](https://github.com/google/desugar_jdk_libs/tree/73170c345e6a762fc6a1f0301bb15218850023ef) 的完整[对应源码归档](desugar_jdk_libs-2.1.5-source.tar.gz)，摘要见 manifest。
- desugar_jdk_libs configuration：[BSD-3-Clause](LICENSE-desugar_jdk_libs_configuration)。

许可证文本已打进 JAR。发布含 desugar 库代码的二进制时，同时提供上面的完整源码归档和构建脚本。
