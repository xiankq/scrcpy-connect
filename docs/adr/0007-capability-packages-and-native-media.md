---
status: accepted
---

# 远控媒体保持原生路径

只提供实时远控媒体，不引入本地播放器；Rust scrcpy 将带代际的压缩包直交 FFmpeg 解码，不经过 Dart 字节事件、MKV 或 HTTP 中转，以控制包体、队列延迟及维护成本。

固定 FFmpeg 源码及配置，只保留视频解码、解析与像素转换；AV1 软件回退用裁剪 dav1d。硬解失败按当前 GOP 恢复软件解码；平台代码仅承担纹理、音频及必要系统接口，代价是维护有限平台胶水、回退及构建链。能力归属见 [0008](0008-reusable-packages-and-application-composition.md)。
