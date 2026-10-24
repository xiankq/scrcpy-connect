# 接续当前系统通话界面

产品范围归[交互规则](../../designs/prod/interaction-rules.md)。`calls.open` 不接收 `callId`；应用 Dart 的 [ObservationCoordinator](../../app/lib/companion/observation_coordinator.dart) 核验显式观察及当前连接准入，companion 重查当前用户及非 idle 聚合状态后调用可用 `showInCallScreen` 签名。回执为 `currentSystemCall`、`acceptedBySystem=true`、`uiVisible=null`、`callControlled=false`；页面收到后才进共享远控。接口或权限错误明确失败，不自动新建观察；逐呼叫控制及双向通话音频未实现。

2026-10-18公开Runtime/页面回归覆盖无观察拒绝、失败不打开远控及无旧全局动作。API36隔离目标以Settings前台和自有模拟来电验证InCallActivity、同号码仍ringing；正式CallsPage再经真实提醒进入，核对解码及两端截图。系统接受请求与实际可见分别取证。

上述设备证据来自迁移前 `companion_android` 的 `rust_runtime_observes_rapid_replacement_and_refuses_unsafe_aggregate_actions`，旧 Runtime 测试已移除。当前主机回归入口为 [observation_coordinator_test.dart](../../app/test/companion/observation_coordinator_test.dart) 和 [communication_test.dart](../../app/test/communication_test.dart)；页面入口为 `app/integration_test/current_call_ui_test.dart` 及 `tool/driver/current_call_ui.dart`，从 app 按[隔离规则](validation.md#复现入口)运行。拒绝已有通话，只取消本次模拟号码后等 idle，不发全局 ENDCALL。未验物理 PSTN/VoIP、多 SIM/等待或 OEM；companion 来源归[服务构建](../../servers/companion/README.md)，当前接线与验收范围见[本轮重构记录](architecture-refactor-validation.md)。
