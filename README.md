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

## 工作区

| 目录 | 内容 |
| --- | --- |
| `app/` | Flutter应用、业务与平台runner |
| `packages/`、`rust/` | 同名通用能力包及原生实现 |
| `servers/` | 被控临时执行产物及来源 |
| `designs/` | 产品与视觉规范、Ardot 对照资料 |
| `scripts/` | 生成、检查与构建 |

入口：[产品](designs/prod/README.md) · [视觉](designs/design.md) · [应用约束](app/lib/AGENTS.md) · [脚本](scripts/README.md) · [词表](GLOSSARY.md)。
