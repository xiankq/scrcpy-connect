# Android 音调输入夹具

`InteropAudioFixture.java` 以 `app_process` 的 shell 身份播放 3 秒、48 kHz 双声道 PCM 音调；只提供测试输入，不证明主控已接收、解码或播放声音。由原 Rust 应用测试目录迁入，独立于已移除的 Runtime。

使用仓库 Android SDK 的 `android.jar` 编译，使用匹配 build-tools 的 `d8` 转成 DEX JAR；所有 class、DEX 和 JAR 输出放系统临时目录。仅在专用授权设备上明确上传和启动，结束后清理本次自有文件。源码输出真实 AudioTrack 播放回执；启动者须独立等待本次 VM 退出。
