# Android 入站分享夹具

独立 APK 通过真实 Intent/URI grant 向主控分享文本与文件；包含无授权、私有 URI、超限和慢 provider 等模式，定义见 `ShareFixtureActivity`。

```sh
dart scripts/build_fixture.dart share
cd app
CONNECT_E2E_DEVICE=emulator-5554 \
CONNECT_E2E_ADB=/absolute/android-sdk/platform-tools/adb \
flutter drive -d emulator-5554 --no-pub \
  --driver=../test/driver/incoming_share.dart \
  --target=integration_test/incoming_share_test.dart
```

只用专用主控，拒绝覆盖 `dev.scrcpyconnect.sharefixture`；夹具和输出留系统临时目录。driver 仅卸载本轮安装。`self-sentinel` 只使用指定无害标记，不能替换为用户文件或身份凭据。产品来源契约见[内容交付](../../../docs/implementation/content-delivery.md)。
