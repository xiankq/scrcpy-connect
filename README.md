# 邻接 · Interconnect

通过系统USB/无线调试授权访问Android设备，提供远控、文件、相册与通信入口；被控不安装配套APK。功能门槛见[平台与能力](designs/prod/compatibility.md)。

## 开发

准备 Flutter 3.50+（Dart 3.14+）、`rust-toolchain.toml` 指定的Rust、JDK21和Android SDK：

```sh
flutter pub get --enforce-lockfile
npm ci --ignore-scripts --prefix scripts/design_tokens
cd app
flutter run -d <device>
```

完整检查在仓库根运行 `./scripts/check.sh`。Android 打包与桌面构建见[脚本入口](scripts/README.md)。

## 应用标识与桌面启动

中文产品名为「邻接」，英文名为 Interconnect。macOS 交付 `Interconnect.app`，Windows 入口是 `Interconnect.exe`，Linux 入口是 `interconnect`。Windows 从旧交付包升级后，指向旧文件名的快捷方式需指到新入口。

Android 的 Application ID、Apple 端的 Bundle ID、Linux 的 GTK 应用 ID、Windows 的通知 AppUserModelID 和应用数据目录均沿用现有身份。更换身份需单独评估存储、授权、签名与覆盖升级。

Linux 可直接运行解包目录下的 `./interconnect`。要添加到应用菜单，将解包目录加入桌面会话的 `PATH`，把随包的 `share/applications/` 与 `share/icons/` 内容分别安装到 `${XDG_DATA_HOME:-$HOME/.local/share}/applications/` 和 `${XDG_DATA_HOME:-$HOME/.local/share}/icons/`。保留解包目录下可执行文件与资源的相对位置。

## 工作区

| 目录 | 内容 |
| --- | --- |
| `app/` | Flutter应用、业务与平台runner |
| `packages/`、`rust/` | 同名通用能力包及原生实现 |
| `servers/` | 被控临时执行产物及来源 |
| `designs/` | 产品与视觉规范、Ardot 对照资料 |
| `scripts/` | 生成、检查与构建 |

入口：[产品](designs/prod/README.md) · [视觉](designs/design.md) · [应用约束](app/lib/AGENTS.md) · [脚本](scripts/README.md) · [词表](GLOSSARY.md)。
