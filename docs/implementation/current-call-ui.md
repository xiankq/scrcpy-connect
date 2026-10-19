# 接续当前系统通话界面

本文记录 `calls.open` 的协议边界与历史验收。用户操作规则以 [交互规则](../../designs/prod/interaction-rules.md) 为准；历史模拟来电结果不代表完整通话控制或双向音频已交付。

calls.open只打开被控设备当前系统通话界面，不接受callId，不接听／拒接／挂断或切换音频。Rust要求显式实时观察，JAR重取非空闲聚合通话并检查当前用户，再按运行时已适配的showInCallScreen签名调用系统。接口不存在／权限失败有明确错误；失败可重试。

系统接收请求只返回target=currentSystemCall、acceptedBySystem=true、uiVisible=null、callControlled=false。Flutter页面只在有效回执后通过共享入口进入全屏远控；成功回执不单独证明界面可见。calls.list继续给出聚合观察，具体呼叫动作和主控双向通话音频均未实现。

## 2026-10-18 协议验收（历史）

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

## 2026-10-18 正式页面 E2E（历史）

新增`integration_test/current_call_ui_test.dart`与独立driver，实际第三轮16秒通过，构建12.1秒／安装656ms；`/tmp/connect-current-call-ui-r3.log`、`/tmp/connect-e2e/current-call-ui-r3/result.json`。正式通话页启动观察→真实模拟来电→选择产品来电提醒“查看来电与声音”→通话页“打开系统通话界面”→生产全屏RemotePage与真实解码。动作前目标独立确认Settings前台；之后独立确认InCallActivity、同一TC@7且确切5550101246仍振铃。两端实际截图已目视，远控全屏显示原系统通话界面／接听拒接控件及目标自身首次沉浸“Viewing full screen / Got it”提示；提示也是被控实际像素，不以它遮住的呼叫标题声称完整可见。未点击接听或拒接。

四个一次性checkpoint完整通过，观察、连接、设置、焦点、精确会话清理与自有来电取消全部true，无清理错误；不发全局ENDCALL。驱动拒绝已有通话，保留目标Telecom／Telephony独立记录。严格分析最终两文件无问题；第一次lint发现use_null_aware_elements已修。

此前两轮不算通过：r1模拟器37.2.12的gsm list仅回OK，原驱动误认为没有来电；改为实际Telecom单呼叫身份＋Telephony原号码／状态，后续每点保持同一身份。r2真实产品来电sheet覆盖通话页，直接点底层按钮被hit-test拒绝；测试改为操作产品真实“查看来电与声音”入口，没有透过遮挡点按钮或关闭产品提示机制。

复现（仓库根目录，目标必须隔离且无现有通话，端口按当前实际转发设置）：

```sh
rtk proxy env CONNECT_E2E_ADB=/home/xiankq/Android/Sdk/platform-tools/adb \
  CONNECT_E2E_DEVICE=emulator-5554 CONNECT_E2E_TARGET=emulator-5556 \
  CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/current-call-ui \
  flutter drive -d emulator-5554 --no-pub \
  --driver=test_driver/current_call_ui.dart \
  --target=integration_test/current_call_ui_test.dart \
  --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 --dart-define=CONNECT_E2E_PORT=25556
```

物理PSTN／VoIP、多SIM／通话等待、具体callId adapter、主控麦克风／双向声音／路由仍需独立实现和验收；新入口及该E2E不能用于关闭这些要求。
