# scrcpy

类型化视频/PCM 捕获、控制消息与原生媒体源。设备选择、逻辑窗口、画质、重连及音频路由由应用负责。

`createNativeScrcpyHost` 接收 server JAR 字节、身份路径和数据目录，提供同库 `host.adb` 与 `host.scrcpy`。已有同库 ADB 时用 `createNativeScrcpy(serverBytes: ...)`；**独立 adb 动态库的句柄不能混入本库**。首次成功加载后不能热换库。

```dart
final scrcpy = ScrcpyClient(nativeApi);
final session = await scrcpy.createSession(
  device,
  options: const ScrcpyOptions(maxSize: 1280, maxFps: 30),
);
try {
  final info = await session.start(cancellation: cancellation);
  // 将 info.source 交给本机解码器；无视频时为空。
  await session.sendControl(
    const ScrcpyKey(action: ScrcpyKeyAction.down, keycode: 4),
  );
} finally {
  await session.close();
}
```

需要先打开应用再等待媒体时，依次调用 `startControl()`、`sendControl(...)`、`awaitMedia()`。回执记录准入、写出和剪贴板确认。被控应用的执行结果由对应观测读取。

## 资源归属

`createSession` 拥有捕获停止权。`attach(captureRef, generation: ...)` 读已有捕获，关闭时解除自身观察。渲染器独立附着和分离来源。`sourceStatus` 记录流及接纳计数。解码、显示和播放由渲染器记录。

`session.events` 首次监听才创建独立原生观察者。订阅取消失败可通过会话关闭重试；缺少终态的 EOF 为 `result_unknown`。捕获与观察者分别确认释放，关闭失败须保留同一 session 重试；创建取消后的清理失败由 `ScrcpyCreationCleanupFailure.session` 交回唯一关闭权。

捕获所有者 close 等待本机收尾及受监督主进程退出。上游清理子进程和屏幕设置恢复分别核验。身份或终态未确认时保留清理责任和部署文件，供后续核验。

isolate 重启可用 `listNativeScrcpyServers` 和当前 lease 调用 `restoreNativeScrcpyHost`；再通过配套 ADB 能力分别认领连接。先用 `drainConnection(device)` 排空旧捕获，再恢复业务。端点/PID 不授予权限，旧句柄不能关闭后继。先关闭捕获及设备活动，再关闭宿主。其余契约见[ADB](../adb/README.md)。

`createNativeScrcpyLocalFiles()` 提供同库且无需设备连接的本机文件能力，遵守 ADB 包的 FD/提交未知契约。

## 配置

`maxSize/maxFps=0` 表示不限，当前帧率仅接受整数；`logLevel` 默认 debug，依赖 info 日志时显式设置。新显示宽高为 1–65535；媒体元数据按正 i32 解析，解码器另验资源上限。`ScrcpyResizeDisplay` 只调整启用 flexDisplay 的新显示，不修改物理屏幕尺寸。

上游选项见[固定 scrcpy 5.0.1](https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/Options.java)，产物来源见[servers/vendor](../../servers/vendor/README.md)。
