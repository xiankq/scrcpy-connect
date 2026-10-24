# 互联媒体暂存与活动原件保护

应用 Dart 的 `AppMediaCache` 管理 `media` 预览／缩略图树与启动时登记的临时 `outgoing` 原件树；`TransferCoordinator` 拥有传输任务并持有缓存预留。缓存不扫描应用根目录，不包含用户系统保存的副本、远端原件或 share_plus 自己的系统暂存副本。默认预算 512 MiB；产品偏好由 Dart 保存。这个预算不限制整个应用的磁盘占用。

## 所有权与空间准入

`media.cache.status` 返回 budgetBytes／usedBytes／protectedBytes／reclaimableBytes／reservedBytes；`clear` 只删除可回收文件，并返回实际 deletedBytes。生产写入之前计算源大小或缩略图上限及旁车空间，按文件修改时间从旧到新回收无保护的内容。空间不足以容纳受保护内容与本次写入时拒绝本次准备，不覆盖使用中的原件。预留量减去已经落盘的 part，避免重复计算；目录传输按选中批次准入。

预览／缩略图回复包含精确 UUID `cacheLeaseId`；应用命令 `media.cache.release` 只释放对应租约，重复释放无副作用。`media.cache.acquire {transferId}` 可在原件尚未落盘时取得私有传输租约，保护发布前后的目标及 part。活动传输、目录中的未完成项、结果未知与可能已有部分目标的交付记录也独立保护；`DeliveryJournal` 重开后继续提供持久保护。准入、所有权发布、交付开始和清理共用 `MediaCacheGate`，网络取回与解码不持锁。Rust 只执行必要的文件事实、字节传输及精确 FD 发布，不持有另一份缓存账本或预算。

预览源版本使用元数据散列分目录，修复缓存也写新文件，已有播放器使用的文件不被原地替换。回收原件后传输结果 `cacheEvicted=true`／`canExport=false`，不再给出可导出的 localPath；重开时也核对丢失的已完成文件与目录后代。

Flutter 页面拥有返回租约，迟到回复在页面已退出时释放自己的 UUID；图片解码期间另持引用，释放失败保守保留。当前不内置本地视频播放器，视频原件保存或交给系统应用打开。接收、传输详情和系统导出表单在使用私有原件前持有传输租约。出站分享／本机打开先执行 `media.cache.retain`，持久保留已交给外部应用的来源，不把 Sharesheet 返回当作外部读取完成。普通用户拥有的非受管文件使用 `ifManaged:true` 跳过媒体保留，不被纳入清理。

注册根和传输目的路径只允许无子符号链接的受管路径。系统临时目录可能经过平台别名；应用先创建 outgoing 并规范化路径，缓存、文件任务与交付账本使用同一根身份。新缓存所有者打开前必须先通过 ADB 文件 scope 接管并排空旧原生 worker，不能只重置 Dart 租约后复用仍被旧操作写入的路径。

## 设置与设计

正式生成路由 `/settings/media-cache`，入口位于设置的本机数据区域。页面归属 `pages/settings/media_cache/`，文件命名与组件布局遵循[页面文件布局](flutter-navigation.md#文件布局)，复用既有主题／面板。清理需要确认，区分受保护和可回收；清理完成只报告实际回收量，剩余受保护内容不会被称为全部清空。代表状态见[流程覆盖](../../designs/prod/coverage.md)，不按状态Frame数量新增产品路由。

## 已执行证据与复现

当前所有者回归位于 `app/test/media/cache/` 与 `app/test/files/delivery_journal_test.dart`；生产接线与验证范围见[本轮重构记录](architecture-refactor-validation.md)，文件任务恢复证据见[文件能力验收](file-ownership-validation.md)。旧 `rust/app/core/tests/media_cache.rs` 是迁移前夹具，不能作为保留 Rust 缓存业务的理由或当前实现的复现入口。

2026-10-18 API36真实adbd样本推入PNG，目标companion生成缩略图并取回预览/原件；持有三租约时保留，释放后回收并将传输改为不可导出。双AVD流程再经真实预览/设置清理页操作，host逐字节核对保护原件及路径消失，确认远端原件未被删。该结果属于业务迁移前实现，不能替代当前 Dart 缓存组装的复验。

应用生产接线恢复后，在 `app/` 运行 `integration_test/media_cache_test.dart` 配 `../tool/driver/media_cache.dart`；目标条件/参数按用例声明。组件与临时文件测试不等同设备运行，跨目标 cargo check 及 ARM64 签名包只证明编译／构建。

## 未完成范围

外部接收应用缺少可靠读取结束回执，持久保留不能安全自动解除，可能占满预算后拒绝新内容；显式撤回/用户管理保留项仍待实现。预算尚无用户调整入口；超预算大原件不能称完整取用。巨量小文件核算、inode/空目录回收、ENOSPC、低内存/后台死亡、写入中进程终止、全部provider和其他宿主运行未由上述样本证明。
