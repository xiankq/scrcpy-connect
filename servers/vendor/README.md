# scrcpy server 来源与构建

`scrcpy-server-v5.0.1` 是单一当前 scrcpy 5.0.1 的源码构建产物，供被控 Android 的 `app_process` 临时执行，不安装 APK。视频、音频和查询共用它。上游 Java 源码与协议保持原样；构建时启用标准 Android core-library desugaring，补齐 Android API 21–23 缺少的 Java 函数接口。

- scrcpy 固定源码：[a60891aea193d92e7e5c3942700eca63f9d19a5f](https://github.com/Genymobile/scrcpy/tree/a60891aea193d92e7e5c3942700eca63f9d19a5f)，对应 [v5.0.1](https://github.com/Genymobile/scrcpy/releases/tag/v5.0.1)。
- [manifest.json](manifest.json) 分别记录当前产物、官方 release 原始产物摘要、源码归档、Java 源码集合摘要、构建脚本、工具链、依赖与每个 DEX 的摘要。
- 官方原始 release 的 SHA-256 是 `764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536`；它不是当前内置产物，不另行保留第二条运行路径。

核心在推送前校验内置字节摘要，每个会话使用独立临时文件和 socket 标识，停止后清理。主机连接、授权、流协议、输入、媒体编排由本仓库实现，不运行上游 adb/scrcpy 主机可执行程序。会话暂停只暂停主控本地显示，被控设备继续采集和编码；恢复通过官方 RESET_VIDEO 指令获取新的编码会话。

## 构建与复查

无需 Android SDK 的离线完整性和构建输入新鲜度检查：

```sh
python3 servers/vendor/build.py --check
```

源码构建需要 Python 3.12+、OpenJDK 21、Android SDK platform 36 与 build-tools 36.0.0。脚本固定 Gradle 9.3.1（下载包 SHA-256）、AGP 9.1.0 / D8-L8-R8 9.1.31、desugar_jdk_libs 与 configuration 2.1.4（各自 JAR SHA-256），并核对本地 API 36 android.jar 摘要。设置 `JAVA_HOME`、`ANDROID_HOME` 后执行：

```sh
# 干净临时源码构建，与当前 JAR 逐字节比较，不修改 vendor。
python3 servers/vendor/build.py --rebuild
# 有意更新构建输入或产物时，验证成功后替换唯一 JAR 与 manifest。
python3 servers/vendor/build.py --update
```

`--gradle /path/to/gradle` 可复用已安装的同版本 Gradle；`--offline` 让 Gradle 使用已填充的依赖缓存（固定 scrcpy 源码归档仍需下载）。网络代理由环境与 Gradle 用户配置控制，必要时可显式传 `--gradle-arg=-Dhttps.proxyHost=` 等参数。脚本只在系统临时目录展开固定来源源码，结束即清理，使用 `--no-daemon` 退出本次 Gradle 进程。

构建只追加 `buildToolsVersion`、Java 8 source/target、`coreLibraryDesugaringEnabled` 和固定依赖配置；不修改任何上游 Java 文件。JAR 包装只保留两个 DEX 和许可证，统一 ZIP 时间、权限并使用不压缩存储，消除 APK 包装时间与压缩器差异。`--rebuild` 是当前工具链下的逐字节复现检查；不同 JDK 21 补丁版或 SDK 内容不能预先保证得到相同字节，差异会明确失败，manifest 记录实际构建 JDK 版本。

## API 21 回归与边界

官方源码的 [Size.constrain](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/model/Size.java) 在编码失败后获得 capabilities，创建实现 `java.util.function.Predicate` 的 lambda，调用 [BinarySearch.findHighestTrue](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/util/BinarySearch.java)。该平台接口从 API 24 才存在；仅有语言 lambda 脱糖不足以支持 API 21。

2.1.4 官方 configuration 使用 `maintain_type` 策略：`Size$$ExternalSyntheticLambda0` 仍实现 `java.util.function.Predicate`，但 `classes2.dex` 实际定义 `Predicate`、`Supplier` 等接口，默认方法实现位于 `j$.util.function.*`。因此不以“所有接口名字必须改为 j$”作为成功条件。离线检查读取 DEX 类定义与接口表，要求这些回填类实际存在，并核对 D8/L8/R8 `min-api:21` 标记；不是只搜索字符串。实现依据参见 [Android 官方 API desugaring 说明](https://developer.android.com/studio/write/java8-support#library-desugaring)。

可编译保留的诊断探针：

```sh
python3 servers/vendor/test/build_probe.py /tmp/scrcpy-api21-probe.jar
```

在已授权的被控设备测试中，将 server 和探针推送到设备临时路径、赋予可读权限，并以 `CLASSPATH=<server>:<probe.jar> app_process / ScrcpyApi21Probe` 执行。它加载函数接口、默认方法回填和 Size lambda，调用真实 `BinarySearch.findHighestTrue`，再读取 AVC 编码器 capabilities 调用 `Size.constrain(VideoConstraints)`，不启动编码器。API 21 实际验证得到 `BINARY_SEARCH_OK 7`、`SIZE_CONSTRAIN_OK OMX.google.h264.encoder 96x48`、`PROBE_OK`，确认 `app_process` 可加载第二个 DEX 并经过原失败路径。

这修复的是缺失 Java 接口导致的重试路径类加载失败。设备仍须具备可工作的 MediaCodec 编码器；API 21 AVD 的 AVC 软件编码器在首次编码时返回 `IllegalStateException`、系统 screenrecord 也失败，属于独立限制。探针成功不等于该 AVD 可以远控，也不改变上游各功能的 Android API 门槛。

## 许可证与对应源码

- scrcpy：原样保留 [LICENSE-scrcpy](LICENSE-scrcpy)，Apache-2.0。
- desugar_jdk_libs 2.1.4：保留 [LICENSE-desugar_jdk_libs](LICENSE-desugar_jdk_libs)（GPLv2 + Classpath Exception）、[ASSEMBLY_EXCEPTION](ASSEMBLY_EXCEPTION-desugar_jdk_libs) 与 [ADDITIONAL_LICENSE_INFO](ADDITIONAL_LICENSE_INFO-desugar_jdk_libs)。完整对应源码归档 [desugar_jdk_libs-2.1.4-source.tar.gz](desugar_jdk_libs-2.1.4-source.tar.gz) 来自固定 [50d9c1fb3e85fa4c00161525a45484f712c1f003](https://github.com/google/desugar_jdk_libs/tree/50d9c1fb3e85fa4c00161525a45484f712c1f003)，摘要见 manifest；归档包含原始来源声明与构建文件，未修改。
- desugar_jdk_libs_configuration：保留原 [BSD-3-Clause 许可证](LICENSE-desugar_jdk_libs_configuration)。

上述许可证也嵌入唯一 server JAR 的 `META-INF/`，随运行产物分发。发布包含回填库的二进制时，同时提供这里固定的完整对应源码归档及构建脚本；该归档是来源材料，不是构建缓存。
