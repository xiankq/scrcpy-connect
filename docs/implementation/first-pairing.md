# 首次配对、加密连接与撤权

产品使用自己的 Rust 身份，通过被控 Android 系统的配对码窗口完成 PAKE，再使用独立连接端口建立 Required TLS。宿主测试工具只操作系统设置、读取当次码和准备网络转发；不执行 `adb pair`，不导入产品私钥，不在被控设备安装 APK。配对成功与连接成功分别确认。

## 可重复的产品链路

`integration_test/first_pairing_test.dart` 启动真实 app.main、FRB 和 Runtime，经 typed route/实际表单验证：

1. 未配对时访问实际 TLS listener，要求明确的证书授权拒绝，不能以超时/拒绝连接代替。
2. 输入由当前码改一位的错误码，确认真实配对失败且未保存 GUID。
3. 宿主重新打开系统配对窗口，把新码交给测试；真实表单配对并保存 GUID。
4. 使用独立连接端口，读取真实设备能力，确认连接与配对是两个完成点。
5. 主动断开；宿主从系统设置读取本次新增 `interop-controller` 的指纹，关闭设置页后调用系统撤权接口，只撤销该身份；产品再次连接必须被拒，状态为未授权且不自动重连。
6. 精确删除本次设备记录、配对项、转发和临时 XML，保留基线设备及其他已配对身份。补收集和单项删除失败不会跳过其余已知记录。

宿主 driver 用 VM service extension 协调步骤；码不进入 extension 响应、报告或截图。初始拒绝阶段不截图，避免晚到的截图拍到后续配对码。工作台截图发生在实际连接仍保持的 `need-connected-capture` 等待点；撤权拒绝截图也通过专用握手等待完成，两者均不含码。报告中的证书错误只用于证明真实拒绝原因。

工作目录 `apps/connect`，PATH 含 Rust/Flutter，目标已按下面条件准备；图片/日志仍只在 tmp：

```sh
rtk proxy env CONNECT_E2E_ADB=/home/xiankq/Android/Sdk/platform-tools/adb \
  CONNECT_E2E_DEVICE=emulator-5554 CONNECT_E2E_TARGET=emulator-5558 \
  CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/first-pairing \
  flutter drive -d emulator-5554 --no-pub \
  --driver=test_driver/first_pairing.dart \
  --target=integration_test/first_pairing_test.dart
```

driver 要求明确、不同的两个 AVD；目标开发者选项、Wi-Fi 与无线调试已开启，系统界面为该夹具验证过的英文 API36。没有预存的同名产品配对项才允许撤销本次项；基线存在同名项时拒绝准备且不修改它。所有必要产品回执、系统精确撤权及清理回执齐备才通过；不能把局部结果称为完整产品验收。

## 安全测试环境

本机原 API36 Google APIs GSI 的 `/system_ext/etc/build.prop` 明确包含 `ro.adb.secure=0`。AOSP adbd 在可调试/解锁环境读取该属性决定是否要求认证，见 [daemon/main.cpp](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/daemon/main.cpp)。旧目标接受未配对身份的负例失败仍保留，不能用配对正例覆盖。

本轮仅为第三台 `interop-target-b` 构造隔离测试环境：以 `-writable-system -no-snapshot` 启动，临时 root/remount、重启挂载覆盖层，仅将该文件中的 `ro.adb.secure=0` 改为 `1` 后再次重启。原文件保存在 `/tmp/connect-first-trust-fixture/system_ext-build.prop.original`；原摘要 `c71f1bbdea16cceed528cfa4a7d761ebee0aed2b985790dec33be649b1633540`，改后 `8b62fa8e92715aa3611c64c55abe2dc77146bd0396409c3191eea7bd10989023`。SDK 原镜像未编辑，不修改前两台的认证配置，不将测试准备变成产品 root 前提。

emulator37.2.12 对 `-prop ro.adb.secure=1` 明确报告只支持 qemu.*，实际属性仍0，不能以该参数出现作为成功证据。系统完成启动、Wi-Fi 连上 AndroidWifi、允许此网络无线调试后，使用系统页面显示的实际连接端口；本镜像 `getprop service.adb.tls.port` 为空，不能依赖它。宿主只为当次端口创建动态转发。

实际记录为 API36、`google/sdk_gphone64_x86_64/emu64xa:16/BE2A.250530.026.F3/13894323:userdebug/dev-keys`，`ro.adb.secure=1`、`ro.debuggable=1`、verifiedbootstate=orange，重启后实际 shell UID2000。这是修改过的可调试模拟器，不能声称量产锁定镜像、OEM 或硬件安全已验收。

仅属性不足以证明安全。先用真实 Android 新身份拒绝用例，再用公开 Runtime 回归确认状态与重连行为；初始测试记录在 `/tmp/connect-first-trust-unpaired.log`、`connect-first-trust-core-status-red.log`、`connect-first-trust-core-green.log`。Core 先真实失败：`CertificateUnknown` 被误标 offline；补入授权拒绝分类后，unauthorized/autoReconnect=false 通过。

```sh
# endpoint 是系统连接端口的本次宿主转发，绝不是配对端口。
rtk proxy env ANDROID_TLS_ENDPOINT=127.0.0.1:<当次宿主转发端口> \
  cargo test -p interop-adb --test android_wireless \
  android_unpaired_identity_cannot_open_tls_transport -- --include-ignored --exact
rtk proxy env ANDROID_TLS_ENDPOINT=127.0.0.1:<当次宿主转发端口> \
  cargo test -p interop-core --test first_trust_android -- --include-ignored
```

结果、工具失败与视觉边界另记[验收记录](validation.md)。QR 系统扫码、跨 AVD 真实 mDNS、系统码过期/切网/切后台、USB、身份重装/备份、四端密钥与密码实现发布资格仍需分别验证。本链路不替代这些要求，也不关闭首次设置与完整 ADB 任务。

## API36 系统设置撤权竞争

直接点击设置页 Forget 的完整测试失败，不能记为通过：系统先移除 `adb_keys` 中本次公钥，但 `adb_temp_keys.xml` 与列表仍残留；重启后公钥恢复。目标日志明确出现 `AtomicFile: Failed to rename /data/misc/adb/adb_temp_keys.xml.new to /data/misc/adb/adb_temp_keys.xml`。独立读取只显示公钥摘要/存在性，未读取产品私钥。该负例不是仅凭列表推断。

[AOSP AdbDebuggingManager](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android16-release/services/core/java/com/android/server/adb/AdbDebuggingManager.java) 的 `getPairedDevices` 新建 keystore，`MSG_REQ_UNPAIR` 删除并异步持久化；[AtomicFile.openRead](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android16-release/core/java/android/util/AtomicFile.java) 明确要求调用者同步，且读取旧文件时会删除现有 `.new`。结合实际日志，设置返回页读取与持久化相撞是得到支持的原因；未修改系统框架来证明所有可能时序。

独立最小实验先重启加载残留身份，然后停留主屏，调用同一个 [IAdbManager.unpairDevice](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android16-release/core/java/android/debug/IAdbManager.aidl) 接口，结果 Parcel 无异常；2秒后 dumpsys 中产品公钥和元数据均消失，原有宿主仍保留。没有编辑授权文件。由此将 host driver 的撤权动作固定为 **API36 的事务7**：先在唯一产品详情读取指纹，停止系统设置进程后发接口请求，不让设置页在提交间隙重读文件；等待元数据及授权文件移除、基线公钥保留，再回设置核对。driver 会拒绝其他 API，不把事务编号当成通用跨版本产品API。此操作只属于宿主测试夹具，普通主控不调用该特权服务、不需要调试或root。

最终完整 E2E 已连续两轮64秒通过，范围是“系统接口精确撤权后产品拒绝旧身份”，**不能称直接 Settings Forget 路径或量产镜像已通过**。默认自动检查也不执行该设备夹具；完整结果见验收记录。

本次下载的 android16-release 源内容 SHA-256：AdbDebuggingManager `428b0cec9a84ba5c29bb43553fca05f2f127e23f41a39a82f935e918e3e45fd7`、AtomicFile `90e1cc85e92e53e6c257e49156677de354a79d2b6caf65d826cb77d0cffab70e`、IAdbManager `34759f2a5dde1b67874e61d9a1970bdbc1a67c0d14c658213085db6221858ca6`。分支名不是不可变提交；摘要固定本次阅读内容，不声称等同 AVD 内二进制源码。
