# 本机键盘的已提交文字

远控键盘监听完整TextEditingValue：composing中不发，结束即使text未变也提交一次；重置防重入，失焦/暂停/会话失效丢弃未提交缓存，入口请求焦点。Unicode走scrcpy clipboard+paste，会改变被控剪贴板；不是远端InputConnection/selection/composing镜像。当前输入范围归[交互规则](../../designs/prod/interaction-rules.md)。

2026-10-18公开页面回归覆盖组合不泄漏、中文emoji一次、迟到重复与旧会话缓存丢弃。双API36 AVD通过正式main/decoder/工具聚焦Settings搜索，用TestTextInput模拟编辑；host独立uiautomator核对空查询、聚焦、组合中、你好🙂精确一次及延迟不重复。后续两端截图确认同会话持续更新，含刻意等待，不能作为输入延迟样本；未实测Gboard中文候选。

入口为app/integration_test/remote_ime_test.dart及tool/driver/remote_ime.dart，从app按[隔离规则](validation.md#复现入口)运行。目标需已授权、唤醒、搜索为空；只清本次会话、查询/设置/焦点及新增记录。密码识别、复杂选区/撤销、中文候选、遮挡/横屏及旧系统仍待实现或验收。
