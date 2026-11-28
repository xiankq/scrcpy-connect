# 设计素材

本目录列出仓库里每个素材的来源和许可。新增素材时在这里补一行来源。

## 原创素材

- [应用图标](app-icon.svg)：邻接的原创矢量稿。形状、颜色、各平台遮罩和使用场景见[应用图标规范](../design.md#应用图标)。
- `app/assets/device/`：从 Ardot 导出的原创图层。
  - `intro-*.png`：「首次添加」插画里的卡片、手机和各自的阴影。[Ardot 首次添加插画](https://ardot.tencent.com/file/749360133997361?node_id=12%3A1)
  - `connection-*.png`：「连接等待」用的本机标记（明暗两套）和共用的手机轮廓。[Ardot 连接等待组件](https://ardot.tencent.com/file/749360133997361?node_id=9%3A801)

## 示例照片

用在设计稿的相册、背景和预览示例里。

| 文件 | 作者 | 原图来源 |
| --- | --- | --- |
| `sample-lake.jpg` | [Spencer DeMera](https://unsplash.com/@spencer_demera) | [Unsplash 图片](https://images.unsplash.com/photo-1658601877304-21af2b1a7068) |
| `sample-architecture.jpg` | [anthony mcgee](https://unsplash.com/@tmg) | [Unsplash 图片](https://images.unsplash.com/photo-1502473379243-ba6449c3b6c4) |
| `sample-forest.jpg` | [Chrissy](https://unsplash.com/@cthecreator) | [Unsplash 图片](https://images.unsplash.com/photo-1663998606502-5d8a320325ca) |

对外分发前，核对 [Unsplash 许可](https://unsplash.com/license)以及实际用途涉及的其他权利（如照片中的人物、建筑）。

## Android 应用图标

下列图标都在 Android API 36 上通过 PackageManager 读取，尺寸 96×96，用作"真实应用任务"的示例内容。

| 素材 | 应用包名 | 示例名称 |
| --- | --- | --- |
| `android-settings-api36.png` | `com.android.settings` | 设置 |
| `com.android.chrome-api36.png` | `com.android.chrome` | Chrome |
| `com.google.android.calendar-api36.png` | `com.google.android.calendar` | 日历 |
| `com.google.android.contacts-api36.png` | `com.google.android.contacts` | 联系人 |
| `com.google.android.dialer-api36.png` | `com.google.android.dialer` | 电话 |
| `com.google.android.apps.messaging-api36.png` | `com.google.android.apps.messaging` | 信息 |
| `com.google.android.apps.photos-api36.png` | `com.google.android.apps.photos` | 相册 |
| `com.android.camera2-api36.png` | `com.android.camera2` | 相机 |

这些图标保持原色，只代表对应的手机应用，不能当作邻接的品牌图标或功能图标。

## 设计稿字体

MiSans 只用于设计稿。来源、字重、文件摘要和许可见[字体说明](fonts/misans/README.md)；应用运行时用的字体见[视觉规范 · 文字](../design.md#文字)。
