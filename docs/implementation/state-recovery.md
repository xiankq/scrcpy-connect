# 事件中断后的状态核验

本批对应 A24。恢复的是仍然存在的活动及其本地呈现，不是重放历史命令，也不覆盖进程死亡后的完整用户意图恢复。

## 边界

Rust runtime 每次发布事件，在同一短锁内分配递增 `sequence` 并写入 broadcast。通道容量仍为 256。FRB 观察者遇到 `Lagged` 时先从当前尾部重新订阅，再发 `state.resync`，不继续交付滞留旧队列；其他观察者不受影响。

`state.snapshot` 只读取本地存储、现有会话/音源/传输/活动、分享管理器及已经存在的 companion 缓存，不连接设备、不新建播放器、不启动观察进程。返回 `sequence`、`consistency: event-fenced`、`settings` 与 `devices/sessions/sources/transfers/activities/shares/companions`。前后状态 revision 不同则最多重读四次，仍不稳定返回 `state_busy`。视频帧遥测不推进状态 revision，避免持续视频使核验饥饿。

此屏障是 runtime 已观察状态的事件一致性检查，不是跨 Android 系统服务的远端事务。RPC list 缓存提交在 socket actor 中先于 oneshot 返回，并推进 revision；不会因查询再发 changed 事件造成查询循环。取消的 companion 不暴露旧可操作缓存。设置在持当前读锁时发布；分享转发从当前状态重新取值，已消费来源只触发重新核验。

## Bridge 与页面

`state.reconcile` 是 Dart Bridge 命令。并发请求合并为一次核验。开始立即发布本地 `state.resync` 并禁止新输入、媒体启动及通知/通话动作；精确 session UUID 的 UP/CANCEL、暂停与明确停止仍可清理已有活动。快照校验失败或超时后保持待核验，不把空结果当成全部结束。

读取前捕获本地播放器所有者，只清理快照里不存在或已结束、且读取期间未被替换的同一所有者。合并时仅允许当前播放器的纹理、尺寸和实际解码证据覆盖 Rust 状态，不能让旧呈现回执覆盖暂停等权威状态。成功发布 `state.resynced`，拒绝水位之前的旧事件；核验期间又有缺口或更新超过快照则重读。

AppController 在同步通知页面监听器之前落地不可变快照，校准 SessionViews，并废弃旧设备、设置、分享请求及旧设置保存回执。远控立即停止新输入，清理原会话触点；成功后只核对原 UUID，可见窗口确认新像素后恢复，不可见窗口维持暂停。不存在的窗口清除 Texture 并提供“重新检查”，该动作只调用核验命令，不创建替代窗口。旧导航/文本等初始动作不再执行。终态同步失效正在等待的恢复 epoch，迟到成功回执与输出事件不能解除终态暂停。

剪贴板取消旧轮询、旧队列及晚到的系统读回；前台且目标可用后重新建立当前对象基线，后台不读取。首次核验后，自动 `notifications.list/calls.list/clipboard.get` 使用 `allowStart:false`；已有观察仍可查询。无观察时返回 unknown、stopped或observation_required；列表不再启动观察，用户明确核验须调用`observation.start`，随后等待事件/status确认。`allowStart`只控制共享helper资格，不能替代观察意图。

## 编码会话边界

核验的真实复验发现连续 reset 会在首个关键帧前发出多组 session/CSD。HTTP relay 在新的 Dimensions 标记处废弃前一 session 尚未成帧的配置，只合并同一 session 内的配置分包。相同 CSD 保留现有 HTTP 流，变化 CSD 创建下一代；不靠放宽 AVC 单活动 SPS 约束吞掉混合配置。真实 TCP 回归同时检查两条路径，原配置容量、64 单位和半包超时限制保留。

## 验证范围

默认回归覆盖实际容量的 broadcast 溢出、独立观察者、快照水位、晚到设置与分享事件、companion 查询/通知交错、取消缓存、同 ID 的呈现恢复、失效所有者清理、超时/取消、输入释放、覆盖页面返回及剪贴板冻结。真实 Android 流程使用 `integration_test/state_recovery_test.dart` 和生产 Bridge 的显式核验入口；它不声称在 AVD 中人为制造了 FRB 溢出。实际执行结果、命令和截图记录在 [validation.md](validation.md)。

仍需后续实现及验收：断网后的用户意图恢复、进程回收/系统停止、持续通知与后台发布、资源仲裁、完整文件恢复及四宿主整包。再次只读审查发现embedded设置/传输主标签绕过PageFrame，原共享核验入口未覆盖这两条路径（A39），须单独修复并走实际typed路由回归。不能以本批结束关闭这些任务。
