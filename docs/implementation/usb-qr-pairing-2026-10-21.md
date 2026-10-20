# USB 与系统扫码配对修复验证

日期：2026-10-21。主机 Ubuntu x86_64，Flutter 3.47.7／Dart 3.13.5／Rust 1.99.1；Android Emulator 37.2.12，Google APIs API36 x86_64。记录当前版本结果，不替代[设备连接规则](../../designs/prod/device-connection.md)。

## 已确认缺陷

- 桌面 `devices.usb` 错误要求 Android 授权器与 FD，已有 nusb 枚举始终无法执行；原生入口也只接受 Linux／Android FD。现在 Android 保留 UsbManager 授权与 FD 交接，桌面走原生枚举；多台先选择当前附着标识，拔除后报错，不改选其他设备。无序列号候选仍可选择，页面显示产品名或 USB 设备编号，内部标识只用于提交与 Widget Key。
- QR 的首候选 TCP 已建立但 TLS 不响应时，原逻辑耗尽整个扫码期限，无法尝试第二地址。现在每个地址的 TCP＋PAKE 共用 `endpoint_timeout_ms`，保留总体期限、取消及明确认证拒绝后停止。
- Android USB 平台错误未经转换，真实页面显示 `PlatformException(...)`。现在保留错误码和平台原因，按产品异常显示中文消息。
- 原 invalid-FD 测试缺 `attemptId`，只触发参数拒绝，没有进入 FD 导入。修正后连续复用同一尝试，核验失败租约释放及原始描述符仍可用。
- USB 系统授权回执的 PendingIntent 带 `scrcpyconnect://...` URI，MainActivity 的 action-only IntentFilter 却不接收带 URI 的广播。软件 USB 实操确认：Cancel 和 OK 都已由系统发送，但页面一直“正在检查”，OK 后系统实际上已有权限。补充 `addDataScheme("scrcpyconnect")` 后，两种结果均正常返回，拒绝后可以重试。
- USB 拔除后工作台连接主动作和离线功能提示直接调用 `devices.connect`，没有重新获取当前 USB FD。现在带原设备 ID 回到统一添加页的 USB 形式；两项回归在原实现明确失败、修复后通过，不重放原远端操作。

## 红绿回归与工程检查

| 检查 | 本轮实际结果 |
| --- | --- |
| Dart 连接协调器 | 10 项通过；桌面无授权器旧实现明确报“需要主控系统USB授权”，修复后进入原生 open／attach；多设备选择不接入不存在的操作 |
| Flutter USB／恢复／统一添加表单 | 11 项通过；无序列号候选旧页面无法选择，修复后准确提交 `usbDeviceId`；覆盖取消、迟到结果及模式切换 |
| Rust Core lib 默认集 | 146 passed、0 failed、14 ignored；未将 ignored 计为通过 |
| QR 实际协议端 | 4 项 QR 相关用例显式运行通过；新增用例使用真实 UDP DNS-SD 与独立官方 BoringSSL PAKE。首地址实际接受后静默，原实现以 expired 失败，修复后第二地址完成配对并记录 GUID |
| 独立 BoringSSL fixture | 原配对、错码、STLS 三项通过；QR 密码经私有 stdin 传入，不放命令参数或日志 |
| USB 原生 | 2 项选择回归及实际无效 FD 导入／重试清理通过；这不是物理 USB |
| 编译与静态检查 | Windows x86_64、macOS aarch64、Android aarch64 Core 编译；Core／ADB Clippy `-D warnings`、Rust 格式、定向 Dart 分析及共享协议生成检查通过 |
| 补充 USB 回归 | USB/IP socket 6 项、USB 页面 2 项、设备管理 9 项，共 17 项通过；系统授权集成用例在实际 API36 主控 AVD 通过，完整回执全部为 true，物理线缆标记保持 false |

新增 QR 回归从仓库根运行；独立 fixture 的构建依据见 `crates/adb/tests/wireless_boringssl.rs`，需要支持 IPv4 组播的环境：

```sh
ADB_BORINGSSL_FIXTURE=<已编译的官方 BoringSSL fixture> \
  cargo test -p interop-core --lib \
  qr_pairing_tries_a_working_address_after_a_stalled_tls_endpoint \
  -- --ignored --nocapture
```

## 双 AVD 实际流程

主控为 `interop-controller`／emulator-5554，被控为 `interop-target-b`／emulator-5556。两台均由本轮启动，使用 host GL、禁用 Vulkan，主控 `-wifi-server-port 18679`、被控 `-wifi-client-port 18679`，通过系统 Wi-Fi 连接同一个 AndroidWifi；实际 wlan0 地址为 10.0.2.16 和 10.0.2.17。

1. 普通 `app/lib/main.dart` 调试入口安装并启动，应用实际生成 QR。宿主只捕获图像，不调用 adb pair、不导入密钥。
2. 被控 AVD 以 `-camera-back imagefile:<临时PNG>` 启动。将主控 QR 区域放入相机图像，打开 Settings 的 Wireless debugging → Pair device with QR code，由系统相机与扫码器读取。没有通过 Intent 或系统接口跳过扫码。
3. 系统完成配对并返回无线调试页，“Paired devices”新增 `interop-controller`，既有 `xiankq@unknown` 保留。主控显示“配对与连接已完成。”。
4. 主控点击“打开设备工作台”，实际显示 sdk_gphone64_x86_64、Android 16、无线调试、已连接，以及 10.0.2.17 和系统实际连接端口。完成了二维码生成 → 系统识别 → mDNS → PAKE → 连接端口发现 → Required TLS → 工作台。
5. 此阶段 AVD 尚未导入软件 USB，实际检查得到 `usb_not_found`，修复平台异常转换后重新检查中文展示。USB 授权正例随后按下节补充。

普通主控 Dart hot reload 和 hot restart 成功，runtime errors 查询为空。Pencil MCP 未连通时，用 `pen interactive` 只读检查 `OxUaB`、`G4CpTk`、`WMggr`、`ONn92` 及共享内容引用，未发现活动布局裁剪；本轮未改布局、token 或母组件。

## AVD 软件 USB 实际流程

用户无法提供真机后，进一步使用两台 `-read-only` API36 AVD 验证 USB。该镜像内核 6.6.66 已加载 `usbip_core`、`vhci_hcd`，宿主无需 root。临时复制、标记并 bind mount vendor 权限目录，添加 USB Host feature，重启 Android 框架后 `pm list features` 与 `dumpsys usb` 实际出现 USB Host 管理器。

宿主 Dart USB/IP server 提供 18d1:4ee7、ff/42/01、双 bulk、512-byte max packet 的 USB2 高速设备。NDK helper 导入到 AVD 的 vhci；实际设备经内核枚举出现在 `/dev/bus/usb/...`，UsbManager 读取到 Virtual Android。仅 helper 创建内核标签 socket 的握手阶段短暂放宽测试 AVD SELinux，USB 导入前已恢复 Enforcing；普通应用在 untrusted_app 域运行，不以 root 调用产品 USB。SIGTERM 中断静默握手的实测也确认最终恢复 Enforcing。完整可复现入口及清理方法见[软件 USB 工具](../../tool/e2e/usb_fixture/README.md)。

1. 普通 debug 应用点击“检查连接”，实际弹出 Android SystemUI 的“Allow 邻接 to access Virtual Android?”。先拒绝，页面收到“尚未允许主控应用访问 USB 设备。”并恢复检查按钮；再次检查并允许，完成 Java USB FD → Rust duplicate → nusb claim／URB → ADB 握手。
2. server 使用真实转发模式，USB bulk 数据发往另一台 AVD 的 adbd TCP 端口，元数据不是模拟字符串。工作台显示 sdk_gphone64_x86_64、Android 16、USB、已连接。Java `UsbDeviceConnectionJNI close` 后进程仍只保留一个 Rust USB FD；独立 `device.capabilities` 实际 shell/sync 探测成功，连接 ID 保持不变。
3. 停止 USB fixture 后，工作台实际变为离线。点击“连接手机”进入原设备 USB 检查形式；重新导入、检查、点击新的系统 OK 后，再次进入已连接工作台。没有复用拔线前 FD。
4. `usb_connection_test.dart`＋`tool/driver/usb.dart` 自动执行拒绝、重试、允许、工作台归属、Java lease 释放后的真实 shell/files 探测及精确记录清理，通过。报告 `/tmp/connect-usb-emulation/automated/result.json` 的业务断言均为 true，hostErrors 为空，`physicalCableVerified:false`；运行时 Enforcing。工具 socket 回归另覆盖控制请求、分段 OUT、512/ZLP、UNLINK 和断线释放。
5. 最终普通 release APK 在同一隔离只读 AVD 的临时覆盖层内安装，实际通过系统 USB 允许与连接工作台正例，截图 `/tmp/connect-usb-emulation/release-usb-workspace.png`。普通 debug 的最终 hot reload／hot restart 成功，Dart MCP 查询无运行错误。nusb 的 USB mmap 被 SELinux 拒绝时自动采用普通缓冲，以上实操仍成功。

这些结果覆盖真实 Android USB Host API 与内核虚拟 USB 传输；没有物理数据线、OTG 角色、电气链路或厂商 USB HAL，也不把该软件装置称为真机 USB。

## 边界与资源

本轮被控镜像 `ro.adb.secure=0`。实际系统扫码与 PAKE、主控 USB 访问授权正例成立，但不证明量产设备未配对身份或 ADB RSA 调试信任会被拒绝；安全拒绝证据仍以[安全配置 AVD 的首次配对记录](first-pairing.md)为准。桌面 USB 编译与夹具也不能证明物理线缆、USB 主从角色、驱动及各 OEM 均通过。用户现场故障尚无设备和错误信息，不能把已确认代码缺陷认定为现场唯一原因。

清理已完成：生产 `devices.forget` 返回 `disconnected:true/forgotten:true`，设备列表恢复空记录；按本轮新增项的唯一指纹调用 API36 系统 unpair 接口，独立 dumpsys 确认 `interop-controller` 消失、`xiankq@unknown` 保留。临时 XML、QR 输入、临时解码器、检查副本和调试 APK 副本已删除；本轮两台 AVD 均停止。保留临时目录下的配对成功／连接工作台截图与可复用 BoringSSL 编译缓存。

后续 USB 批次也已清理：集成用例与普通 release 分别移除其精确设备记录，列表为空；fixture 退出后确认 vhci port 0 为空、Enforcing、无临时权限挂载，helper／UI XML、宿主 native 编译副本与重复 debug APK 已删除。唯一目标转发 tcp:18743 已移除，本批次两台只读 AVD 停止，临时覆盖层丢弃。保留发布包、报告及截图；编译缓存继续复用。

## 交付包

普通 `app/lib/main.dart` 通用 release APK 已在最终 Dart 与 Android 修改后重新构建，包含 armeabi-v7a／arm64-v8a／x86_64，59,117,417 bytes。签名、ZIP 完整性、16 KiB 原生页对齐及共享服务产物校验通过。SHA-256：`0f9944089a539dc83da1551206c2c5ea61ed33e723eb615ab3930c4a05117549`。

产物为 `app/build/app/outputs/flutter-apk/app-release.apk`。系统扫码流程使用普通 debug 入口；最终 release 的 USB 流程也已实际运行。为处理签名不同，补测 release 时只删除本轮 `-read-only` AVD 临时覆盖层内的 debug 安装，原 AVD 基础数据与授权身份不变。
