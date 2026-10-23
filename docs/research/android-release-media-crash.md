# Android Release 打开投屏即退出：R8 裁掉 JNI 回调

日期：2026-10-23。结论：**已在 Android 16 x86_64 AVD 上复现现有普通 Release APK 的确定性崩溃，根因是 R8 移除 JNI 按名访问的 Java 回调；未修改业务代码，未实施修复。**

用户真机为 arm64 / Android 16，报告主控打开被控屏幕退出。AVD复现证明同类症状在x86_64也存在，根因属于Java构建与JNI契约，不依赖arm64指令集；用户真机是否为完全相同栈仍需真机日志确认。

## 复现对象和最小触发

- 主控：`interop-controller`，API36 / Android16 / x86_64；普通 `dev.scrcpyconnect.scrcpy_connect/.MainActivity`。
- 被控：`interop-target`，API36 / x86_64，系统Settings前台。
- 使用原来已安装的Release，未重新编译、未换成integration-test入口。安装APK与交付 `build/verified/android-universal-release.apk` 的SHA-256相同：`eafaed0ffe680bc3c4ce1bba51bf6b52e46a01b81a5cdb46be523fe59feb6d3f`。
- 被控TCP5555经本机15556转发，主控普通UI添加 `10.0.2.2:15556` 后显示已连接。
- 设备详情点击“打开手机屏幕”。不需要音频、转屏、后台切换或触摸；首个媒体输出创建即失败。
- 点击前主控PID3410；点击后PID消失，logcat记录同包SIGABRT。

该最小场景避免将宿主模拟器本身的GPU启动失败误当成Android应用崩溃。最初无DISPLAY的host模式未启动成功，SwiftShader下模拟器宿主进程也曾SIGSEGV；最终有效复现使用 `DISPLAY=:0`、正确的 `XAUTHORITY`、host GPU、禁用Vulkan。有效证据是Android guest中的应用SIGABRT，模拟器继续在线。

## 运行证据

第一次有效复现：2026-10-23 10:14:47（UTC+8）。简化后的关键日志：

```text
Fatal signal 6 (SIGABRT) ... pool-3-thread-1 ... pid 3410
Cmdline: dev.scrcpyconnect.scrcpy_connect
ABI: x86_64
NoSuchMethodError: no non-static method "Llj;.onFrame(II)V"
Throwing new exception: no non-static method "Llj;.onPcm([B)J"
with unexpected pending exception
...
art::JNI<false>::GetMethodID
Java_dev_scrcpyconnect_media_1codec_MediaCodecPlugin_nativeCreate+191
libmedia_codec_plugin.so BuildId: 4593d8ae8f1250ac38db672824e719c847d31e10
```

原始logcat保存在本次系统临时目录 `/tmp/scrcpy-source-audit/android-crash/crash-after-open.log`；上述摘录属于长期记录，临时日志不承担规范或永久交付责任。原始buffer也含早期uiautomator启动过早的独立错误，归因只使用应用包名、PID、nativeCreate和匹配时间段，未将不同进程异常混算。

重新打开同一个普通Release应用后重复相同操作，10:18:08再次从PID3957退出，缺失回调及nativeCreate栈一致，记录于 `crash-second-open.log`。两次Android退出记录均为 `APP CRASH(NATIVE)`、status 6。两次复现之间没有更换APK、修改代码或调整混淆配置。

实验结束已通过普通UI移除本次新增的测试设备，删除本次UI导出文件，撤销15556转发，将被控adbd恢复USB模式，并关闭本次启动的两个AVD。保留原有AVD、安装包、ADB密钥和编译缓存；SDK默认ADB服务未被关闭。

## 从构建到 abort 的闭合证据

1. [Java Session 回调](/home/xiankq/git/scrcpy-connect/packages/media_codec/android/src/main/java/dev/scrcpyconnect/media_codec/MediaCodecPlugin.java:254) 定义 `public void onFrame(int,int)` 与 `public long onPcm(byte[])`；没有保留注解。
2. [JNI nativeCreate](/home/xiankq/git/scrcpy-connect/packages/media_codec/android/src/main/cpp/media_codec_jni.cpp:110) 用 `GetObjectClass(listener)`，接着两次 `GetMethodID` 查找字面量名字及签名。R8无法从Java调用图得知这些回调被C++使用。
3. [插件 Gradle](/home/xiankq/git/scrcpy-connect/packages/media_codec/android/build.gradle:7) 未打包保护它们的consumer keep rules。原有native方法保留只保护Java→native入口，不自动保护native→Java回调。
4. 本次Release的 `app/build/app/outputs/mapping/release/usage.txt:8489–8493` 明确列出 `MediaCodecPlugin$Session` 的 `onFrame(int,int)`、`onPcm(byte[])` 被移除；mapping把Session混淆成 `lj`，与崩溃栈 `Llj;` 对应。
5. 第一次GetMethodID找不到onFrame，留下NoSuchMethodError；代码未检查method ID或pending exception就执行第二次GetMethodID查onPcm。ART在已有异常时再次抛异常并abort，栈落在nativeCreate。
6. 该故障发生在 `mc_create` / `mc_attach` 及实际解码之前，不是本次AVD的MediaCodec兼容、CPU解码性能或GPU颜色转换失败。

Android官方说明：native代码反向访问Java成员需要对应keep规则，库应随consumer规则分发；默认native入口保护不等于回调保护。见[官方JNI与keep规则示例](https://developer.android.com/topic/performance/app-optimization/keep-rule-examples#jni)。

## 最小整改范围（未实施）

- 在 `media_codec` 库自己的consumer规则中，精确保留这两个回调的名字、签名及存活，或采用能可靠传递给R8的保留注解。不要用全应用关闭R8来掩盖契约缺失，也无需保留所有媒体类。
- JNI逐个检查GlobalRef/class/method lookup结果和pending exception；失败清理所有已创建引用，转成可由Java创建流程处理的失败，避免继续带异常调用JNI。只加keep规则不能解决以后签名变更时相同abort风险。
- 回归必须测试**开启R8的普通Release APK打开真实投屏和PCM输出**。Debug/Profile已有测试不等于这条链路已覆盖。
- 构建后检查最终DEX/mapping，确认callback仍存在；设备运行检查真实画面及无fatal，不能只看MainActivity成功启动。

这是具体可审阅的修复方案；本轮按“只调研、不编码”约束保留故障，没有生成宣称已修复的新APK。

## 与用户截图的关系

截图中的 `device.screen.state / device_error` 是设备屏幕状态查询失败，既没有此处NoSuchMethodError，也没有native abort栈。该查询位于[device_details.rs](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/device_details.rs:254)，执行目标 `dumpsys power; dumpsys window policy`。当前证据不能把截图的查询失败与JNI abort合并为同一个根因。

## 验收结论更正

此前普通Release只验证安装、MainActivity启动和设备页呈现；真正视频生命周期及性能测试跑的是Debug。这个覆盖范围遗漏了R8裁剪后的首次JNI媒体输出。因此“Release普通入口启动成功”仍是有效事实，但不能据此声称Release投屏可用。当前Release交付物存在本报告所列阻断故障。
