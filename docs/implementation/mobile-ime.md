# 本机键盘的已提交文字

全屏远控的键盘工具监听完整TextEditingValue：composing中不发送，composing结束即使文字不变也提交一次；重置有防重入，失焦/暂停/会话失效丢弃未提交缓存，入口显式请求焦点。

这是已提交文字插入及已有删除路径，不是远端InputConnection/selection/composing镜像。Unicode沿scrcpy clipboard+paste，会改变被控剪贴板。`session.ime`实际生产者、密码/敏感字段识别、自动唤起、复杂选区/撤销、真实中文候选、遮挡与横屏仍待实现或验收。

## 已执行证据

2026-10-18公开页面回归先复现composing-only漏提交和入口焦点缺陷，修复后覆盖组合不泄漏、中文emoji一次、迟到重复及旧会话缓存丢弃。

API36双AVD正式main/decoder/公开工具流程通过scrcpy touch聚焦Settings搜索，本机以TestTextInput模拟编辑协议。host独立uiautomator检查空查询、聚焦、组合中、`你好🙂`精确一次、延迟不重复与清理恢复；不代表Gboard候选实测。

早期主控截图仍空、目标已含新字，不能由首帧通过推断持续更新。限定复验先取目标屏幕，等待750ms再取主控，并在延迟检查点再取两端；两组主控图实际看见新字/结果/远端键盘，同会话工具页暂停恢复后未再出现旧画面疑点。刻意等待和截图开销不算触控到像素延迟，更不能外推其他设备/编码性能。

早期SystemUI ANR、工具未加载、XML数字实体未解码及通话夹具全局ENDCALL令目标睡眠的失败未计通过。后者已改精确清理自有模拟号码；没有据夹具失败调整生产播放器或放宽原文断言。

## 可复现入口

使用当前已授权、Awake且Settings搜索初始为空的隔离目标，从 `app/` 运行：

```sh
CONNECT_E2E_ADB=<SDK>/platform-tools/adb \
CONNECT_E2E_DEVICE=<主控serial> CONNECT_E2E_TARGET=<目标serial> \
CONNECT_E2E_CAPTURE_DIR=<新临时目录> \
flutter drive -d <主控serial> \
  --driver=../tool/driver/remote_ime.dart --target=integration_test/remote_ime_test.dart \
  --dart-define=CONNECT_E2E_ADDRESS=<地址> --dart-define=CONNECT_E2E_PORT=<连接端口>
```

夹具只停止新建会话、恢复自己的查询/设置/焦点并忘记新增记录，不清空应用数据。XML读取器处理数字与amp实体；API36空输入占位文字与提交原文分别核验。真实中文IME、旧系统、密码限制和当前依赖的完整动态验证不由该历史样本关闭。
