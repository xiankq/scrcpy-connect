# 互联媒体暂存与活动原件保护

管理 Core 的 `media` 预览／缩略图树与启动时登记的应用临时 `outgoing` 原件树；不扫描应用根目录，不包含用户系统保存的副本、远端原件、播放器内部缓存或 share_plus 自己的系统暂存副本。默认预算 512 MiB，配置持久化。这个预算不能宣称限制整个应用的磁盘占用。

## 所有权与空间准入

`media.cache.status` 返回 budgetBytes／usedBytes／protectedBytes／reclaimableBytes／reservedBytes；`clear` 只删除可回收文件，并返回实际 deletedBytes。生产写入之前计算源大小或缩略图上限及旁车空间，按文件修改时间从旧到新回收无保护的内容。空间不足以容纳受保护内容与本次写入时拒绝本次准备，不覆盖使用中的原件。预留量减去已经落盘的 part，避免重复计算；目录传输按选中批次准入。

预览／缩略图回复包含精确 UUID `cacheLeaseId`；`media.cache.release` 只释放对应租约，重复释放无副作用。`media.cache.acquire {transferId}` 可在原件尚未落盘时取得私有传输租约，保护发布前后的目标及 part。活动传输、目录中的未完成项、结果未知与可能已有部分目标的交付记录也独立保护；持久交付账本重开后继续生效。准入、所有权发布、交付开始和清理共用短门锁，网络取回与解码不持锁。

预览源版本使用元数据散列分目录，修复缓存也写新文件，已有播放器使用的文件不被原地替换。回收原件后传输结果 `cacheEvicted=true`／`canExport=false`，不再给出可导出的 localPath；重开时也核对丢失的已完成文件与目录后代。

Flutter 页面拥有返回租约，迟到回复在页面已退出时释放自己的 UUID。图片另持有至文件解码首帧或错误，视频另持有至 `VideoPlayerController.dispose()` 完成；释放失败保守保留。接收、传输详情和系统导出表单在使用私有原件前持有传输租约。出站分享／本机打开先执行 `media.cache.retain`，持久保留已交给外部应用的来源，不把 Sharesheet 返回当作外部读取完成。普通用户拥有的非受管文件使用 `ifManaged:true` 跳过媒体保留，不被纳入清理。

注册根和传输目的路径只允许无子符号链接的受管路径。系统临时目录可能经过平台别名；Flutter 先创建 outgoing 并规范化路径，Core 同样规范化自己的数据根。所有后续接收目的地使用同一规范路径。没有新增 Android 业务代码或依赖。

## 设置与设计

正式生成路由 `/settings/media-cache`，入口位于设置的本机数据区域。页面归属 `pages/settings/media_cache/`，文件命名与组件布局遵循[页面文件布局](flutter-navigation.md#文件布局)，复用既有主题／面板。清理需要确认，区分受保护和可回收；清理完成只报告实际回收量，剩余受保护内容不会被称为全部清空。代表状态见[流程覆盖](../../designs/prod/coverage.md)，不按状态Frame数量新增产品路由。

## 已执行证据与复现

公开Runtime/真实临时文件回归覆盖精确租约释放、源变化后旧消费者保留、预算拒绝、取回中status/clear、私有pull回收投影，以及交付/分享跨Runtime重开保护。页面回归核对迟到UUID释放、失败任务重传不被详情页自己的租约阻塞、取消/确认及真实回收字节；不是设备结果。

2026-10-18 API36真实adbd样本推入PNG，目标companion生成缩略图并取回预览/原件；持有三租约时保留，释放后回收并将传输改为不可导出。正式双AVD流程再经真实预览/设置清理页操作，host逐字节核对保护原件及路径消失，确认远端原件未被删；未用清空应用数据掩盖保护问题。

复现用 `crates/interop_core/tests/media_cache.rs` 的显式设备用例，或在 `app/` 运行 `integration_test/media_cache_test.dart` 配 `tool/driver/media_cache.dart`；目标条件/参数按用例声明。跨目标cargo check及ARM64签名包只证明编译/构建，不证明这些宿主已运行。

## 未完成范围

外部接收应用缺少可靠读取结束回执，持久保留不能安全自动解除，可能占满预算后拒绝新内容；显式撤回/用户管理保留项仍待实现。预算可由Core配置，尚无用户调整入口；超预算大原件不能称完整取用。巨量小文件核算、inode/空目录回收、ENOSPC、低内存/后台死亡、写入中进程终止、全部provider和其他宿主运行未由上述样本证明。
