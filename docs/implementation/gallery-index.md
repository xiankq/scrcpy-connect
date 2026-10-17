# 共享存储相册检查与快照分页

`media.list`检查当前用户的主共享存储，包含根部媒体、Download、自定义目录和Android/media。它按扩展名识别照片与视频，不冒充Android系统媒体库、其他用户或其他存储卷；Android/data、Android/obb、子符号链接和特殊文件在公开scope中列明排除。modified是文件修改秒数，不是拍摄时间。

## 公开契约与生命周期

- `media.list({deviceId,limit?})`创建一次异步只读检查；立即返回scanId、scanning状态、进度和空items。终态前不呈现尚未冻结的媒体集合。
- `media.list({deviceId,scanId,offset?,limit?})`只读同一快照；deviceId必须一致，过期身份明确拒绝。limit为1–200，默认100。终态按modified降序、path升序冻结，返回total、nextOffset及所请求页；刷新创建独立快照，旧页不随手机变化而偷偷重排。
- `media.scan.cancel({deviceId,scanId})`只取消该检查，保留已读内容并冻结为cancelled；不停止连接、传输、远控或其他检查。断开和Runtime销毁也取消所属worker，worker不持Runtime。
- completed只表示公开范围内没有发现扫描问题。partial保留可访问内容及issues／issueCount／truncated，不等同整台手机或所有格式完整。目录前后元数据和实际遍历权限按尽力原则核对；这不是文件系统事务隔离，打开与保存原件继续重验。

逐目录优先SYNC，针对某些adbd权限拒绝被返回空DONE的问题，先后核验read／execute。LIS2因元数据错误或单目录超限时采用有界逐目录shell回退；保留限额内媒体，失败条目仍计入检查预算。无效UTF8不生成可误操作的替代路径，不跟随子链接。

检查有30秒deadline、50000项、4096目录、32层、25000媒体、每目录4096项、128条问题展示及每快照8MiB保留容量预算；问题另计总数。typed记录计入容器容量和全部拥有的字符串，保留固定预算用于明确返回snapshot_byte_limit。最多2个活动检查、8个终态快照，终态淘汰后旧ID明确过期。该预算只属于相册索引内存，不能作为A51媒体原件／缩略图磁盘预算已实现的证据。

Flutter每页拥有一个固定设备的检查，展示检查／停止、已显示与总数、范围／未读目录、有限空态和加载更多。离页和刷新取消精确旧检查；即使首次回执迟到也退回其scanId。请求代际与读序号排除迟到页，换设备重置所选项；读取或归属错误不混入其他设备内容。下拉或刷新按钮开始新检查，加载更多只读旧快照。

## 已执行的公开测试

`rtk proxy /home/xiankq/.cargo/bin/cargo test -p interop-core --test gallery_index`：十项Runtime协议fixture通过，最终10.45秒；窄clippy严格通过。覆盖动态目录／root媒体、mtime同秒排序、分页／刷新隔离、拒权空DONE、精确取消／错设备／两活动及八终态、断开、非法名称／链接／源变化、legacy根别名、目录与全局预算、字节预算。

真实先红后绿包括：旧media.list无异步状态；4097项目录total=0而应保留4096；fallback元数据失败不计全局预算；64条拒权后耗尽内存预算时，错误的预留容量导致panic。最终保留prefix、把失败计入examined、按最大问题容器容量预留后通过。fixture不冒充真实adbd或Android主控E2E。

页面公开测试已复现并修复partial空结果称全相册为空；同快照分页、刷新后迟到旧页、首次admission离页取消、错设备及换设备选择隔离另有相关回归。七项公开页面测试通过，含100＋5项的真实滚动布局。

## 真实Android入口与保留边界

从apps/connect运行，下列仅为测试宿主部署／对照使用adb，产品仍经FRB和自有Rust库：

```sh
rtk proxy env CONNECT_E2E_ADB=/home/xiankq/Android/Sdk/platform-tools/adb \
  CONNECT_E2E_DEVICE=emulator-5554 CONNECT_E2E_TARGET=emulator-5556 \
  CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/gallery-index \
  flutter drive -d emulator-5554 --no-pub \
  --driver=test_driver/gallery_index.dart \
  --target=integration_test/gallery_index_test.dart \
  --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 \
  --dart-define=CONNECT_E2E_PORT=15556
```

夹具通过实际产品上传105个PNG原件，包含共享根、Download、自定义目录、Android/media；公开Runtime逐页核验路径、唯一性与排序，实际相册读取／解码缩略图、加载更多、展开范围、修改后主动刷新。旧快照保持不变，新快照才能纳入新文件；宿主通过VM service精确握手，在文件清理前独立读取原件字节和全部大小，结束后检查精确路径已消失。

模拟器是API36 legacy TCP测试目标，不能替安全首次配对或量产OEM；Android/data/obb保持排除，不用root扩大产品权限。真实目录拒权、切网／重连／进程回收、大原件／损坏格式／低内存，以及拍摄时间索引和持续增量更新仍应分别验证。刷新独立快照并不是持续增量索引，A53与相册任务尚不整体关闭。

首轮真实运行日志`/tmp/connect-gallery-index-r1.log`：105PNG目录覆盖、稳定分页、实际缩略图解码已完成，但截图传args在当前Android integration_test明确assert失败，完整E2E不通过；finally精确清理并获宿主路径不存在证明。已用Dart MCP读取该锁定依赖的_IOCallbackManager源码，并检索takeScreenshot／onScreenshot：IO端要求args==null，不能凭通用签名推定支持。测试改用本仓库既有VM service模式作有身份的独立核验握手，截图只传名称。此项是测试夹具修正，不作产品功能成功证据。

第二轮真实验收`/tmp/connect-gallery-index-r2.log`已独立核验105个文件大小和4207字节样本原文，清理独立通过，但分页汇总断言失败，未计完整通过。以同一公开页面构造100＋5项的滚动测试，确认页查询已到offset100，而汇总Sliver滚出后不再被finder呈现；先回到范围／汇总位置再断言105／105后通过。真实用例同步保持实际加载更多点击、精确105总数和分页排序要求，不放松成仅按钮消失。

第三轮完整85秒通过：`/tmp/connect-gallery-index-r3.log`、`/tmp/connect-e2e/gallery-index-r3/result.json`。必需回执及独立原文／105大小／精确清理全true，hostErrors为空；实际加载更多、范围面板与刷新后106项／旧快照105项已验证。主代理已目视首页网格和范围截图。

该轮仅要求至少一张实际缩略图解码，目视暴露A57：各cell直接并发请求，而companion只有一个worker和一个等待位，busy后widget保持失败、离屏未精确取消。此证据只能证明单张通路，不能证明多图网格可用。共享有界调度、精确取消、有限busy恢复和真实多图门槛须单独实现与复验；A53和相册领域仍未整体关闭。

本批代码完整`tool/check.sh --android`退出0，日志`/tmp/connect-gallery-all-gates.log`：应用237／Bridge106／设计系统3、Rust186 passed／58 ignored，150输入生成一致、205文件格式零改动、严格分析／clippy／lint负例／capture JAR与JVM、三ABI APK125.8秒／四组native main／实际manifest和Flutter／Rust ELF均通过。默认ignored不计通过；DESIGN仍31警告／1信息，原有Kotlin警告保留。这份门禁先于A57修复，不外推后续代码。
