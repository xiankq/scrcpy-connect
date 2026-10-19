# 本机键盘的已提交文字

输入链路由“屏幕与输入工具→使用本机键盘”进入全屏远控。RemotePage监听完整TextEditingValue，composing仍进行时不发送；仅composing结束、文字未变化也会提交一次。控制器重置有防重入保护，失焦、暂停和会话失效时清空未提交缓存。入口显式请求输入焦点，避免外层实体键盘Focus先获得焦点后，隐藏TextField的autofocus不生效。

这是已提交文字的插入与已有删除路径，不是远端InputConnection／selection／composing镜像。session.ime仍缺实际生产者，密码／敏感字段识别、自动唤起、复杂选区／撤销、实际中文键盘候选与遮挡／横屏继续开放。Unicode沿用scrcpy clipboard+paste路径，会改变被控剪贴板；主控无须开启调试，被控无须额外安装 APK。

## 2026-10-18 输入验收（历史）

- 公开页面红绿：旧onChanged漏composing-only提交；新增自动焦点断言又复现入口不聚焦，两处修复后通过。组合中不发、中文emoji原文一次、暂停／失焦／换会话丢弃旧缓存均有公开页面回归。
- 最终remote_lifecycle＋communication共43项通过，`/tmp/connect-ime-calls-widget-final.log`。最终6文件严格分析无问题；新测试两处lint修正，不称首轮通过。
- 真实双AVD第七轮30秒通过，构建2.64秒／安装555ms，`/tmp/connect-remote-ime-r7.log`与`/tmp/connect-e2e/remote-ime-r7/result.json`。真实生产main／decoder／公开工具入口、session.touch聚焦系统Settings搜索框；本机输入由Flutter TestTextInput编辑协议模拟，不代表Gboard候选已实测。
- 宿主独立uiautomator六个checkpoint确认：空查询→聚焦→composing无泄漏→你好🙂精确一次→延迟仍一次→清理回空；inspectionError=null。实际原应用文字与emoji已目视。
- **第七轮未决（下节限定复验已处理）**：主控committed截图当时仍显示空查询，被控截图已显示你好🙂。截图先后与目标绘制／媒体PTS尚未对齐，不能据此归因永久停帧，也不能声明主控动态画面已跟随。需要在明确目标画面已绘制后，限定时间观察主控新像素／PTS，覆盖暂停／工具页返回。该缺口回填任务07／08／20，不围绕输入插入继续扩矩阵。

### A59限定时序复验（2026-10-18）

第八轮先捕获目标实际屏幕，再等待750ms捕获主控；延迟检查点再捕获两端，记录每次截图起止UTC。真实流程31秒通过，构建34.7秒／安装1,813ms；`/tmp/connect-remote-ime-r8.log`、`/tmp/connect-e2e/remote-ime-r8/result.json`。主控两张截图均已目视，确实显示你好🙂、对应搜索结果和远端键盘，悬浮退出覆盖在全屏画面上；目标截图原文一致，六项独立EditText检查与查询恢复通过。目标首张截图完成18:15:42.601Z，主控首张18:15:43.933Z完成；这包含刻意750ms等待与截图开销，**不是触控到像素延迟测量**。

第八轮在工具页暂停／同会话恢复后复现原操作，旧空查询差异未再出现；无需据旧截图改动生产播放器。关闭的是这条流程的“主控始终旧画面”疑点，不外推所有设备／编码的持续帧新鲜度或性能达标。自动回执只证明输入与帧可解码，动态视觉结论来自本次实际截图人工复核。

## 可复现命令

以下复现命令从仓库根目录开始，PATH含Flutter／Rust，ANDROID_HOME指向SDK。主控5554、已授权被控5556的TCP通过15556转发；目标屏幕应为Awake，系统Settings搜索可用，测试初始查询为空。

```sh
cd app
env CONNECT_E2E_ADB=/home/xiankq/Android/Sdk/platform-tools/adb \
  CONNECT_E2E_DEVICE=emulator-5554 CONNECT_E2E_TARGET=emulator-5556 \
  CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/remote-ime \
  flutter drive -d emulator-5554 --no-pub \
  --driver=../tool/driver/remote_ime.dart --target=integration_test/remote_ime_test.dart \
  --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 \
  --dart-define=CONNECT_E2E_PORT=15556
```

只停止新建会话、还原测试查询与原设置／焦点，按原状态恢复连接并忘记新增记录，不重置应用数据。所有XML、截图和回执只写/tmp。驱动按XML规则先解数字实体再解amp实体，避免把emoji或字面实体字符串读错；API36此Settings空框同时暴露text／hint为Search settings，空阶段保留rawAccessibilityText并明确识别占位，提交阶段仍严格要求完整原文。

## 失败与复验

r1目标SystemUI无响应弹窗遮住输入框；r2工具页尚未加载导致找不到Scrollable；r3实际入口焦点缺陷；r4已插入emoji但读取器未解XML数字实体。这些不算通过。r5功能30秒通过，但主控自身SystemUI ANR遮盖屏幕，目视未接受；清除该独立OS弹窗后，r6遇通话测试旧全局ENDCALL清理导致目标Asleep／首帧失败。通话夹具已改只取消自己的模拟号码，显式唤醒后r7功能通过。r7截图的新旧画面差异继续保留为A59，不能以测试总数掩盖。
