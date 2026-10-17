# 接续当前系统通话界面

calls.open只打开被控设备当前系统通话界面，不接受callId，不接听／拒接／挂断或切换音频。Rust要求显式实时观察，JAR重取非空闲聚合通话并检查当前用户，再按运行时已适配的showInCallScreen签名调用系统。接口不存在／权限失败有明确错误；失败可重试。

系统接收请求只返回target=currentSystemCall、acceptedBySystem=true、uiVisible=null、callControlled=false。Flutter页面只在有效回执后进入已有全屏远控；成功回执不单独证明界面可见。calls.list继续给出聚合观察，具体呼叫动作和主控双向通话音频均未实现。

## 本批证据

- 公开Runtime红测unknown_command→observation_required，证明无live观察时不会偷偷启动helper。最终1项通过。
- 通话页成功／失败两条公开页面测试已与远控生命周期合计43项通过；等待系统回复时不提前启动session，失败不打开远控，不调用calls.action。
- 独立实际Android Runtime验收：创建自己的模拟来电→确认聚合状态→先切Settings前台→calls.open→独立dumpsys确认真实InCallActivity前台→虚拟modem仍ringing→旧呼叫动作拒绝且不结束替代来电。最终9.94秒通过，`/tmp/connect-call-system-ui-r2.log`，构建1.28秒。前版6.01秒也通过，但其旧ENDCALL清理会令目标睡眠，已移除并复验。
- 夹具只取消5550101234／5550101235，等待真实modem与Telecom idle，不再发全局ENDCALL。真实测试前拒绝已有call，不把系统全局动作当产品的逐呼叫控制。
- JAR已同步编译产物和SHA：77007b4fb29e51296a448e669178f43c775854b3f4665ea5af44412c207447de。没有新增Kotlin产品代码／目标APK。

## 可复现命令

仅在明确隔离的目标AVD且当前无通话时运行：

```sh
rtk proxy env ANDROID_ADB=/home/xiankq/Android/Sdk/platform-tools/adb \
  ANDROID_TARGET_SERIAL=emulator-5556 INTEROP_CORE_TEST_ENDPOINT=127.0.0.1:15556 \
  CARGO_BUILD_JOBS=2 cargo test -p interop-core --test companion_android \
  rust_runtime_observes_rapid_replacement_and_refuses_unsafe_aggregate_actions \
  --locked -- --ignored --nocapture --test-threads=1
```

这是公开Runtime＋实际系统界面的证据，尚不是正式CallsPage→全屏像素的完整产品E2E。物理PSTN／VoIP、多SIM／通话等待、具体callId adapter、主控麦克风／双向声音／路由仍按任务12／20独立推进；新入口不能用于关闭这些要求。
