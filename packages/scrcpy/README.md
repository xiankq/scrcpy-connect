# scrcpy

提供类型化的视频/PCM 捕获、控制消息和原生媒体源。

不负责：选择设备、逻辑窗口、画质选择、重连、音频路由。这些由应用负责。

## 创建

- `createNativeScrcpyHost` 接收 server JAR 字节、身份文件路径和数据目录，返回同一动态库里的 `host.adb` 和 `host.scrcpy`。
- 已经有本库配套的 ADB 时，用 `createNativeScrcpy(serverBytes: ...)`。
- **独立 adb 包的动态库创建的句柄不能传给本库。** 第一次成功加载后不能更换动态库。

```dart
final scrcpy = ScrcpyClient(nativeApi);
final session = await scrcpy.createSession(
  device,
  options: const ScrcpyOptions(maxSize: 1280, maxFps: 30),
);
try {
  final info = await session.start(cancellation: cancellation);
  // 把 info.source 交给本机解码器；没有视频时为 null。
  await session.sendControl(
    const ScrcpyKey(action: ScrcpyKeyAction.down, keycode: 4),
  );
} finally {
  await session.close();
}
```

需要先打开某个应用、再等媒体流时，依次调用 `startControl()`、`sendControl(...)`、`awaitMedia()`。

`sendControl` 的回执只说明消息被接受、已写出、剪贴板已确认。被控应用是否真的执行了操作，要从对应的观测结果读取。

## 资源归属

| 谁 | 负责什么 |
| --- | --- |
| `createSession` 创建的 session | 拥有捕获，只有它能停止捕获。 |
| `attach(captureRef, generation: ...)` | 读取已有的捕获；关闭时只解除自己的观察，不停止捕获。 |
| 渲染器 | 自己附着和分离来源，并记录解码、显示和播放结果。 |
| `sourceStatus` | 记录流的状态和已接收计数。 |

- `session.events` 第一次被监听时才创建一个独立的原生观察者。取消订阅失败时，可以通过关闭 session 重试。EOF 时没有收到终止结果，结果为 `result_unknown`。
- 捕获和观察者分别确认释放。`close()` 失败时保留同一个 session 再次调用。
- 创建过程中被取消、清理又失败时，`ScrcpyCreationCleanupFailure.session` 交回这个 session，它是唯一能关闭该 session 的对象。
- 捕获的所有者调用 `close()` 时，会等本机收尾完成、并等受监督的 scrcpy 主进程退出。上游清理子进程和恢复屏幕设置是两件事，分别核验。
- 身份或终止结果未确认时，保留清理任务和手机上的部署文件，留待之后核验。

## isolate 重启后恢复

1. 用 `listNativeScrcpyServers` 和当前 lease（授权凭证）调用 `restoreNativeScrcpyHost`。
2. 通过配套的 ADB 能力分别认领各条连接。
3. 先用 `drainConnection(device)` 等旧捕获处理完，再恢复业务。

- 地址端口和 PID 不能当作权限；旧句柄不能关闭新的继任者。
- 关闭顺序：先关捕获和设备上的活动，再关宿主。
- 其余规则同 [ADB 包](../adb/README.md)。

`createNativeScrcpyLocalFiles()` 提供同一动态库里、不需要设备连接的本机文件能力，规则同 ADB 包的[本机文件](../adb/README.md#本机文件)。

## 配置

- `maxSize` 或 `maxFps` 为 `0` 表示不限制。帧率只接受整数。
- `logLevel` 默认 `debug`。代码依赖 info 级日志时显式设置。
- 新建虚拟显示的宽高范围为 1–65535。媒体元数据按正的 i32 解析；解码器另外检查资源上限。
- `ScrcpyResizeDisplay` 只调整启用了 flexDisplay 的新建显示，不改手机物理屏幕的尺寸。

上游选项见[固定的 scrcpy 5.0.1](https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/Options.java)，产物来源见 [servers/vendor](../../servers/vendor/README.md)。
