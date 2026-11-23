# 第三方组件和素材

项目使用的外部组件仍适用各自的许可证。以下列出对公开源码与分发安装包影响较大的来源。

| 组件 | 随仓库或安装包提供的内容 | 来源与许可 |
| --- | --- | --- |
| scrcpy | Android 被控端使用的 scrcpy server 与许可文件 | [仓库内构建说明](servers/vendor/README.md) · [scrcpy 上游许可](https://github.com/Genymobile/scrcpy/blob/master/LICENSE) |
| Android desugar_jdk_libs | scrcpy server 的 Android 兼容库、对应源码归档、许可与附加条款 | [保留的组件和材料](servers/vendor/) |
| Android SDK Platform-Tools | 桌面端随包的官方 ADB 和平台相关文件 | [固定版本与校验和](packages/adb/third_party/platform-tools.lock.json) · [Android SDK 条款](https://developer.android.com/studio/terms) |
| FFmpeg 和 dav1d | 媒体解码库、随包声明、所用版本与补丁 | [依赖、来源和补丁](packages/media_codec/third_party/) · [FFmpeg 分发说明](https://ffmpeg.org/legal.html) · [dav1d 上游](https://code.videolan.org/videolan/dav1d) |
| nv-codec-headers / libva | Linux 媒体构建用头文件、随桌面包提供的 libva 与其声明 | [nv-codec-headers 固定版本](packages/media_codec/third_party/nv-codec-headers.lock.json) · [libva 上游](https://github.com/intel/libva) |
| 设计素材 | 设计稿中的示例照片、Android 应用图标与 MiSans 字体 | [设计素材来源](designs/assets/README.md) · [MiSans 来源与许可](designs/assets/fonts/misans/README.md) |

GitHub 发布流程会收集对应的媒体上游归档、校验文件、补丁和构建脚本，应用包也保留原生依赖随附的许可。首次公开前还需要确认 ADB 的再分发依据，以及静态链接媒体库所需的重新链接和其他交付材料。办理步骤见[维护者清单](docs/release-owner-checklist.md)。
