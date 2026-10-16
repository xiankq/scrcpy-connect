# 目标端有界媒体缩略图

核实日期：2026-10-17。产品源码基线为 AOSP `android-16.0.0_r1`；实测对象是 API 36 x86_64 AVD 的官方 adbd，经本机 127.0.0.1:15556 转发。官方 adb 仅为外部测试设置和通知 fixture，产品始终使用 Rust ADB host。没有安装目标 APK、root、额外授权或修改目标屏幕。

## 管线与接口

`media.thumbnail {deviceId,path,maxSize?,operationId?}` 的 maxSize 为 64–512（默认256），operationId 为一次性 UUID。返回 `localPath,mime:image/jpeg,thumbnail:true,width,height,originalSize,cacheHit,sourceStamp,sourceValidation,bytesTransferred,jpegBytes,jpegBytesTransferred,originalBytesTransferred:0,transferAccounting:companionJsonPayloadBytes,operationId`。路径只指向本机私有缓存的小 JPEG，绝不复用 `media.preview`。原内容预览/保存仍须明确调用原接口。

`bytesTransferred` 是实际收到的 companion JSON payload 字节，包含 base64 编码开销和源校验元数据，不包含 ADB/TCP 帧头或首次通用 JAR bootstrap 上传；`jpegBytesTransferred` 是本次 JPEG 二进制内容，命中缓存时为0。它不是原视频读盘量：目标解码器仍会读取目标上的部分原文件。

`media.thumbnail.cancel {deviceId,operationId}` 支持先取消后到达的请求，返回取消请求状态；真实操作承诺与回收由原请求结果确认，不把 `cancelling` 当完成。完成/取消 UUID 均不复用。Rust 每设备最多16个请求，按设备串行生成；Java 一个执行、一个排队，无无限目录或媒体展开。标识 tombstone 每进程最多65536个，达到上限显式拒绝。

目标 companion 的通知/通话/剪贴板队列保持独立，媒体使用 `ProcessBuilder` 启动同一校验 JAR 的单请求 app_process 子进程。参数经过 JSON stdin，不拼 shell 命令；stderr 有界缓冲并丢弃，不记录路径或媒体内容。JPEG 最大256KiB，回复最大384KiB，父进程只处理小 JSON。

## 平台实现和依据

图片依据 [BitmapFactory.Options.inSampleSize](https://developer.android.com/reference/android/graphics/BitmapFactory.Options#inSampleSize) 先读取 bounds、限制100MP、以采样解码，再缩放到请求范围；输入最大256MiB。处理 [ExifInterface](https://developer.android.com/reference/android/media/ExifInterface) 的全部八种方向，包括镜像。透明像素用白色背景输出 JPEG，不保留原始附件或 EXIF 敏感字段。

Android16 [ExifInterface FD 构造器](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/media/java/android/media/ExifInterface.java) 经 FileUtils.convertToModernFd 访问 ActivityThread.currentApplication；普通 shell 子进程不存在该 Application，真实测试稳定复现 FileUtils.getMediaProviderAppId 的 NPE。产品采用公开只读 InputStream 构造器，包裹打开 descriptor 的 dup；不用伪造 Application 或冒充包身份。

视频通过公开 [MediaDataSource](https://developer.android.com/reference/android/media/MediaDataSource) 的 readAt/getSize 从已打开 FD pread，交给 [getScaledFrameAtTime](https://developer.android.com/reference/android/media/MediaMetadataRetriever#getScaledFrameAtTime(long,int,int,int))（API27+）。这同样绕过 [MediaMetadataRetriever FD 重载](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/media/java/android/media/MediaMetadataRetriever.java) 中依赖 Application 的现代格式转换。AOSP [Retriever JNI](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/media/jni/android_media_MediaMetadataRetriever.cpp) 已按视频元数据旋转返回 Bitmap，产品不重复旋转。取首个可用同步帧；无帧、损坏或当前解码器失败显式返回，不下载原件作为隐式降级。视频源最大64GiB，实际返回帧检查至多1MP，再收缩到512px。

解码在独立进程中：内存耗尽不拖死负责通知的父 JVM；8秒自身 watchdog 和父 stdin EOF 监视线程调用 killProcess(myPid) 杀死当前子进程。父进程10秒上限，保留 Process 对象、等待退出和回收，清理不确认时为 media_cleanup_unknown。不能按旧数字 PID 杀进程。[libcore UNIXProcess](https://android.googlesource.com/platform/libcore/+/refs/tags/android-16.0.0_r1/ojluni/src/main/native/UNIXProcess_md.c) 的 destroyProcess 使用 SIGTERM，因此不能把 destroyForcibly 视为必然SIGKILL；这里依赖子进程独立自杀线程，Process.destroy 只是后备。

## 缓存一致性

只接收普通文件，O_NOFOLLOW 拒绝末端符号链接。对同一打开 descriptor 的 fstat 和当前路径 lstat，在生成前后比较 dev/inode/mode/size/mtime/ctime。平台真实公开 st_mtim/st_ctim 才附纳秒字段；字段存在不代表文件系统具备纳秒粒度，也不是原内容哈希或对并发恶意写入的快照证明。

Rust 在生成前、生成后校验源戳，再验证 JPEG SHA-256、长度和尺寸后原子写私有缓存。缓存命中仍请求源戳，并验证本机 JPEG 摘要和尺寸；输出文件名包含 JPEG 摘要，源变化不会被图像控件按旧路径缓存。源变化、权限变化、文件替换或缓存损坏均不冒用旧内容。秒精度系统中同inode、同大小且时间戳粒度内写入仍可能无法检测；不会声称纳秒或内容级验证。

媒体根目录先通过有界SYNC列表确认，不能用test -d将权限拒绝与不存在混淆。媒体列表不再吞掉 find stderr/非零退出码或非法UTF8文件名。16MiB命令输出上限、25000项上限均显式失败，无悄然截断；分页尚未实现。

## 验收

测试工具为临时 FFmpeg7.0.2-static（imageio-ffmpeg0.6.0），SHA256 `e7e7fb30477f717e6f55f9180a70386c62677ef8a4d4d1a5d948f4098aa3eb99`，不是产品依赖。视频 fixture 使用真实 MP4 display matrix（FFmpeg7 的 `-display_rotation -90`）；旧 `-metadata rotate=90` 未生成旋转矩阵，不能当旋转验证。

```sh
rtk proxy env INTEROP_CORE_TEST_ENDPOINT=127.0.0.1:15556 \
 INTEROP_TEST_FFMPEG=/tmp/interop-test-tools/imageio_ffmpeg/binaries/ffmpeg-linux-x86_64-v7.0.2 \
 /home/xiankq/.cargo/bin/cargo +stable test -p interop-core --test media_thumbnail_android -- --ignored --nocapture --test-threads=1
```

实测覆盖：JPEG全部8种EXIF方向，由独立FFmpeg解码实际缩略图并比对四色角像素；90度视频方向和纵向尺寸；原视频填充至8,388,608字节、实际 JPEG861字节、实际总RPC2475字节（3次源/生成响应，原内容传输0）；缓存命中只传源戳，同大小且保留mtime的源替换、本机JPEG同长度篡改后均重生成；PNG采样、伪造400MP尺寸拒绝、最终symlink拒绝、损坏/不存在/权限拒绝、实际子进程存在时取消并确认退出。

两项真实媒体测试在默认2MiB Rust测试线程栈完成22.04s；最终JAR在宿主构建/I/O压力下复跑仍通过90.37s，包括真实子进程运行中断线、退出确认、断线后不重建helper和音频onlyMP4无视频帧。首次扩展测试曾在默认栈发生嵌套future poll栈溢出；GDB定位到thumbnail→RPC→companion startup→sync/open调用链。产品已在RPC/缓存/启动边界堆分配future，默认栈重新运行通过，没有靠增大RUST_MIN_STACK掩盖。

最终JAR真实通知动态更新/旧动作失效/清除通过20.30s；无视频session剪贴板往返/另一companion触发实时事件/启动期间断开两项回归通过49.39s（宿主构建/I/O压力下）。最终 JAR SHA256为 `719e57e3317d91d0858aa722f86770275d3af6130ad2ff0cd4334a5f7722b828`，与Rust内嵌常量和README一致。纯Rust默认边界测试验证参数、提前取消、源戳及JPEG结构。最终core默认回归共39项通过、27项真实环境opt-in忽略；all-targets clippy -D warnings、全workspace fmt --check、作用域git diff --check均通过。

## 明确限制

- Android<26的有界进程生命周期尚未实现；Android26的有界视频取帧尚未实现，均返回thumbnail_api_pending，不等于系统不支持。
- ROM媒体解码器、HEIF/AVIF等格式、超大图和非seekable/特殊文件没有保证；拒绝后用户可以明确打开原件。
- 目标端硬件解码器进程属于系统服务，独立Java子进程隔离不能绝对保证厂商原生服务无缺陷；超时不会把结果伪装成功。
- 有界缓存没有总磁盘容量/LRU淘汰策略；后续需产品层清理与容量设置。来源验证非文件快照，存在以上时间粒度边界。

断线竞争的重复测试曾发现：Rust shell drain结束不能证明Java finally已回收子进程。最终实现先取消设备拥有的thumbnail tokens，向仍存活的认证helper发media.shutdown，并等待真正Process退出回执后才关闭socket；启动阶段仍直接取消，不创建新helper。待完成的媒体取消请求若不能确认回执，返回media_cleanup_unknown，不把未知说成已回收。设备断线返回只表示本机连接已关闭；网络中断时不能把该结果当作目标进程已回收证明，目标自身的stdin-EOF/有界watchdog继续限制解码。
