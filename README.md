# 邻接 · Interconnect

通过系统USB/无线调试授权访问Android设备，提供远控、文件、相册与通信入口；被控不安装配套APK。功能门槛见[兼容条件](docs/implementation/android-target-compatibility.md)。

## 开发

准备Flutter、`rust-toolchain.toml` 指定的Rust、JDK21和Android SDK：

```sh
flutter pub get --enforce-lockfile
npm ci --ignore-scripts --prefix scripts/design_tokens
cd app
flutter run -d <device>
```

完整检查在仓库根运行 `./scripts/check.sh`。发布见[Android打包](docs/implementation/android-packaging.md)及[桌面构建](scripts/README.md)。

## 工作区

| 目录 | 内容 |
| --- | --- |
| `app/` | Flutter应用、业务与平台runner |
| `packages/`、`rust/` | 同名通用能力包及原生实现 |
| `servers/` | 被控临时执行产物及来源 |
| `protocol/` | 应用命令契约 |
| `designs/` | 产品、视觉规范及Pencil源稿 |
| `scripts/` | 生成、检查、构建与设备驱动 |

入口：[产品](designs/prod/README.md) · [视觉](designs/design.md) · [架构](docs/implementation/architecture.md) · [工具链](docs/implementation/repository-tooling.md) · [词表](GLOSSARY.md) · [ADR](docs/adr/)。
