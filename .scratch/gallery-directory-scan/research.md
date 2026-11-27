# Android 相册索引与目录检查

## 当前为什么遍历

原页面每次进入都会调用 `GalleryScanNotifier.start()`，即使已有可展示的历史快照。`FileCatalog.startScan` 从 `/sdcard` 启动 `_walk`，逐目录经 ADB 列举、按扩展名识别媒体，然后由应用分页展示结果。重复遍历来自页面触发策略，逐目录读取来自数据源选择。产品规格约定检查当前用户主共享存储，包含根目录、Download、自定义目录和 `Android/media`，排除 `Android/data`、`Android/obb`、其他卷、链接与特殊文件。该范围由实际目录项定义。见 [相册页面](../../app/lib/pages/gallery/gallery_page.dart)、[文件目录实现](../../app/lib/core/files/file_catalog.dart)、[产品规格](../../designs/prod/content-and-transfer.md#相册检查与加载)。

## 系统已有媒体 API

- 用 `ContentResolver.query` 查询 `MediaStore.Images.Media` 和 `MediaStore.Video.Media` 可直接取得系统索引中的图片和视频。API 29 起，给两个集合分别传 `MediaStore.VOLUME_EXTERNAL_PRIMARY`，可限定当前用户的主共享卷。API 29 起 `VOLUME_EXTERNAL` 是所有共享卷的合并视图。API 28 及以下使用各集合的 `EXTERNAL_CONTENT_URI`，接入时仍需核对返回对象是否在产品约定范围内。引用原件时，可将集合 URI 与行 `_ID` 组成媒体 URI，再经 `ContentResolver` 打开。现有路径型预览和文件传输在打开前也要继续核验实际对象。[共享媒体访问](https://developer.android.com/training/data-storage/shared/media)、[MediaStore 存储卷](https://developer.android.com/reference/android/provider/MediaStore#VOLUME_EXTERNAL_PRIMARY)
- 自定义目录内已进入系统索引的文件可以查到。未入索引和被系统扫描器跳过的内容可能缺失。AOSP 扫描器有隐藏目录与 `.nomedia` 判断，MediaStore 查询默认过滤待发布和在回收站里的项目。要采用索引作为唯一来源，需要把相册覆盖范围改为当前用户主共享卷中对调用者可见的系统媒体。[AOSP ModernMediaScanner](https://android.googlesource.com/platform/packages/providers/MediaProvider/+/6b7baf4b9722dd75bfb5d64acadf48223226cde6/src/com/android/providers/media/scan/ModernMediaScanner.java)、[MediaStore 查询参数](https://developer.android.com/reference/android/provider/MediaStore#QUERY_ARG_MATCH_PENDING)
- 普通 APK 读取其他应用的媒体会受 Android 版本、目标 SDK 及授权影响。面向 Android 13 或更高版本时分别使用 `READ_MEDIA_IMAGES`、`READ_MEDIA_VIDEO`，旧系统在适用场景用 `READ_EXTERNAL_STORAGE`。Android 14 起还可能只授权用户选中的图片和视频。系统 Photo Picker 用于让用户选取文件，可见范围由用户的选择确定。[共享媒体权限](https://developer.android.com/training/data-storage/shared/media#request-permissions)、[Android 14 部分照片和视频访问](https://developer.android.com/about/versions/14/changes/partial-photo-video-access)、[系统 Photo Picker](https://developer.android.com/training/data-storage/shared/photopicker)

## 索引如何增量刷新

- API 30 起按用户和实际卷一起缓存 `MediaStore.getVersion(context, volume)` 与 `getGeneration(context, volume)`。先对比版本，版本变化时重读该卷索引。版本和 generation 均相同可复用已有集合。generation 变化后，可以根据 `GENERATION_ADDED` 和 `GENERATION_MODIFIED` 取仍可见行的增量。刷新前后也要考虑用户授予相册的可见范围变化，尤其是 Android 14 的部分访问。[MediaStore generation](https://developer.android.com/reference/android/provider/MediaStore#getGeneration(android.content.Context,%20java.lang.String))、[媒体行 generation 列](https://developer.android.com/reference/android/provider/MediaStore.MediaColumns#GENERATION_MODIFIED)
- 硬删除、移出查询范围或放入回收站后，旧行可能不再可查。缺少可靠删除记录时，可查询同范围的可见 ID 来移除已消失项目。API 37.1 或 S Extensions 23 起有 `queryDeletedFiles`，只追踪外部卷，外部卷移除后不再返回其删除记录。[MediaStore 删除记录查询](https://developer.android.com/reference/android/provider/MediaStore#queryDeletedFiles(android.content.ContentResolver,%20android.os.Bundle,%20android.os.CancellationSignal))
- 连接期间可对媒体集合 URI 注册 `ContentObserver`，接到通知时使已有快照过期或启动合并后的刷新。回调可携带 URI 和插入、更新、删除标记，提供方可以省略这些标记。断线重连后应重新核对版本和 generation。API 29 及以下可通过同范围索引查询更新，库大小与查询列决定读取量。[注册观察器](https://developer.android.com/reference/android/content/ContentResolver#registerContentObserver(android.net.Uri,%20boolean,%20android.database.ContentObserver))、[观察器回调](https://developer.android.com/reference/android/database/ContentObserver)

## ADB 与执行端接入

- `adb shell content query` 可用来确认设备索引是否可读。AOSP 命令以 shell 调用归属访问指定用户的 provider，用逗号分隔列，字符串原样输出。媒体文件名允许逗号和换行，输出不能可靠地作为结构化媒体协议。[AOSP content 命令](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/cmds/content/src/com/android/commands/content/Content.java#653)
- 现有 companion 在被控手机的 shell UID 2000 下运行，已有 `com.android.shell` 归属检查、当前用户 context、配对连接和 JSON 请求协议。接索引时可复用这些边界，从被控端返回结构化分页数据，在实际 shell 身份下验证各 Android 版本、厂商设备和前台用户的索引与原件可见性。普通 APK 的权限文档无法单独证明 shell UID 在所有设备都能看到同样的行。[执行端说明](../../servers/companion/README.md)、[shell 归属校验](../../servers/companion/src/com/interop/companion/Main.java)、[当前用户 context](../../servers/companion/src/com/interop/companion/Apps.java)

## API 34 模拟器验证

在独立 AVD 上用 ADB shell 放入两张临时 PNG，并发送扫描广播。文件系统 `ls` 看得到两张。通过 `content query` 分别查询 `external_primary` 和 `external`，均只返回 DCIM 里的图片，其 `generation_added` 为 41。放在含 `.nomedia` 子目录的第二张图片没有被索引。这次实验验证了该模拟器 shell 能查询索引，也复现了索引与文件目录范围的差异。
