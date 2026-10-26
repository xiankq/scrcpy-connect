# 系统分享接收夹具

独立 API 36 应用 `dev.scrcpyconnect.deliveryfixture`，验证 Sharesheet 的实际读取内容。

```sh
dart scripts/build_fixture.dart content-delivery --output /tmp/connect-content-delivery-fixture
```

仅在专用主控 AVD 安装，拒绝覆盖已有包，结束只卸载本轮安装。通过真实 Sharesheet 选择 `Connect delivery verifier`；回执为应用私有 `files/receipt.json`，内容须与源字节/摘要一致。只支持单文件且成功样本须小于 2 MiB。

自动入口为 `test/driver/content_delivery.dart` 与 `app/integration_test/content_delivery_test.dart`；环境参数见 driver，输出留系统临时目录。
