# 被控执行端

修改前读取对应构建说明：[vendor](vendor/README.md)、[companion](companion/README.md) 或 [helpers](helpers/README.md)；构建与资源同步统一从 `servers/build.dart` 执行，参数见[构建说明](README.md)。

- 协议变更同时核对能力包与应用调用端。低版本兼容验证真实方法签名、类加载及运行行为。
- 源码、manifest、固定产物与共享 assets 同步更新；应用向能力包提供经校验的产物字节。受控二进制及对应许可证、源码归档属于构建输入，随产物保留。
- 标准能力优先复用 ADB 和 scrcpy；扩展范围遵循 [README](README.md) 的职责边界。
- 部署与回收仅操作本次拥有的路径、流和进程；退出未确认时保留清理责任及后续重试所需的身份。
