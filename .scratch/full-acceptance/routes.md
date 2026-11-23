# 路由验收索引

状态仅用于记录实跑覆盖。按钮、菜单、系统动作和自动状态另列于验收记录。

| 路由 | 代码行 | 实跑状态 |
| --- | ---: | --- |
| `RootRoute` | 180 | macOS、Android 真机启动进入设备，iOS 逐台启动 |
| `HomeShellRoute` | 204 | macOS 切换设备、传输和设置 |
| `DevicesRoute` | 232 | macOS 查现有设备列表，小米 12 主控进入首次空态 |
| `TransfersRoute` | 244 | macOS 确认样本成功、失败记录可查 |
| `SettingsRoute` | 257 | macOS 打开并检查分组和入口 |
| `RouteErrorRoute` | 271 | 待实跑 |
| `TransferCenterRoute` | 289 | 待实跑 |
| `SettingsPageRoute` | 299 | 待实跑 |
| `AddDeviceRoute` | 309 | macOS IP 空值、USB 状态卡，其他授权方式待验 |
| `WirelessGuideRoute` | 331 | 待实跑 |
| `ConnectionFormRoute` | 356 | 待实跑 |
| `DiscoveryRoute` | 397 | 待实跑 |
| `UsbGuideRoute` | 408 | 待实跑 |
| `QrPairRoute` | 432 | 待实跑 |
| `WorkspaceRoute` | 442 | macOS TCP 进入小米 12 工作台，核对了充满状态 |
| `DeviceManagementRoute` | 458 | macOS 进入页面，打开画面与控制 |
| `DeviceDetailsRoute` | 476 | macOS 核对骨架到系统与电池数据 |
| `DeviceDataRoute` | 492 | 待实跑 |
| `CapabilitiesRoute` | 505 | 待实跑 |
| `DeviceConnectionRoute` | 518 | 待实跑 |
| `DiagnosticsRoute` | 534 | 待实跑 |
| `FilesRoute` | 547 | 真机四层样本目录，返回上一级仍有可用内容 |
| `FileDetailsRoute` | 568 | 真机测试文件详情和取回动作 |
| `FileSearchRoute` | 598 | 当前目录按名称返回唯一真机样本 |
| `AppsRoute` | 625 | macOS 搜索系统设置，打开独立应用 |
| `GalleryRoute` | 638 | 真机样本、刷新、采用结果、日期分组、保留读到的图片 |
| `MediaPreviewRoute` | 654 | 真机样本打开原件，切换原尺寸后返回 |
| `NotificationsRoute` | 678 | macOS 页面可达，通知产生与接续待验 |
| `CallsRoute` | 691 | macOS 页面可达，通话发起及接续待验 |
| `QualityRoute` | 704 | 修改帧率、离页确认保存并恢复原值。实测采样帧率待验 |
| `SessionToolsRoute` | 720 | 待实跑 |
| `SessionsRoute` | 734 | 待实跑 |
| `RemoteRoute` | 744 | macOS TCP 真机出现首帧，Escape 发往手机，关闭后连接保留 |
| `RemoteAppRoute` | 770 | macOS TCP 独立设置获得首帧，关闭后整机保留 |
| `RemoteSessionRoute` | 804 | 待实跑 |
| `TransferDetailsRoute` | 847 | 核对失败状态和修复后的完成状态与字节数 |
| `ScreenshotRoute` | 867 | macOS 真实截图打开预览，返回原画面 |
| `DocumentExportRoute` | 892 | 待实跑 |
| `ReceiveContentRoute` | 928 | 真机原件完整取回，校验 SHA-256 |
| `FileSendRoute` | 957 | 待实跑 |
| `DocumentImportRoute` | 977 | 待实跑 |
| `IncomingShareRoute` | 1008 | 待实跑 |
| `ShareDirectoryRoute` | 1028 | 待实跑 |
| `AppUpdatesRoute` | 1042 | macOS 关于页、检查和更新记录，无渠道 |
| `AppearanceRoute` | 1051 | 待实跑 |
| `BackgroundRoute` | 1061 | macOS 页面可达，保活和系统提示待验 |
| `ActivitiesRoute` | 1071 | 待实跑 |
| `DataPreferencesRoute` | 1083 | macOS 页面可达，导入、导出及恢复待验 |
| `MediaCacheRoute` | 1096 | macOS 页面可达，清理和容量限制待验 |
| `DeviceActivitiesRoute` | 1108 | 待实跑 |
| `AdbIdentityRoute` | 1123 | macOS 页面可达，密钥导入导出及切换待验 |
| `DeviceIdentityRoute` | 1135 | 待实跑 |
| `DeviceIpRoute` | 1148 | 待实跑 |
| `RuntimeLogsRoute` | 1163 | macOS 页面可达，日志导出待验 |
