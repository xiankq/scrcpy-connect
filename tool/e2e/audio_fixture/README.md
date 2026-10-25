# Android 音调夹具

`InteropAudioFixture.java` 用 shell app_process 播放 3 秒、48 kHz 双声道 PCM。以 SDK android.jar 编译，再用对应 d8 转 DEX JAR，输出均放系统临时目录。

只在专用授权目标上传执行，等待 VM 退出并清理本次文件。AudioTrack 回执只证明目标输入，不证明主控播放。
