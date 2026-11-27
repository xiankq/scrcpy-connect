# 小米电视 Android 9 镜像裁切工单

## 最接近的工单

- **scrcpy #3778** 的报告者用 Windows 上的 scrcpy 1.24 和 1.25 镜像 Android TV，默认命令和 `-m 1024` 都只显示部分画面。原帖附件里的设备信息显示 Xiaomi、小米电视型号 MiTV-MFTP0、Android 9（API 28）和 1920×1080 物理分辨率。另一张图中的电视启动器在画面底部被截断。工单仍开放，暂无回复。图片缺少同一画面的全屏对照，无法量化裁切比例。 [scrcpy #3778](https://github.com/Genymobile/scrcpy/issues/3778)
- **scrcpy #2158** 记录了 Android 9 的小米盒子 3／3s 和小米电视棒（MiTV AESP0）在 scrcpy 1.17 上的采集异常。播放视频的 Surface 损坏，叠加的系统界面仍正常。日志显示 `OMX.amlogic.video.encoder.avc`。报告者用系统 `screenrecord` 也录到同样的损坏，scrcpy 维护者据此判断问题出在被控设备。该报告涉及播放画面，整机四分之一裁切的原因仍待验证。 [scrcpy #2158](https://github.com/Genymobile/scrcpy/issues/2158)

## 可区分的问题

- **scrcpy #5799** 的 Lenovo Android 10 平板只显示画面的一部分。日志先报 1200×1920，再变成 1080×1920。维护者推测编码器静默输出了更小帧，报告者确认将视频长边限制为 1600 后恢复。它说明核对请求尺寸和实际视频帧尺寸能帮助定位裁切。 [维护者判断和报告者的验证](https://github.com/Genymobile/scrcpy/issues/5799#issuecomment-2623944580)
- **scrcpy #6845** 的 JVC Android 11 电视在 scrcpy 4.0 上输出 398×224，3.3.4 上输出 1920×1080。一位用户说其小米智能电视也遇到同类问题，随后确认 #6859 修复。该工单描述的是视频分辨率大幅下降，小米机型、系统版本及是否只显示左上角没有记录。#6859 的合并提交已包含在仓库固定的 scrcpy 5.0.1 提交中。 [原帖](https://github.com/Genymobile/scrcpy/issues/6845) · [小米用户确认](https://github.com/Genymobile/scrcpy/issues/6845#issuecomment-4543778576) · [修复 PR](https://github.com/Genymobile/scrcpy/pull/6859) · [提交关系](https://github.com/Genymobile/scrcpy/compare/f457fd4cf5ff4e91853159cbbbbbb98efa8f30b3...a60891aea193d92e7e5c3942700eca63f9d19a5f) · [仓库固定版本](../../servers/vendor/README.md)
- **scrcpy #2701** 的画面明确只显示左上象限，出现在 macOS 主控使用 SDL 软件渲染时，切换到 Metal 或 OpenGL 后恢复。该报告的被控端是 Android 11 手机，可作为主控渲染产生同样外观的对照。 [scrcpy #2701](https://github.com/Genymobile/scrcpy/issues/2701)

## 同类项目

- **ScrcpyForAndroid #52** 是 Android 主控的解码问题报告。MTK AC8257 车机在超出硬件分辨率上限或旋转后解码崩溃，症状是闪退。**易控 #19** 记录连接后黑屏闪烁和无法控制，讨论集中在熄屏控制和被控设备的屏幕状态。两个工单都没有描述小米 Android 9 电视的左上角裁切。 [ScrcpyForAndroid #52](https://github.com/Miuzarte/ScrcpyForAndroid/issues/52) · [易控 #19](https://github.com/mingzhixian/Easycontrol/issues/19)
- **RedmiTvManager** 项目记录了一次 Android 9 电视实测，使用其随附的 scrcpy 2.4、1280 宽、15 FPS 上限和 2 Mbps 录制 5 秒成功。说明中没有给出该次录制的四角完整性。 [RedmiTvManager 实机限制](https://github.com/moonheart/RedmiTvManager#v020-%E5%AE%9E%E6%9C%BA%E9%99%90%E5%88%B6)
