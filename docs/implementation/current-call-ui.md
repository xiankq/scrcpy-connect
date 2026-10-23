# 接续当前系统通话界面

产品范围归[交互规则](../../designs/prod/interaction-rules.md)。calls.open不接收callId；Rust要求显式观察，companion重查当前用户及非idle聚合状态后调用可用showInCallScreen签名。回执为currentSystemCall、acceptedBySystem=true、uiVisible=null、callControlled=false；Flutter收到后才进共享远控。接口/权限错误明确失败，不自动新建观察；逐呼叫控制及双向通话音频未实现。

2026-10-18公开Runtime/页面回归覆盖无观察拒绝、失败不打开远控及无旧全局动作。API36隔离目标以Settings前台和自有模拟来电验证InCallActivity、同号码仍ringing；正式CallsPage再经真实提醒进入，核对解码及两端截图。系统接受请求与实际可见分别取证。

原生入口为companion_android中的rust_runtime_observes_rapid_replacement_and_refuses_unsafe_aggregate_actions，显式ignored、单线程并按用例配置目标。页面入口为app/integration_test/current_call_ui_test.dart及tool/driver/current_call_ui.dart，从app按[隔离规则](validation.md#复现入口)运行。拒绝已有通话，只取消本次模拟号码后等idle，不发全局ENDCALL。未验物理PSTN/VoIP、多SIM/等待或OEM；companion来源归[服务构建](../../servers/companion/README.md)。
