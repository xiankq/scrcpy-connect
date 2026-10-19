# 互联媒体暂存与活动原件保护

管理 Core 的 `media` 预览／缩略图树与启动时登记的应用临时 `outgoing` 原件树；不扫描应用根目录，不包含用户系统保存的副本、远端原件、播放器内部缓存或 share_plus 自己的系统暂存副本。默认预算 512 MiB，配置持久化。这个预算不能宣称限制整个应用的磁盘占用。

## 所有权与空间准入

`media.cache.status` 返回 budgetBytes／usedBytes／protectedBytes／reclaimableBytes／reservedBytes；`clear` 只删除可回收文件，并返回实际 deletedBytes。生产写入之前计算源大小或缩略图上限及旁车空间，按文件修改时间从旧到新回收无保护的内容。空间不足以容纳受保护内容与本次写入时拒绝本次准备，不覆盖使用中的原件。预留量减去已经落盘的 part，避免重复计算；目录传输按选中批次准入。

预览／缩略图回复包含精确 UUID `cacheLeaseId`；`media.cache.release` 只释放对应租约，重复释放无副作用。`media.cache.acquire {transferId}` 可在原件尚未落盘时取得私有传输租约，保护发布前后的目标及 part。活动传输、目录中的未完成项、结果未知与可能已有部分目标的交付记录也独立保护；持久交付账本重开后继续生效。准入、所有权发布、交付开始和清理共用短门锁，网络取回与解码不持锁。

预览源版本使用元数据散列分目录，修复缓存也写新文件，已有播放器使用的文件不被原地替换。回收原件后传输结果 `cacheEvicted=true`／`canExport=false`，不再给出可导出的 localPath；重开时也核对丢失的已完成文件与目录后代。

Flutter 页面拥有返回租约，迟到回复在页面已退出时释放自己的 UUID。图片另持有至文件解码首帧或错误，视频另持有至 `VideoPlayerController.dispose()` 完成；释放失败保守保留。接收、传输详情和系统导出表单在使用私有原件前持有传输租约。出站分享／本机打开先执行 `media.cache.retain`，持久保留已交给外部应用的来源，不把 Sharesheet 返回当作外部读取完成。普通用户拥有的非受管文件使用 `ifManaged:true` 跳过媒体保留，不被纳入清理。

注册根和传输目的路径只允许无子符号链接的受管路径。系统临时目录可能经过平台别名；Flutter 先创建 outgoing 并规范化路径，Core 同样规范化自己的数据根。所有后续接收目的地使用同一规范路径。没有新增 Android 业务代码或依赖。

## 设置与设计

正式生成路由 `/settings/media-cache`，入口位于设置的本机数据区域。一页一个浅层目录及 `_page.dart` 文件，复用既有主题／面板。清理需要确认，区分受保护和可回收；清理完成只报告实际回收量，剩余受保护内容不会被称为全部清空。Pencil 同一文件的偏好类别补两页，产品说明见 [覆盖](../../designs/prod/coverage.md)。

## 验证

- 公开 Runtime：五项协议／真实临时文件测试通过，包括持有／精确释放、源变化旧消费者保留、保护预算拒绝、正在取回时 status／clear 响应、真实私有 pull 回收及投影、交付与分享跨 Runtime 重开保护。交付十三项、传输状态三项、缩略图验证一项回归通过。
- 真实 API36 AVD：`INTEROP_CORE_TEST_ENDPOINT=127.0.0.1:25556 cargo test -p interop-core --test media_cache android_thumbnail_preview_and_original_have_real_file_leases_through_clear -- --ignored --nocapture`，2.90 秒通过。真实 ADB 推入 PNG，经 companion 生成 JPEG 缩略图、取回预览与私有原件；三租约持有时清理保留，释放后三文件回收、usedBytes=0、传输不可导出，精确远端夹具删除。不是 mock 最终链路。
- Flutter：迟到缩略图／预览回复的公开页面红测从零释放变为精确一次；设置导航／清理取消与确认／实际字节回执及九项调度回归，十二项通过。完整应用 256 项通过（1分26秒）；此前设置测试未等待首帧就定位懒构建项失败已修正，不把该次记为通过。严格分析通过。
- 独立复核发现状态页自己的租约阻止失败任务重传，接收／详情两页的公开中断红测均复现。改为跟随实际任务状态，仅保护准备或可导出的原件，保存表单仍独立保护；相关二十项回归通过，之后清除旧异步快照再跑十一项通过。支持目录别名的主数据根与 outgoing 均规范化，截图的本机打开继续使用规范路径。
- Core 全部测试 136 passed／48 ignored（`/tmp/connect-media-cache-core-regression.log`），忽略项不计通过；上述真实 Android 项单独显式执行。Bridge 全量 106 项通过，Core clippy 全 targets 严格通过，生成一致性 164 输入及应用严格分析通过。
- **正式双 AVD E2E r4**：13秒、构建12.4秒／安装478ms，`/tmp/connect-media-cache-r4.log`、`/tmp/connect-e2e/media-cache-r4/result.json`，全部七项完成／独立核验字段为true，hostErrors为空。实际 PNG 经 ADB 推入被控手机，正式预览页解码，正式清理页回收缩略图但保留预览与私有取回原件，退出预览／精确释放后再次正式清理，宿主以逐字节比较和路径不存在独立核验，并确认远端原件未被清理、最后精确夹具删除。预览、两次清理实截图已目视；本机暂存最终0 B，不能据此声称所有应用缓存为零。

前序失败保留：r1普通main后测试插件注册缺失，离线pub get恢复自动注册；r2宿主只接受`/data/user/0`却拒绝实际规范化的`/data/data`，限定同一应用的两种Android别名后r3保护阶段原文通过；r3第二次清理时夹具未等待真实路由转场，命中AbsorbPointer而未打开确认。r4等待实际animation完成／可命中动作，未绕过确认或以直接Core清理替代页面操作。失败轮均未计完整通过。

新Core对aarch64-apple-ios／aarch64-apple-darwin／x86_64-pc-windows-msvc交叉check通过，分别30.93／17.04／20.31秒，日志`/tmp/connect-media-cache-core-cross-checks.log`及`/tmp/connect-media-cache-core-windows-check.log`；不是这些宿主Flutter最终链接／整包或运行证据。首次误选本机未安装的Windows GNU target而报缺core，已核对实际安装的MSVC target重新通过，没有把该失败隐藏成GNU支持。当前Android arm64 release另行构建与独立签名检查通过，见[打包](android-packaging.md)。

## 仍开放

外部应用缺少可靠的读取结束回执，持久保留尚无可安全自动解除的机制；因此可能逐渐占满预算，届时拒绝新内容，不静默删已分享原件。完整的显式授权撤回与用户可管理保留项仍需实现。预算目前可通过Core配置，尚无面向用户的调整入口；超过默认预算的大原件会拒绝准备，需要补调整／直接交付等产品路径，不能称完整大文件取用。目录遍历按当前受管树核算，巨量既有小文件的时延与 inode／空目录回收仍待实测；当前并非长期压力／ENOSPC 验收。实际大视频、低内存／后台杀进程、写入中进程死亡、所有系统文件提供方及其他宿主运行也未由这些测试证明。A51 保持部分交付，任务10不关闭；下一批按用户最新优先级推进视频流性能、首帧速度和连接稳定性，USB共享选择顺延。
