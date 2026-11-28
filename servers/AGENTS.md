# 被控程序规则

改某个程序前先读它的构建说明：[vendor](vendor/README.md)（scrcpy server）、[companion](companion/README.md)、[helpers](helpers/README.md)。构建和资源同步只用 `servers/build.dart`，用法见[构建说明](README.md)。

- 改协议时，同一次改动里同步改能力包（`packages/`）和应用里的调用代码。
- 声称支持低版本 Android 时，在该版本上实际验证方法签名、类加载和运行结果，不只看编译通过。
- 源码、`manifest.json`、已提交的产物和 `app/assets/servers/` 一起更新，不能只改其中一部分。`servers/build.dart --check` 会报出不一致。
- 应用读取并校验产物后，把字节传给能力包，例如 `createNativeScrcpyHost` 接收的 server JAR 字节。
- 已提交的二进制、对应许可证和源码归档都是构建输入，和产物一起保留，不能删。
- 新需求先看 ADB 和 scrcpy 能否满足；它们做不到的，才按 [README](README.md#职责划分) 写的范围在 companion 或 helpers 里实现。
- 部署和清理只动本次自己创建的路径、流和进程。进程是否退出无法确认时，保留清理任务和后续重试需要的标识（如部署路径），不要假定已清理。
