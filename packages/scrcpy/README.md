# scrcpy

提供类型化 scrcpy 视频捕获、控制消息与原生媒体源描述。设备选择、逻辑窗口、画质档位、重连、焦点和持久化由调用应用负责。音频捕获与播放策略分别由原生协议机制和宿主组合。

独立宿主通过 `createNativeScrcpyHost` 提供服务器 JAR 字节、身份路径和数据目录，取得配套的 `host.adb` 与 `host.scrcpy`。Rust 协议实现位于顶层 `rust/scrcpy/`；本包独立动态库组合普通 ADB 与 scrcpy API，共享同一连接注册表。传入的 `AdbDevice.id` 必须来自同库 ADB 能力，不能使用独立 adb 动态库的句柄。自定义宿主也可注入 `NativeScrcpyApi`。

isolate 重启后，可用 `listNativeScrcpyServers` 列举原生仍持有的服务器，再以当前 `leaseId` 调用 `restoreNativeScrcpyHost`。认领保留原服务器与密钥，轮换控制租约；`host.nativeConfiguration` 只提供事实投影，端点或 PID 不能授予关闭权。`createNativeScrcpyAdbApi` 提供同库普通 Dart 能力，供 `NativeAdbClient` 枚举和精确认领既有连接；服务器认领与连接认领分别进行。调用方须先停止自己拥有的捕获和活动，再关闭宿主。参见 [ADB 生命周期约束](../adb/README.md)。

连接认领保留既有捕获。需要释放旧 isolate 留下的捕获时，使用 `ScrcpyClient.drainConnection(device)`：按当前连接权限固定属于该底层连接的捕获集合，取消并等待实际清理。等待期间新建的捕获不进入旧集合；同一物理 Client 的另一个独立登记不受影响。旧操作句柄不能发起排空，失败保留精确捕获供重试；该操作不关闭共享 ADB Client。调用方先完成排空，再恢复自己的逻辑窗口或活动。注入的自定义适配器需实现 `NativeScrcpyConnectionApi`，缺少该能力时明确失败。

默认加载本包 Native Assets 动态库。首次成功后固定所选路径；普通文件按规范路径比较，APK 内库等加载器路径按原值比较。后续省略路径复用已选库，显式指定不同路径会返回 `native_library_mismatch`。初始化失败后允许重试，不在同一 isolate 热换库。

本包与独立 ADB 包可以在同一 isolate 使用，各自为实际动态库保留退出登记。子 isolate 退出不撤销其他存活 isolate 的结果通道；这不合并两个库的资源登记，连接和 scope 句柄仍须交回创建它们的库。

`createNativeScrcpyLocalFiles()` 返回同一动态库的通用本机文件能力，无需服务器 JAR、ADB 服务器或设备连接。文档提供方的业务规划与授权仍由调用方持有；该工厂只隐藏绑定并复用 [LocalFiles 的资源契约](../adb/README.md)，不接受应用命令。

独立捕获先登记可取消句柄，再启动远端工作：

```dart
final scrcpy = ScrcpyClient(nativeApi);
final session = await scrcpy.createSession(
  device,
  options: const ScrcpyOptions(maxSize: 1280, maxFps: 30),
);
try {
  final info = await session.start(cancellation: cancellation);
  // info.source 只含本进程原生通道描述；将它交给本机解码器，不传媒体字节。
  await session.sendControl(
    const ScrcpyKey(action: ScrcpyKeyAction.down, keycode: 4),
  );
} finally {
  await session.close();
}
```

已有同库 ADB 所有者时，`createNativeScrcpy(serverBytes: ...)` 只创建协议能力，不启动另一套 ADB 宿主。需要先打开控制通道、发送 `ScrcpyStartApp`，再等待画面时，可按 `session.startControl()`、`session.sendControl(...)`、`session.awaitMedia()` 分阶段执行；普通 `start()` 组合这些准备阶段。发送应用启动消息只证明消息写出，媒体就绪由独立回执确认。

`ScrcpyOptions` 分别控制视频、音频与控制通道；无视频捕获时 `info.source` 为空。当前音频捕获支持 raw/output 双声道 PCM，原始通道与本机播放输出分别描述，SDK 不选择产品音频路由。会话还提供实际远端进程与有界输出事实，输出最多保留 64 KiB；进程结束和捕获清理分别确认。

`scrcpy.sourceStatus(device, captureRef: session.id, sourceId: source.sourceId)` 返回精确来源的状态、实际 sink 代次、类型、编码及已接纳的数据包和字节数。未附着 sink 时代次为 0、状态为 waiting；streaming 表示 sink 已附着，不证明解码、呈现或音频播放。计数只包含 sink 已接纳的数据包，未接纳及重试不重复计数。查询核验同库的当前连接操作句柄与捕获归属：认领后须使用新句柄，同一物理连接的另一个独立登记也不能查询。未知、释放或串用来源明确报错，不返回伪造零值。自定义适配器可选择实现 `NativeScrcpySourceStatusApi`，缺少能力时返回 `source_status_unavailable`。

宿主业务所有者已经启动捕获时，使用精确捕获引用附着，避免再次启动：

```dart
final observer = await ScrcpyClient(nativeApi).attach(
  captureRef,
  generation: rendererGeneration,
);
try {
  final source = observer.info!.source;
  // 渲染器负责自己的原生 attach/detach；它不能借用旧来源身份停止新捕获。
} finally {
  await observer.close();
}
```

`createSession` 返回的会话拥有停止权，`close` 会撤销精确捕获；`attach` 返回的会话只拥有观察权，`close` 不停止业务所有者。显式停止现有捕获使用宿主所有者或 `NativeScrcpyApi.stopSession`。拥有停止权的关闭等待本机回收与受监督主进程退出证明；启动使用 START→PID→RUN，停止核验本次唯一 DONE，回执丢失时按 PID 与内核启动时间核验。START 可能已交付且身份与 DONE 均缺失时保留清理未知，不删除部署文件。主进程退出不证明上游清理子进程结束或屏幕设置恢复。关闭失败可重试；若创建取消后的回收失败，`ScrcpyCreationCleanupFailure.session` 保留唯一句柄供调用者重试关闭。

每次读取 `session.events` 获得独立单订阅元数据流，首次监听才创建原生观察者。取消订阅和会话关闭共用同一 `ScrcpyEventObserver` 的精确关闭权；取消失败保留原 ID，可通过会话关闭重试，`whenClosed` 只在实际释放确认后完成。暂停观察者不会阻塞会话回收，关闭未监听的流不会创建原生观察者。缺少停止终态的 EOF 返回 `result_unknown`。注入适配器通过同步 `NativeScrcpyApi.openEvents` 交出观察者所有者，不另包一层订阅或取消登记。

捕获与观察者分别保留释放确认。观察者取消失败时，仍发起并等待捕获停止；捕获已确认释放后，重试 `session.close()` 只回收尚未释放的观察者，不再次使用已失效的捕获句柄。捕获停止失败则保留原捕获供重试，已释放的观察者不会重新登记。

控制回执的 `completion` 区分队列准入、写出与剪贴板协议确认。按键、触控和滚动的准入不保证被控应用已处理；写出 `ScrcpyStartApp` 不证明应用已经打开。实现可以对需要协议确认的文本返回剪贴板确认层级。

`ScrcpySetDisplayPower(on: ...)` 对应固定上游的布尔显示电源消息。`ScrcpyResizeDisplay(width: ..., height: ...)` 仅用于视频捕获已创建且启用 `flexDisplay` 的新显示，尺寸为 1–65535；不修改物理屏幕 `wm size` 或密度，也不安装产品最小尺寸。两者的 written 回执均不证明设备已应用变化。

当前类型化新显示配置同样支持 1–65535 的宽高；视频会话元数据按固定服务端的 32 位正整数解析，不套用本机解码器限制。尺寸可以被协议表达，不代表被控编码器、设备显示系统或所接解码器支持；各执行者核验自己的限制。配套 `media_codec` 的单边上限为 16384。

配置默认值对应固定上游版本：`maxSize` 与 `maxFps` 为 0 表示不限；当前帧率入口支持非负整数，不接收上游的小数帧率。`logLevel` 提供 verbose/debug/info/warn/error，默认与固定服务端 `Options` 一致为 debug；创建虚拟显示不会改变它。需要读取 info 等级的服务端输出时，调用方须显式选择相应等级。产品对帧率、虚拟屏行为和剪贴板同步的选择必须显式传入。支持项以公开的类型化字段为准，上游定义见 [scrcpy 5.0.1 Options](https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/Options.java)。
