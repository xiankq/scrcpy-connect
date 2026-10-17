# 原文件取回、系统保存与分享

单项文件／相册取用由固定的传输任务持有来源，不依赖当前焦点设备。`ReceiveContentRoute` 从权威任务记录核验 ID；页面继续核验设备、方向和私有暂存范围。准备时展示进度、冲突、失败和精确取消；只有后端确认完整原件可导出后，才出现系统保存或分享操作。

## 三个不同的完成点

| 阶段 | 完成依据 | 不代表 |
| --- | --- | --- |
| 取回本机暂存 | ADB 取回完整、源未变化、原子发布成功，任务 `canExport` | 已保存到用户选择的系统位置 |
| 系统保存 | 共享复制／同步、提供方错误检查与关闭、目标元数据核验 | 云端远程副本已经提交或同步 |
| 系统分享 | 交给系统选择的接收应用；关闭和未知结果单独呈现 | 接收应用已发送给他人或保存完成 |

`DocumentExportForm` 为准备页与传输详情复用同一保存交互。取消系统选择器保留原件暂存；取消写入可能留下部分目标，不能显示成保存成功。请求异常导致回执缺失时，页面保留结果未知状态，要求用户核对系统文件后再重试。离页只取消本次系统文档操作，不自动重放，也不删除被控原件。

## 共享与系统适配边界

Flutter 承担页面、任务归属与交互；共享 Dart 协调树规划、数量／容量限制和操作生命周期；Rust 持有借用 FD 的副本并复制、核验和同步。Android 适配仅管理系统选择器、URI／授权和原始 PFD，不增加文件业务或视频循环。

完成提供方描述符时，共享层显式传递 `success`／`abort`。成功路径执行 `checkError → close → checkError`，各步失败也继续释放并保留首错；失败／取消发送 `closeWithError`。没有实际 lease 的回执不能确认成功。复制本身失败时，关闭失败不能覆盖原错误。上述 API 不提供远端持久提交 ACK；契约与固定 AOSP 来源见[提供方研究](../research/provider-output-streams.md)。

兼容范围仍为支持 `rw` 且提供可核验空普通文件、定位和同步能力的提供方。不能把系统选择器返回的 URI 当作排他新建凭证，也不能自动切换到可能截断已有内容的 `w`。非空目标、只支持管道写入、授权失效和提供方异常均须保留来源并明确结果。管道／云提供方的完整矩阵尚未验收。

## Android 私有文件的发布

真实普通应用受到 SELinux 限制，私有缓存的硬链接同样可能返回 `EACCES`。Linux／Android 的文件取回与文档暂存发布共用 `renameat2(RENAME_NOREPLACE)`：已有目标原子拒绝，保持原目标及未提交 part；成功后核对身份并同步目录。发布后的身份或同步无法确认时返回 `result_unknown`，不能自动再次提交或删除结果。

调用使用 libc 对应架构的 `SYS_renameat2`，不依赖 Bionic API 30 才提供的动态符号。旧内核／文件系统／厂商策略不支持时安全失败，不降级为会覆盖已有目标的普通 rename。实际来源：固定 [Bionic 声明](https://android.googlesource.com/platform/bionic/+/06356e41c5ed7b12220b24c05ba4fdb873b126a7/libc/include/stdio.h#260)、[旧系统应用 syscall 策略](https://android.googlesource.com/platform/bionic/+/f711b078b9656f7dbb52a046a7f992a450e8fa13/libc/seccomp/arm64_policy.cpp#36)及 [Linux rename 契约](https://man7.org/linux/man-pages/man2/rename.2.html)。这不提供对同权限恶意并发写者的事务隔离。

## 可复现验收

公开 CopyManager 回归在独立 Linux 子进程禁止 `linkat`，验证成功发布、part 消失、已有目标和未提交 part 保全；该回归不冒充 Android SELinux 验收。Bridge 测试覆盖成功／中止完成信号、迟到回执／取消、lease 丢失及关闭错误；原生 JVM 端口实际检查关闭顺序与异常收束。

双 AVD 自动流程使用真实 `app.main`、Rust ADB、文件详情和任务准备页。host 生成唯一 UTF-8 原件，通过实际系统文件选择器取消／保存，再通过实际 Sharesheet 选择独立测试接收器。保存位置由 host 独立读字节，接收器凭实际 content URI 授权读内容并计算 SHA-256。缺失任一回执均失败。接收器仅安装在主控 AVD；不进入产品、被控设备或发布依赖。

```sh
rtk proxy python3 tool/e2e/content_delivery_fixture/build.py
# 工作目录 apps/connect；PATH 包含 Rust 和 Flutter。
rtk proxy env CONNECT_E2E_ADB=/home/xiankq/Android/Sdk/platform-tools/adb \
  CONNECT_E2E_DEVICE=emulator-5554 CONNECT_E2E_TARGET=emulator-5556 \
  CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/content-delivery \
  flutter drive -d emulator-5554 --no-pub \
  --driver=test_driver/content_delivery.dart \
  --target=integration_test/content_delivery_test.dart \
  --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 \
  --dart-define=CONNECT_E2E_PORT=15556
```

运行结果、失败与复验记录见[实施验收](validation.md)。单项文本、JPEG及MP4的实际系统交付已有证据；当前整体验收仍需批量取用、目录／提供方矩阵、长原件预览活动、媒体异常组合和进程重建后的任务意图恢复。系统目标／测试 APK 的精确清理由 host 确认；用户语义要求保留的私有暂存没有通过清空应用数据去掩盖。

## 相册入口的验收变体

同一真实流程支持`text`、`image`、`video`三种明确样本。媒体测试须同时设置host环境`CONNECT_E2E_CONTENT_KIND=image`（或`video`）和Flutter参数`--dart-define=CONNECT_E2E_CONTENT_KIND=image`，并将`CONNECT_E2E_FFMPEG`指定为host FFmpeg绝对路径。工具只生成320×180 JPEG或6秒H264 MP4临时样本，不是产品运行依赖。host独立读取样本、计算hash并核验导出；严格检查接收MIME，不只比长度。

媒体变体从真实相册网格进入：目标缩略图必须解码出像素，原件预览也必须加载；视频检查真实时钟前进、暂停、拖动定位和静音。之后仍经过实际系统选择器取消/保存、Sharesheet接收及字节/hash/grant核验。被控唯一源分别位于Pictures/Movies，主控导出位于Downloads，两处路径单独拥有和精确清理。此变体不证明超2MiB原件、所有媒体格式、媒体索引分页或云提供方能力。
