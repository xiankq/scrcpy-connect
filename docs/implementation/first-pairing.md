# 首次配对、加密连接与撤权验证

产品用自己的Rust身份，经被控系统配对码窗口完成PAKE，再用独立连接端口建立Required TLS。宿主只协调系统界面/当次码/转发，不执行adb pair、不导入产品私钥或在目标安装APK。配对、连接、授权拒绝分别核验；当前用户规则见[设备连接](../../designs/prod/device-connection.md)。

## 可重复的产品链路

`app/integration_test/first_pairing_test.dart`与 `tool/driver/first_pairing.dart`经过app.main/FRB/Runtime及真实表单：

1. 新身份访问真实TLS listener，要求明确证书授权拒绝，不以超时代替。
2. 错码失败且无GUID；重新打开系统窗口，用新码完成PAKE。
3. 使用独立连接端口，确认真实连接和设备能力。
4. 断开后仅撤销本次新增产品身份，再连接必须unauthorized且关闭自动重连。
5. 精确清理自有记录/信任/转发，保留基线身份；配对码、私钥和公钥原文不入报告或截图。

从 `app/` 用上述driver/target执行drive，并设CONNECT_E2E_ADB、CONNECT_E2E_DEVICE、CONNECT_E2E_TARGET、CONNECT_E2E_CAPTURE_DIR。夹具仅接受明确不同的隔离AVD和已验证英文API36系统UI；已有同名产品配对项时拒绝准备，不修改既有信任。

## 安全测试环境

原API36 Google APIs镜像 `ro.adb.secure=0`，实际未配对身份拒绝负例失败，配对正例不能覆盖。2026-10-17/18仅为独立目标建立可写覆盖层，将secure设1后重启；SDK原镜像和其他AVD未改。实测userdebug/dev-keys、debuggable=1、verifiedbootstate=orange、shell UID2000；不是量产锁定/OEM安全证明，也不是产品root前提。

Emulator37.2.12忽略非qemu的 `-prop ro.adb.secure=1`，不能以参数出现当设置成功；镜像的 `service.adb.tls.port`为空，使用系统页面实际端口及当次动态转发。安全条件必须由新身份真实被拒绝验证。[adbd入口](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/daemon/main.cpp)解释认证属性路径，但分支源码不冒充镜像二进制完全同源。

Core曾将CertificateUnknown记成offline并继续重连；实际Runtime红测后修复为unauthorized/autoReconnect=false，保留真实原因。可显式复验：

```sh
ANDROID_TLS_ENDPOINT=<实际TLS连接端口的宿主转发> \
  cargo test -p interop-adb --test android_wireless \
  android_unpaired_identity_cannot_open_tls_transport -- --include-ignored --exact
ANDROID_TLS_ENDPOINT=<同一端点> \
  cargo test -p interop-core --test first_trust_android -- --include-ignored
```

## API36系统撤权竞争

直接点击Settings Forget的完整链路曾失败：公钥移除后元数据残留，重启恢复信任，日志出现AtomicFile重命名失败。固定阅读的[AOSP AdbDebuggingManager](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android16-release/services/core/java/com/android/server/adb/AdbDebuggingManager.java)和[AtomicFile](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android16-release/core/java/android/util/AtomicFile.java)支持设置返回页读取与异步持久化竞争这一原因，未修改框架证明所有时序。

独立实验停止设置页后调用同一IAdbManager.unpairDevice，确认本次公钥/元数据消失、宿主基线保留，不编辑授权文件。host因此仅在API36用事务7，取唯一指纹、停止设置、发请求并等真实清除；拒绝其他API，不把事务号当通用产品API。

最终连续两轮完成未授权拒绝、错码、PAKE、Required TLS、该系统接口撤权及旧身份拒绝，所有清理/基线保留回执齐备。通过的是“接口精确撤权后产品拒绝”，不是直接Settings Forget、量产安全或任意OEM撤权。

## 错误反馈与剩余范围

中文失败展示仍保留结构化原始原因：明确配对拒绝不笼统称码错，EOF只说明中断。真实安全AVD复验覆盖唯一中文提示、重新配对保留设备/地址、端口/码重新填写及再次TLS/撤权；初次英文回退错误修复后才记录通过。

码过期、切网/后台、真实QR系统扫码、跨设备mDNS、USB、重装/密钥迁移、纯Rust密码提供器发布安全及四宿主均分别验证。设备专用扫码身份和TCP失败记录保护见[设备与系统证据](validation.md#设备与系统证据)，不借旧配对链路宣称已在实体设备互操作。
