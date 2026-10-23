# Release JNI 回调被 R8 裁掉

2026-10-23，在普通 Release、Android16 x86_64 AVD重复复现：打开远控时 `GetMethodID` 找不到 `onFrame(II)V`，代码带着待处理异常继续查 `onPcm([B)J`，ART在 `nativeCreate` 中SIGABRT。Release usage/mapping确认回调被移除，故障发生在实际解码前。

原因是JNI按字面量反向访问Java成员，而插件没有随consumer规则保留回调；Java→native入口的默认保护不覆盖反向调用。[Android官方JNI keep规则](https://developer.android.com/topic/performance/app-optimization/keep-rule-examples#jni)

修复及普通Release复验已记录在[移动整改A18](../implementation/scrcpy-audit-mobile-apple-fixes.md)和[最终验收](../implementation/scrcpy-audit-fixes.md)。本报告不再保留已失效APK摘要、临时PID/日志路径和未实施建议。

持续有效的回归要求是：库分发精确consumer规则，JNI逐次检查引用/方法查找及pending exception，并验证启用R8的普通Release媒体创建。Debug媒体通过、Release只启动设备首页，均不能覆盖该路径。用户arm64截图中的 `device.screen.state` 错误没有此JNI栈，不能据此判为同一根因。
