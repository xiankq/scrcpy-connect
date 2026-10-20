# Connect delivery verifier

此 APK 是 Android API 36 **主控 AVD** 的独立测试接收方，包名
`dev.scrcpyconnect.deliveryfixture`，系统分享目标名称精确为
`Connect delivery verifier`。它不属于产品，不是主控应用的运行依赖，
也不能安装到被控设备来补充产品能力。`debuggable=true` 仅供 host
通过 `run-as` 查看 fixture 自己的内部验收文件。

## 构建

需要 Android SDK platform 36、build-tools 36.0.0、JDK 的 `javac` 与
`keytool`。在仓库根目录运行：

```bash
dart tool/e2e/content_delivery_fixture/build.dart --output /tmp/connect-content-delivery-fixture
```

可用 `--sdk /path/to/android-sdk` 指定 SDK。`--output` 必须严格位于
`/tmp/` 下；APK、测试签名密钥和构建中间产物均在该目录内。最终 APK 为
`/tmp/connect-content-delivery-fixture/content-delivery-fixture.apk`，签名 alias 为
`deliveryfixture`。脚本不运行 adb、Gradle 或 Flutter。

## 实际系统分享验收

仅在已明确授权的主控 API 36 AVD 上操作。先用 `pm path dev.scrcpyconnect.deliveryfixture`
确认包不存在；已有安装时停止，不覆盖。记录本轮新安装的所有权，完成后仅卸载自己的安装：

```bash
adb -s <controller-avd-serial> install /tmp/connect-content-delivery-fixture/content-delivery-fixture.apk
```

从主控应用执行真实内容交付，打开 Android 系统 Sharesheet，并手动选择
`Connect delivery verifier`。不要用 `am start` 伪造一次发送代替这项验收。
接收页将显示 `SUCCESS` 或 `FAILED`，以及 provider 提供的文件显示名。
不需要网络、存储或其他运行时权限。

等待接收页显示结果后，在 host 读取 **fixture 自己的内部文件**：

```bash
adb -s <controller-avd-serial> shell run-as dev.scrcpyconnect.deliveryfixture cat files/receipt.json
```

receipt 的 `status` 应为 `success`，且 `success=true`，再对照原文件的
`displayName`、`intentMime`、`resolvedMime`、`bytes` 与 `sha256`。Intent的类型
决定Sharesheet匹配，URI解析类型则来自提供方；两者分别核验，不互相覆盖。
`uriScheme` 必须为
`content`，`readGrant` 必须为 `true`；后者表示接收 Intent 带有
`FLAG_GRANT_READ_URI_PERMISSION`，实际打开并读至 EOF 才会成功。
SHA-256 是实际读到的全部字节的十六进制摘要，不是元数据声明。

每次交付先把 receipt 写成 `processing`，完成后原子替换为最终结果。
失败时 `status=error`、`success=false`、`error` 给出原因，`bytes`
保留已读取的字节数，`sha256=null`，避免把截断内容当成完整文件。
缺少 `EXTRA_STREAM`、错误 action、非 `content:` URI、无 Intent 读取授权、
provider 查询或读取异常均失败。fixture 只处理 `ACTION_SEND`，不处理多文件。

实际最多读取 **2 MiB**，不额外读取探测字节。若读满 2 MiB，无法在预算内
再确认 EOF，因此一律保守失败 `read_limit_reached_2_mib`，包括恰好 2 MiB
的文件。成功验收请使用小于 2 MiB 的已知样本；大于等于该阈值不会假成功。
不信任 provider 声明的大小来绕过这项限制。

需要复验“缺少 URI”的失败路径时，可通过系统分享发送纯文本至该目标；
该路径应失败，不能当作内容交付成功证据。不要删除或读取产品应用的内部文件。

## 自动相册原件交付

自动host入口为`tool/driver/content_delivery.dart`，目标为
`app/integration_test/content_delivery_test.dart`。默认`text`从文件详情取用；
`image`／`video`必须同时设置host环境变量`CONNECT_E2E_CONTENT_KIND`和
同名`--dart-define`，再用`CONNECT_E2E_FFMPEG`指定实际host FFmpeg绝对路径。
该工具只生成测试JPEG／H264 MP4，不是产品依赖。样本由host读取并计算hash，
源文件只放被控Pictures／Movies下的唯一名称，系统保存仍选择主控Downloads。

媒体流程必须从实际相册网格进入，等待真实缩略图和原件解码；视频还检查播放时钟、
暂停、拖动定位和静音，然后复用真实取消／保存／系统分享／外部字节及授权核验。
host同时核验精确MIME；只出现文件名、播放按钮或分享面板不算通过。
结果和图像仍只在指定`/tmp/`目录，清理不遍历删除其他相册或下载内容。
