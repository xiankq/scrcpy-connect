# 无真机 USB 实操回归

此工具只供一次性、以 `-read-only` 启动的 API36 x86_64 AVD 使用，不是应用依赖。镜像需可 `adb root`，并已加载 `vhci_hcd` 和 `usbip_core`；当前 Google APIs API36 镜像满足条件。宿主无需 root、USB/IP 内核模块或物理 USB。协议依据为 [Linux USB/IP](https://www.kernel.org/doc/html/latest/usb/usbip_protocol.html)。

`prepare.dart` 将软件 USB 设备导入 **AVD 的真实 Linux USB 栈**。Android UsbManager 枚举、系统权限弹窗、Java FD、nusb 接口占用和 URB 都实际执行。提供 `--target-port` 时，USB bulk 数据转发给另一台 AVD 的真实 adbd；省略该参数则是模拟 ADB peer，不能记为真实被控运行。

准备工具会复制并临时挂载 vendor 权限目录，补充 USB Host feature 后重启 Android 框架。原 XML 保留并恢复 SELinux 标签。原生 helper 仅在创建内核标签 socket 的握手阶段短暂放宽 AVD SELinux，在导入 USB 前恢复 Enforcing；应用运行时保持 Enforcing，仍须用户通过系统 USB 授权。helper 处理错误和退出信号以恢复模式；停止工具后移除其 USB 附着、挂载和临时文件。测试结束仍应关闭本次只读 AVD，丢弃整个测试覆盖层。

## 运行

从根目录执行。先用仓库验证过的 host GL 配置启动两台隔离 AVD，等待系统完全启动；不要复用用户正在使用的模拟器。以下序列号和 AVD 名是本轮环境示例：

```sh
USB_FIXTURE_SDK=/path/to/Android/Sdk
"$USB_FIXTURE_SDK/emulator/emulator" -avd interop-controller -read-only -port 5554 -gpu host -feature -Vulkan -no-window -no-audio -no-snapshot -cores 2
"$USB_FIXTURE_SDK/emulator/emulator" -avd interop-target-b -read-only -port 5556 -gpu host -feature -Vulkan -no-window -no-audio -no-snapshot -cores 2
```

两条 emulator 命令分别保持运行。为真实 adbd 准备一条仅本轮使用的转发；`tcpip` 重启 adbd 后需等目标重新上线：

```sh
"$USB_FIXTURE_SDK/platform-tools/adb" -s emulator-5556 tcpip 5555
"$USB_FIXTURE_SDK/platform-tools/adb" -s emulator-5556 wait-for-device
"$USB_FIXTURE_SDK/platform-tools/adb" -s emulator-5556 forward tcp:0 tcp:5555
dart tool/e2e/usb_fixture/prepare.dart --device emulator-5554 --sdk "$USB_FIXTURE_SDK" --target-port <上条命令返回的宿主端口>
```

保持准备工具运行，看到 `USB fixture ready` 后，在另一终端从 `app/` 执行：

```sh
CONNECT_E2E_ADB="$USB_FIXTURE_SDK/platform-tools/adb" \
CONNECT_E2E_DEVICE=emulator-5554 \
CONNECT_E2E_CAPTURE_DIR=/tmp/connect-usb-e2e \
flutter drive --no-pub -d emulator-5554 \
  --driver=../tool/driver/usb.dart \
  --target=integration_test/usb_connection_test.dart
```

用全新的 USB 附着和没有目标记录的安装运行。用例经过实际添加页，先点击系统 Cancel，验证中文拒绝与可重试；再点击 OK，进入 USB 工作台，校验 Java lease 已释放后同一个 Rust 连接仍能执行真实 shell/sync 探测，最后删除精确新增记录并保留原记录。报告为指定临时目录的 `result.json`。驱动不调用 `pm grant`，不代替应用建立 ADB 连接。

单独验证 USB/IP 协议夹具：

```sh
flutter test --no-pub tool/e2e/tests/usbip_server_test.dart
```

完成后 Ctrl-C 停止准备工具，移除上述精确转发（`adb -s emulator-5556 forward --remove tcp:<宿主端口>`），并只关闭本轮启动的两台 AVD。手动拔插可通过停止、重启准备工具完成。普通应用调试入口与 integration-test APK 分开记录；测试结束若要交付安装包，重新构建普通 `app/lib/main.dart` release。

这覆盖虚拟 USB 主机和真实 Android API／adbd，不证明物理线缆、电气、OTG 主从角色、厂商 USB HAL、量产设备 ADB RSA 授权或其他主控平台已通过。本轮实际结果见[验收记录](../../../docs/implementation/usb-qr-pairing-2026-10-21.md)。
