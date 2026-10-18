# 首次编码器分配复用候选

本补丁基于固定 scrcpy 5.0.1 加生产暂停扩展，与 bounded-input 候选独立。
生产 JAR 不覆盖。只有本补丁确实改变被控设备源码时，才需要重新构建隔离 JAR；
修改主控 Rust／Flutter 不因此重建 scrcpy。

生产暂停扩展先分配 MediaCodec 查询能力、释放，再为第一次捕获重新分配。
候选把首次暂停门禁移至分配前，用同一实例查询能力并启动首次捕获。编码器选择、
能力约束、画质参数、重试和后续暂停时释放编码器的约定保留。

控制对象在 SurfaceEncoder 构造时绑定到 SurfaceCapture，不分配捕获资源，确保
Controller 启动后早到的暂停和 reset 能进入同一控制对象。视频 codec header 独立
于编码器分配，在初始门禁前写入。门禁后到达的暂停请求仍先结束捕获、stop／release
编码器与输入 Surface，再回到门禁确认。部分初始化及 capture.stop 异常也经过
finally 清理。

初始暂停可能延后虚拟显示初始化。flex display 在此时收到 resize 仅保存最新尺寸，
初始化与请求共用对象锁，待实际约束和 debouncer 就绪后应用。不会为暂停分配编码器。

构建与测试：

```sh
rtk proxy python3 servers/scrcpy/build.py --candidate initial-codec --output-dir /tmp/connect-initial-codec-new
rtk proxy python3 servers/scrcpy/test.py --candidate initial-codec --build-dir /tmp/connect-initial-codec-new
```

输出目录须不存在且位于仓库外。源码归档和两份补丁均验证摘要，输出 manifest 记录
候选与编译身份。实际编译的 SurfaceEncoder 与 NewDisplayCapture 接缝由 JVM 回归
验证；仅 Android SDK 接口使用替身，没有复制项目状态机。

源端启动对照可使用：

```sh
rtk proxy python3 servers/scrcpy/benchmark_startup.py \
  --baseline servers/scrcpy/interop-scrcpy-server.jar \
  --candidate /tmp/connect-initial-codec-new/interop-scrcpy-server.jar \
  --output /tmp/connect-initial-codec-startup-new --rounds 5
```

此脚本使用官方 ADB 部署、固定 H2641280／60／8Mbps／c2.android.avc.encoder，
逐组 A/B/A，记录从启动 shell 到完整首媒体包的宿主单调时间、精确 PID 的 native
分配日志，以及首包离线解码的原始尺寸和计数内容。部署和离线解码不计入时钟；
读取共用启动绝对期限，清理精确进程、forward、临时 JAR、自有 fixture 和设置。
这不是产品 Rust ADB／Flutter 呈现验收。设备测试 APK 与 FFmpeg 需事先具备；
已有 fixture 时拒绝运行，不删除已有安装。

2026-10-18 的15次 API36 进程冷启均确认分配2→1；配对首媒体包差值中位-26.611ms，
一组反向，不能替代完整首帧结果。真实初始暂停、静止后新输入、恢复与旋转通过。
普通Flutter A/B/A首像素2433／2356／2223ms，输入P50为1819／1715／1714ms，
没有稳定优于返回基线，三组严格性能门禁均失败，**不替换生产JAR**。
30张真实窗口内容正确，暂停恢复和逻辑停止通过；原生delete确认仍未取得。
完整结果及生产是否采用以[当前完成度](../../../../.scratch/interop/current-status.md)和
[视频性能记录](../../../../docs/implementation/video-performance.md)为准。其他编码器、
物理 ARM、无线漫游及虚拟显示设备运行仍需验证。
