# 接续当前系统通话界面

`calls.open`只请求被控设备当前系统通话界面，不接受callId，不接听/拒接/挂断或切换音频。Rust要求显式实时观察，companion重查非空闲聚合状态与当前用户，再按可用showInCallScreen签名调用；接口/权限错误明确返回，不偷偷新建观察。

有效回执为 `target=currentSystemCall`、`acceptedBySystem=true`、`uiVisible=null`、`callControlled=false`。Flutter收到后才进入共享全屏远控，系统接受请求本身不证明可见。具体呼叫动作因无法可靠原子定位而移除，双向通话音频未实现；产品规则见[交互规则](../../designs/prod/interaction-rules.md)。

## 已执行证据

2026-10-18公开Runtime/页面回归核对无观察拒绝、失败不打开远控及不调用旧全局动作。API36隔离目标先让Settings前台，再创建自有模拟来电，调用后独立dumpsys确认InCallActivity且同一号码仍ringing；旧动作不能结束替代呼叫。

正式CallsPage流程另从真实来电提醒进入通话页，再打开系统界面和RemotePage，核对真实解码/两端截图及同一Telecom/Telephony身份。未点击接听/拒接；被控自身首次全屏提示也是真实像素，不能据被遮标题声称完整可见。先前gsm list只返回OK、提醒sheet遮挡底层按钮的失败均未记通过；使用真实入口和独立身份检查修正夹具。

测试拒绝已有通话，只取消本次模拟号码并等待idle，不发送全局ENDCALL。它不是物理PSTN/VoIP、多SIM/等待、逐callId安全控制或双向音频验收。

## 可复现入口

隔离无通话目标的Rust用例：`companion_android` 中 `rust_runtime_observes_rapid_replacement_and_refuses_unsafe_aggregate_actions`，按声明设置ANDROID_ADB、ANDROID_TARGET_SERIAL、INTEROP_CORE_TEST_ENDPOINT并显式 `--ignored --test-threads=1`。

正式页面从 `app/` 运行：

```sh
CONNECT_E2E_ADB=<SDK>/platform-tools/adb \
CONNECT_E2E_DEVICE=<主控serial> CONNECT_E2E_TARGET=<目标serial> \
CONNECT_E2E_CAPTURE_DIR=<新临时目录> \
flutter drive -d <主控serial> \
  --driver=../tool/driver/current_call_ui.dart --target=integration_test/current_call_ui_test.dart \
  --dart-define=CONNECT_E2E_ADDRESS=<地址> --dart-define=CONNECT_E2E_PORT=<连接端口>
```

该记录是历史API36系统入口样本，当前companion来源/摘要由[构建清单](../../servers/companion/README.md)维护，不在此重复旧JAR摘要或构建回执。
