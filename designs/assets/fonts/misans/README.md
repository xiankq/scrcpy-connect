# MiSans 设计素材

字体来自小米 [MiSans 官方下载页](https://hyperos.mi.com/font/zh/download/)，下载归档为 [MiSans.zip](https://hyperos.mi.com/font-download/MiSans.zip)，于 2026-10-23 获取。从官方归档的 `MiSans/woff2/` 提取以下四个原始文件，未修改、裁剪或转换字体。

`designs/mobile.pen` 使用文档自定义字体引用此目录，路径相对于 `.pen` 文件为 `./assets/fonts/misans/MiSans-<字重>.woff2`。字体族统一注册为 `MiSans`，设计稿语义字重对应如下：

| 文件 | 设计稿字重 | SHA-256 |
| --- | --- | --- |
| `MiSans-Regular.woff2` | 400 | `d704c1a932c0bd7e8a071d276cd81c0ed0c9fecfa26ac234f4bed0559fe1cb2d` |
| `MiSans-Medium.woff2` | 500 | `44e28ca6c2f0ca79829f192831ef87b5eec7c464f5cfb7a83467f57bb6e58114` |
| `MiSans-Semibold.woff2` | 600 | `78227c6ec59566785c65ac0b5312328bfa2f879918f3d7403725785615a9a8f6` |
| `MiSans-Bold.woff2` | 700 | `1c5a7515b61bc82baaa2e2c2fdae2032479fb9a99e09d4d021dc17314fc5939b` |

[LICENSE.pdf](LICENSE.pdf) 为小米发布的[字体知识产权许可协议](https://hyperos.mi.com/font-download/MiSans字体知识产权许可协议.pdf)，随字体保留。移动或分享设计稿时须保留上述相对目录及许可；无需安装到系统或用户字体目录。Pencil 的[自定义字体说明](https://docs.pencil.dev/core-concepts/drawing-and-editing#text-and-fonts)要求字体文件随设计稿保留。

这些文件只服务设计稿，不加入应用资源或运行时字体设置。各端代码继承默认字体的规则见[视觉规范](../../../design.md#typography)。
