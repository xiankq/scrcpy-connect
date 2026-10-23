# 事件中断后的状态核验

本文规定同一 Runtime 内事件中断后的核验屏障。应用打开账本的跨 Runtime 恢复见 [应用打开记录与恢复](app-launch-recovery.md)；进程死亡后的完整用户意图恢复仍待验收。产品恢复行为以 [交互规则](../../designs/prod/interaction-rules.md) 为准。

## 边界

Rust runtime 每次发布事件，在同一短锁内分配递增 `sequence` 并写入 broadcast。通道容量仍为 256。FRB 观察者遇到 `Lagged` 时先从当前尾部重新订阅，再发 `state.resync`，不继续交付滞留旧队列；其他观察者不受影响。

Rust `state.snapshot` 只读取本地存储、现有会话/音源/活动、分享管理器及已经存在的 companion 缓存，不连接设备、不新建播放器、不启动观察进程。返回 `sequence`、`consistency: event-fenced` 及原生状态；Dart `DeviceRuntime` 再组合偏好、文件任务与对应活动。原生状态前后 revision 不同则最多重读四次，仍不稳定返回 `state_busy`。视频帧遥测不推进状态 revision，避免持续视频使核验饥饿。

此屏障是 runtime 已观察状态的事件一致性检查，不是跨 Android 系统服务的远端事务。RPC list 缓存提交在 socket actor 中先于 oneshot 返回，并推进 revision；不会因查询再发 changed 事件造成查询循环。取消的 companion 不暴露旧可操作缓存。设置在持当前读锁时发布；分享转发从当前状态重新取值，已消费来源只触发重新核验。

## Bridge 与页面

`state.reconcile` 是 Dart Bridge 命令。并发请求合并为一次核验。开始立即发布本地 `state.resync` 并禁止新输入、媒体启动及通知/通话动作；精确 session UUID 的 UP/CANCEL、暂停与明确停止仍可清理已有活动。快照校验失败或超时后保持待核验，不把空结果当成全部结束。

读取前捕获本地播放器所有者，只清理快照里不存在或已结束、且读取期间未被替换的同一所有者。合并时仅允许当前播放器的纹理、尺寸和实际解码证据覆盖 Rust 状态，不能让旧呈现回执覆盖暂停等权威状态。成功发布 `state.resynced`，拒绝水位之前的旧事件；核验期间又有缺口或更新超过快照则重读。

AppController 在同步通知页面监听器之前落地不可变快照，校准 SessionViews，并废弃旧设备、设置、分享请求及旧设置保存回执。远控立即停止新输入，清理原会话触点；成功后只核对原 UUID，可见窗口确认新像素后恢复，不可见窗口维持暂停。不存在的窗口清除 Texture 并提供“重新检查”，该动作只调用核验命令，不创建替代窗口。旧导航/文本等初始动作不再执行。终态同步失效正在等待的恢复 epoch，迟到成功回执与输出事件不能解除终态暂停。

剪贴板取消旧轮询、旧队列及晚到的系统读回；前台且目标可用后重新建立当前对象基线，后台不读取。首次核验后，自动 `notifications.list/calls.list/clipboard.get` 使用 `allowStart:false`；已有观察仍可查询。无观察时返回 unknown、stopped或observation_required；列表不再启动观察，用户明确核验须调用`observation.start`，随后等待事件/status确认。`allowStart`只控制共享helper资格，不能替代观察意图。

## 编码会话边界

连续 reset 可在首个关键帧前产生多组 session/CSD。Rust `VideoPackets` 遇到新尺寸标记即清除上一段尚未成帧的配置，只合并当前段；等到关键帧后配置原生 packet source，再交付压缩包。配置容量、64 单元与完整包期限仍有界；当前路径不经过 HTTP relay 或容器封装。

## 通知与系统提醒

通知页不保留回复草稿或回复提交状态；权威恢复只刷新当前有效通知、打开与清除能力，不恢复旧动作。主控系统提醒在事件缺口时精确撤回；权威快照形成安静基线，旧 payload 不授权远端动作。平台发布、点击与冷启动边界见 [系统提醒](system-notifications.md)。

## 应用打开与初始动作

START_APP 在编码或渲染失败前可能已经产生真实任务副作用。提交边界先登记固定操作身份；后续失败保留 unknown 并取消捕获，视频输出清理不删除该记录。快照尚未绑定 sessionId 时也按设备与包名保护未知结果。手机主屏与独立窗口共用未决记录门禁，不能通过另一入口绕过。

私有持久账本在 Runtime 重建时将 pending/observed 保守转为 unknown；明确关闭只结束记录和所属控制资源，保留真实应用任务。排队启动在提交许可撤销后不能因迟到 ACK 再发送。详细状态、上限与验收见 [应用打开记录与恢复](app-launch-recovery.md)。

尚未提交的页面初始动作在启动期间进入后台时保留于该页面；回到前台且确认可输入后只提交一次。提交前消费意图，回执丢失不自动重发。迟到输出、前后台切换和核验成功均不能解除未知启动保护。

## 验证范围

默认回归覆盖实际容量的 broadcast 溢出、独立观察者、快照水位、晚到设置与分享事件、companion 查询/通知交错、取消缓存、同 ID 的呈现恢复、失效所有者清理、超时/取消、输入释放、覆盖页面返回及剪贴板冻结。真实 Android 流程使用 `app/integration_test/state_recovery_test.dart` 和生产 Bridge 的显式核验入口，不声称在 AVD 人为制造 FRB 溢出。执行结果、命令及截图见 [验收记录](validation.md)。

公开 Runtime 重建与应用启动门禁已有验证，不能据此关闭断网后的用户意图恢复、Android 杀进程/系统停止、后台通知完整权限/锁屏矩阵、资源仲裁、完整文件恢复或四宿主整包要求。历史入口缺口与后续修复仍按验收记录各自的阶段解释。
