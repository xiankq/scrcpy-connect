# 验证证据与边界

此处索引版本化证据；当前行为归[产品规格](../../designs/prod/README.md)，资源归[架构](architecture.md)，构建归[工具链](repository-tooling.md)。证据层级采用[产品验收依据](../../designs/prod/coverage.md#验收依据)，ignored/skipped不计通过，代码变更后不自动继承旧包摘要或平台结果。

## 版本化工程与平台记录

| 记录 | 责任 |
| --- | --- |
| [原生媒体](native-media-validation.md) | 2026-10-23跨平台运行、历史严格性能及组装入口 |
| [公共整改](scrcpy-audit-fixes.md) | 公共C/S项、启动故障、固定依赖及当轮最终交付摘要 |
| [桌面整改](scrcpy-audit-desktop-fixes.md) / [Windows运行](windows-native-media-validation.md) | D项、GPU/PCM、ADB关闭与普通bootstrap |
| [移动/Apple整改](scrcpy-audit-mobile-apple-fixes.md) / [Apple运行](apple-native-media-validation.md) | A项、JNI、Metal/AudioQueue、SDK与模拟器/实体边界 |
| [传输整改](scrcpy-audit-transport-fixes.md) | T项、输入代际、USB与控制回归 |
| [ADB服务](../../packages/flutter_adb/test/README.md) | 私有官方server和typed适配器 |
| [文件能力](../../packages/device_files/VALIDATION.md) | 当前Dart任务所有者、持久恢复及原生执行组装 |

## 控制、连接与恢复

有界控制/健康策略归[连接健康](connection-health.md)，事件缺口/播放器重验归[状态恢复](state-recovery.md)，未知启动归[应用接续](app-launch-recovery.md)。主机回归保护连接替换、迟到回执、明确停止及未知副作用不重放；真实性能按[测量契约](video-performance.md)取证。

## 设备与系统证据

以下专题保留2026-10-17至22的API36样本环境、入口和专有限制；文件/媒体迁移后的现行所有者结果以以上专项为准。

| 领域 | 证据入口 |
| --- | --- |
| PAKE/TLS、撤权、发现 | [首次配对](first-pairing.md)、[无线重连](wireless-reconnect.md) |
| 输入、系统入口 | [IME](mobile-ime.md)、[当前通话](current-call-ui.md)、[主控提醒](system-notifications.md) |
| 文件/相册/交付 | [搜索](file-search.md)、[图库](gallery-index.md)、[缓存](media-cache.md)、[系统交付](content-delivery.md) |
| 视觉 | [源稿与捕获](design-fidelity.md)，llvmpipe环境不外推物理GPU |
| 旧被控系统 | [API21/API23局部功能](android-target-compatibility.md#验证证据) |

USB/IP装置已核对系统允许/拒绝、FD交接、真实adbd shell/sync及拔除重获，物理USB/OTG/HAL/RSA授权仍需设备验证。OEM、物理Wi-Fi漫游、权限组合、进程死亡、长期温控与声学输出按各专项保留边界。

## 性能证据

定义与预算归[视频测量](video-performance.md)。首包、playing、Texture挂载、snapshot与显示各有终点；历史fvp/MDK、Debug/AVD及软件renderer分布不继承为当前链路结果，跨模式/环境不作速度排名。

## 复现入口

根目录运行 `./tool/check.sh`；Android扩展为 `./tool/check.sh --android`，需SDK/工具链。具体检查以脚本为准。Flutter build/drive从app执行；原生媒体独立workspace与平台入口按专项运行。

设备用例显式提供隔离目标和opt-in，见[E2E工具](../../tool/e2e/README.md)及driver声明。默认门禁不运行全部环境用例；截图、日志和测试安装留系统临时目录并按所有权清理。
