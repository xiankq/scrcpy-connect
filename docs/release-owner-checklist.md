# 发布前需要维护者补充的事项

这份清单分为首次公开必须完成的事项，以及开启其他发布渠道时才需要办理的事项。签名密钥和密码直接填入密钥管理器或 GitHub Secrets。

## 首次公开前

### 1. 确定项目许可证和著作权人

**为什么需要** 公开仓库以后，用户仍需要明确的授权才能复制、修改和再分发项目代码。第三方组件已有的许可证只适用于各自组件。

**怎么做** 确认原创代码和设计的权利归属，以及希望开放的范围。选定许可证和版权署名后，把许可证原文作为仓库根目录的 `LICENSE` 提交。多人或公司参与的部分也请确认授权。遇到混合许可时，保留各组件原有的声明，并标明各自适用范围。发布流水线会检查根目录是否有 `LICENSE`。 [GitHub 许可证说明](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)

**需要你给出** 许可证名称、著作权人、需要单独授权的代码或设计范围。

### 2. 确认随包转发 ADB 的依据

**为什么需要** Windows、Linux x64 和 macOS 的包包含从 Android SDK 下载的官方 Platform-Tools 文件。能公开下载 SDK 和能把它放进另一个产品分发，需要分别确认。Linux ARM64 使用发行版提供的 ADB。

**怎么做** 对照 `packages/adb/third_party/platform-tools.lock.json` 中各平台的实际组件及其附带条款，确认批量再分发的许可依据，并保存相关许可和署名。如果当前下载包的条款无法支持预期分发，决定改用可再分发的构建来源，或调整桌面安装方式，再重新验证连接和卸载。 [Android SDK 条款](https://developer.android.com/studio/terms)

**需要你给出** 可接受的来源及确认依据，或选择先改桌面 ADB 的交付方式。

### 3. 确认静态链接的媒体库如何交付

**为什么需要** 应用会把裁剪后的 FFmpeg 和 dav1d 链接进原生模块。正式发布附件已有对应上游源码、补丁和构建脚本。FFmpeg 的 LGPL 义务还涉及用户替换库后重新链接，源码附件是一部分材料。

**怎么做** 逐平台核对构建选项、链接方式和随包许可。保持静态链接时，准备适用许可要求的可重新链接材料、准确构建命令和必要对象文件，并用干净环境实际完成一次替换 FFmpeg 后的重新链接。也可评估改成适用的动态链接交付，再验证旧系统和干净安装。已收集的来源见[第三方组件](../THIRD_PARTY_NOTICES.md)。 [FFmpeg 分发说明](https://ffmpeg.org/legal.html)

**需要你给出** 采用的交付方式、对应材料的公开位置，以及确认已经做过替换验证的发布平台。

### 4. 清点要一并公开的设计素材和 Git 历史

**为什么需要** 仓库里有 Android 预置应用图标、示例照片和 MiSans 用字。公开源码也会公开当前分支能够访问的 Git 历史，旧提交可能含有已经删出工作区的私人数据。

**怎么做** 按[素材来源表](../designs/assets/README.md)逐项确认图片、字体、应用名称与截图能否按现有形式公开。无法确认的内容先替换成可公开的素材。核对将要公开的分支、标签和历史，重点看签名文件、ADB 身份、账号、设备地址、配置和截图。

本地用 `gitleaks git --log-opts='--all' --redact=100` 扫描了历史。校验和与测试数据可以从代码确认。旧版 `designs/mobile.pen` 还有两个形如 UUID 的 `fileToken`，出现在 `95b734ced8` 和 `f18c1506b5`。请用原设计平台确认它们是否仅为文件编号。如果其中任一个可授权访问，先撤销或轮换，再决定公开历史的处理方式。

**需要你给出** 已确认的素材范围、需要替换的条目、旧设计编号的确认结果，以及是否需要保留既有 Git 历史。

### 5. 确定 Android 正式签名

**为什么需要** Android 只允许签名兼容的 APK 覆盖同一个应用。换成新签名后，既有用户可能需要卸载才能安装，应用本地数据也可能随之丢失。

**怎么做**

1. 如果已经发过 APK，在能访问的机器上用 SDK 的 `apksigner verify --print-certs 旧版.apk` 取得 `Signer #1 certificate SHA-256 digest`。用 `keytool -list -v -keystore 密钥库路径 -alias 别名` 核对手中密钥库的证书指纹。
2. 如果还没有需要兼容的版本，可从仓库根运行 `dart scripts/android.dart init-signing` 生成专用签名。用安全存储备份密钥库、密码和别名，记录谁负责保管。
3. 在 GitHub **Settings → Environments → release** 的 **Environment secrets** 加入下表四项。安装了 GitHub CLI 时，密钥库一项可在本机使用 `base64 < 密钥库路径 | tr -d '\n' | gh secret set ANDROID_SIGNING_STORE_BASE64 --env release`。用实际路径替换 `密钥库路径`。
4. 在同一环境的 **Environment variables** 添加 `ANDROID_SIGNER_SHA256`，值为正式证书指纹。跑通发布后，用旧包安装再覆盖新版，确认版本和本地数据保留。 [GitHub Actions Secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets)

| Secret | 填什么 |
| --- | --- |
| `ANDROID_SIGNING_STORE_BASE64` | 整个 JKS 或 PKCS12 密钥库文件的单行 Base64 |
| `ANDROID_SIGNING_STORE_PASSWORD` | 密钥库密码 |
| `ANDROID_SIGNING_KEY_ALIAS` | 发布证书对应的别名 |
| `ANDROID_SIGNING_KEY_PASSWORD` | 该别名下私钥的密码 |

**需要你给出** 是否已有必须兼容的 APK、正式证书指纹，以及 GitHub Secrets 已配置的确认。

### 6. 配置 GitHub 仓库和发布审核

**为什么需要** 自动发布依赖可用的 Actions、明确的发布权限和可访问的 GitHub Releases。应用用公开下载地址读取版本，仓库私有时普通安装用户无法访问该地址。

**怎么做**

1. 将工作流合入 `main` 后，在 **Settings → Actions → General** 确认允许仓库使用工作流中的 Actions。保留默认只读权限，发布任务会单独申请写入 Releases 所需的权限。
2. 在 **Settings → Environments** 建立 `release`。在 **Deployment branches and tags** 里选择只允许 `v*` 标签部署。有权限时配置审核人和禁止自己审批。根据仓库套餐，在 **Settings → Rules → Rulesets** 限制谁可以创建或移动 `v*` 标签。 [GitHub 环境配置](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments)
3. 先在 **Actions → Packages** 试打包，下载每个平台产物。Android 用真机试装，Windows 与 Linux 在 x64、ARM64 的干净系统试装，macOS 试开两种 DMG，iOS 检查编译归档。记录测试版本、架构和结果。
4. 如果仓库现在是私有的，完成前面的授权、素材和历史核对后，再决定是否公开。到 **Settings → Actions secrets and variables → Actions → Variables** 创建仓库变量 `PUBLIC_RELEASES_ENABLED`，值设为 `true`。从通过 CI 的 `main` 提交创建首发标签，审批后确认外部用户可下载并读取更新清单。 [GitHub 发布管理](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)

**需要你给出** 仓库公开时点、发布审批人、首次发布分支与版本，以及首发包验证结果。

### 7. 确认项目公开后的联系入口

**为什么需要** 用户需要知道从哪里反馈普通问题，发现涉及设备授权或数据的问题时也要有私下报告入口。

**怎么做** 在 GitHub 仓库启用 Issues 和 **Private vulnerability reporting**。用一个普通账号打开 [SECURITY.md](../SECURITY.md) 中的地址，确认能看到私下报告表单。确定安全报告接收人和公开维护方式。有隐私政策或应用支持页时，在 README 和对应渠道补上它们。 [GitHub 私下漏洞报告](https://docs.github.com/en/code-security/security-advisories/working-with-repository-security-advisories/configuring-private-vulnerability-reporting-for-a-repository)

**需要你给出** 日常 issue 和安全报告的接收人，是否提供额外的支持或隐私页面。

## 启用更多渠道时

| 渠道 | 为什么要补充 | 怎么做 |
| --- | --- | --- |
| macOS 独立下载 | 下载后的应用要通过 Gatekeeper，升级应沿用相同身份 | 提供 Apple Developer Team ID、Developer ID Application 签名身份、公证用凭据和所用 Bundle ID。接入签名、公证与凭证装订后，用另一台 Mac 从发布页下载并启动。 [Apple 公证说明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) |
| iOS TestFlight / App Store | iPhoneOS 编译归档需要由 Apple 的签名及渠道变成可安装包 | 确定 App Store Connect 团队、Bundle ID、分发签名和描述文件。准备 TestFlight 或商店所需的联系、隐私和设备连接说明，再在真机上验证。 [App Store Connect](https://developer.apple.com/help/app-store-connect/) |
| Windows 签名包 | 正式签名有助于用户核对发布者，可信度也取决于实际下载和系统表现 | 选定签名服务或代码签名证书，确认发布者名称。对 exe 或安装器签名并加时间戳，再从发布页下载并验证签名。 [Microsoft SignTool](https://learn.microsoft.com/en-us/windows/win32/seccrypto/signtool) |
| Google Play | 商店交付使用 AAB 和 Play App Signing，跨渠道覆盖安装取决于签名 | 确认是否上架、应用 ID 与应用签名方案。在 Play Console 配置应用签名和上传密钥，先走内部测试，再决定商店和 GitHub 包能否互相覆盖。 [Android 应用签名](https://developer.android.com/studio/publish/app-signing) |
| 其他 CPU 架构与安装格式 | 不同系统和 CPU 需要各自构建、测试及更新包 | 对照发布说明核验本次的格式和架构。若新增商店或更多架构，再检查原生依赖、系统版本和干净安装。 |

### 开启 macOS 的 GitHub 下载

在 `release` 环境设置以下三项 Secrets。这些值用于签名和调用 Apple 公证服务。

| Secret | 填什么 |
| --- | --- |
| `MACOS_CERTIFICATE_BASE64` | 导出的 Developer ID Application 签名证书和私钥 P12，转为单行 Base64 |
| `MACOS_CERTIFICATE_PASSWORD` | P12 导出时设置的密码 |
| `MACOS_NOTARY_KEY_BASE64` | 用于公证的 App Store Connect 团队 API 私钥 P8，转为单行 Base64 |

在同一环境配置 `MACOS_SIGNING_IDENTITY` 为证书完整名称，`MACOS_NOTARY_KEY_ID` 和 `MACOS_NOTARY_ISSUER` 为 API Key ID 和 Issuer ID。核对 Team ID 和 Bundle ID 后，在仓库级变量设置 `MACOS_RELEASE_ENABLED=true`，两种 DMG 都通过公证后才进入同一版发布。

**需要你给出** 两种芯片的下载与安装验收，以及证书和公证变量已配置的确认。 [Apple 公证工具](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
