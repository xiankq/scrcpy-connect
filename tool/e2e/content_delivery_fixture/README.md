# Connect delivery verifier

独立API 36主控AVD接收方 `dev.scrcpyconnect.deliveryfixture`，Sharesheet名称为 `Connect delivery verifier`。仅验证真实系统分享，不是产品依赖或被控端能力补丁。

```sh
dart tool/e2e/content_delivery_fixture/build.dart --output /tmp/connect-content-delivery-fixture
```

需SDK 36、build-tools 36.0.0和JDK；可传 `--sdk`。输出必须在系统临时目录内，APK为 `content-delivery-fixture.apk`。仅在明确授权的隔离主控AVD安装；先确认 `pm path dev.scrcpyconnect.deliveryfixture` 为空，拒绝覆盖，结束仅卸载本轮安装。

从产品真实交付流程打开Sharesheet并选择该接收方，等待结果后读取：

```sh
adb -s <controller-avd> shell run-as dev.scrcpyconnect.deliveryfixture cat files/receipt.json
```

成功要求 `status=success`、`success=true`，核对源样本的 `displayName/intentMime/resolvedMime/bytes/sha256`；`uriScheme=content`、`readGrant=true` 且实际读至EOF。Intent与provider MIME分别核验。`processing` 不是结果，失败保留已读字节但 `sha256=null`。仅支持 `ACTION_SEND` 单文件；不以 `am start` 代替系统分享。

读取预算2MiB，达到预算（含恰好2MiB）即 `read_limit_reached_2_mib`，因此成功样本必须更小。纯文本可验证缺URI失败。只读取fixture自身回执，不读删产品内部文件。

自动入口为 `tool/driver/content_delivery.dart` / `app/integration_test/content_delivery_test.dart`。默认text；image/video须同时设置host变量和Dart define `CONNECT_E2E_CONTENT_KIND`，并以 `CONNECT_E2E_FFMPEG` 指定host FFmpeg绝对路径。它生成唯一目标Pictures/Movies样本并核对相册原件、保存、分享和外部字节；视频还验证时钟/暂停/定位/静音。输出只在指定临时目录，清理仅限本轮样本。
