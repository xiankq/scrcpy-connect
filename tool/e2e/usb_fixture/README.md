# Virtual USB regression

仅使用一次性、`-read-only` 启动的API 36 x86_64隔离AVD：镜像需可root并提供 `vhci_hcd`/`usbip_core`，宿主无需root或USB模块。工具将USB/IP设备导入AVD真实内核USB栈，经过UsbManager授权、Java FD和nusb；`--target-port` 接另一台AVD的真实adbd，省略则只是模拟peer。

准备会临时挂载vendor权限目录、补USB Host feature并重启框架；仅内核socket握手短暂放宽SELinux，USB导入和应用运行前恢复Enforcing。退出清理附着/挂载/临时文件，结束仍须关闭只读AVD丢弃覆盖层。

启动两台专用AVD并等待系统就绪，在根目录为目标准备本轮转发：

```sh
USB_FIXTURE_SDK=/path/to/Android/Sdk
"$USB_FIXTURE_SDK/platform-tools/adb" -s emulator-5556 tcpip 5555
"$USB_FIXTURE_SDK/platform-tools/adb" -s emulator-5556 wait-for-device
"$USB_FIXTURE_SDK/platform-tools/adb" -s emulator-5556 forward tcp:0 tcp:5555
dart tool/e2e/usb_fixture/prepare.dart --device emulator-5554 \
  --sdk "$USB_FIXTURE_SDK" --target-port <returned-host-port>
```

保持prepare运行，看到 `USB fixture ready` 后从 `app/` 执行：

```sh
CONNECT_E2E_ADB="$USB_FIXTURE_SDK/platform-tools/adb" \
CONNECT_E2E_DEVICE=emulator-5554 \
CONNECT_E2E_CAPTURE_DIR=/tmp/connect-usb-e2e \
flutter drive --no-pub -d emulator-5554 \
  --driver=../tool/driver/usb.dart \
  --target=integration_test/usb_connection_test.dart
```

要求新USB附着、产品无目标记录。用例先Cancel再OK，核对lease释放后真实shell/sync可用，只删除新增记录。它不代替应用授权或连接。协议单测为 `flutter test --no-pub tool/e2e/tests/usbip_server_test.dart`。

结束Ctrl-C停止prepare，精确移除本轮 `forward --remove tcp:<host-port>`，仅关闭本轮AVD。结果在指定目录 `result.json`；虚拟USB不证明线缆、OTG、OEM HAL或量产设备RSA授权。设备证据见[验收记录](../../../docs/implementation/validation.md)。
