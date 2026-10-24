# scrcpy server

`scrcpy-server-v5.0.1` 是固定 [scrcpy 5.0.1源码](https://github.com/Genymobile/scrcpy/tree/a60891aea193d92e7e5c3942700eca63f9d19a5f)的构建产物，由被控Android的 `app_process` 临时执行。上游Java/协议不改，启用core-library desugaring支持API 21–23缺失的函数接口。视频、音频和查询共用这一产物；摘要、原始release来源及构建输入以 [manifest](manifest.json) 为准。

## 构建

根目录先运行 `flutter pub get`。`--check` 不需要Android SDK；重建需JDK 21、SDK 36和build-tools 37.0.0，其余工具/依赖版本与摘要由脚本锁定。

```sh
dart servers/vendor/build.dart --check
# 临时重建并逐字节比较，不改受控产物。
dart servers/vendor/build.dart --rebuild
# 有意更新输入/产物时使用。
dart servers/vendor/build.dart --update
```

`JAVA_HOME`/`ANDROID_HOME` 选择工具链；`--gradle` 可指定同版本安装，`--source` 可指定固定提交的本地源码归档，读取时仍验证固定 SHA-256。`--offline` 使用 Gradle 依赖缓存；配合这两个本地输入可避免下载。不同 JDK 补丁或 SDK 内容可能产生差异，比较会失败。生成与共享打包见[工具链契约](../../docs/implementation/repository-tooling.md)。

## API 21回归

检查读取DEX定义/接口表，要求函数接口回填与 `min-api:21` 标记实际存在；仅语言lambda脱糖或搜索字符串不足以证明兼容。

```sh
dart servers/vendor/test/build_probe.dart /tmp/scrcpy-api21-probe.jar
```

将server与probe推至已授权目标临时路径，以 `CLASSPATH=<server>:<probe.jar> app_process / ScrcpyApi21Probe` 执行。探针覆盖接口加载、二分搜索和编码器尺寸约束，不启动编码；成功不代表设备编码器或远控可用。设备结果见[验收记录](../../docs/implementation/validation.md)。

## 许可证与对应源码

- scrcpy：[Apache-2.0](LICENSE-scrcpy)。
- desugar_jdk_libs 2.1.5：[GPLv2+Classpath Exception](LICENSE-desugar_jdk_libs)、[ASSEMBLY_EXCEPTION](ASSEMBLY_EXCEPTION-desugar_jdk_libs)、[附加声明](ADDITIONAL_LICENSE_INFO-desugar_jdk_libs)。保留固定提交 [73170c3](https://github.com/google/desugar_jdk_libs/tree/73170c345e6a762fc6a1f0301bb15218850023ef) 的完整[对应源码归档](desugar_jdk_libs-2.1.5-source.tar.gz)，摘要见manifest。
- configuration：[BSD-3-Clause](LICENSE-desugar_jdk_libs_configuration)。

许可证嵌入JAR。发布含回填库的二进制时，同时提供这里固定的完整对应源码归档和构建脚本；它们是来源材料，必须保留。
