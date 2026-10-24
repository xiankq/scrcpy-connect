# 共享存储相册检查与快照分页

产品范围归[内容规格](../../designs/prod/content-and-transfer.md)。Dart `FileCatalog` 经类型化执行器扫描 /sdcard，以扩展名识别图片/视频，modified为文件修改时间；不是MediaStore或其他用户/卷。共享预算归[文件所有者](file-ownership.md)，图库另限4096目录、25000媒体项、8MiB结果。

应用 `ApplicationCommandDispatcher` 经无状态 `FileCommands` 将 `media.list`／`media.scan.cancel` 分发给 `FileCatalog`，不经过 Rust 产品命令路由。首次建立scanId，扫描时返回进度，完成后按modified降序/path升序冻结分页；刷新生成新快照，错设备/过期ID拒绝。离页/断开/关闭只取消所属扫描。排除Android/data、Android/obb及子符号链接；权限、非法名称、截断或预算耗尽保留部分结果，原件取用仍重验。目录兼容见[旧协议](android-target-compatibility.md#旧协议与文件服务)。

缩略图共享队列每controller/device最多128等待、同设备一次实际请求；离屏取消精确operationId，旧请求结束才释放队列，仅busy有限重试。

当前取消/分页/部分结果及组装证据见[能力验收](file-ownership-validation.md)。app/integration_test/gallery_index_test.dart配tool/driver/gallery_index.dart为页面入口。2026-10-18双API36 AVD曾核对105张PNG、冻结/刷新及实际滚动解码，早于所有者迁移；拒权、切网、进程回收、坏格式、大原件及长滚动未由该样本关闭。
