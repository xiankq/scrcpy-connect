# 设计示例照片

照片由 Pencil 图片搜索返回，用于相册、手机背景与预览场景；本地保存以使 `.pen` 不依赖远程图片加载。它们是设计示例，不代表已选定应用发布素材。

| 文件 | 作者 | 原图来源 |
| --- | --- | --- |
| `sample-lake.jpg` | [Spencer DeMera](https://unsplash.com/@spencer_demera) | [Unsplash 图片](https://images.unsplash.com/photo-1658601877304-21af2b1a7068) |
| `sample-architecture.jpg` | [anthony mcgee](https://unsplash.com/@tmg) | [Unsplash 图片](https://images.unsplash.com/photo-1502473379243-ba6449c3b6c4) |
| `sample-forest.jpg` | [Chrissy](https://unsplash.com/@cthecreator) | [Unsplash 图片](https://images.unsplash.com/photo-1663998606502-5d8a320325ca) |

正式分发前应按实际用途核对来源、[Unsplash 许可](https://unsplash.com/license)及可能涉及的其他权利。

## Android 应用任务图标

`android-settings-api36.png` 为 Android API 36 目标设备中 `com.android.settings` 的原始应用图标（96×96），通过该设备的 PackageManager 读取，未按品牌重新绘制。用于工作台中一个已验证仍存在的设置后台任务示例：先启动设置、返回 HOME，再从真实任务列表确认。它是设备内容示例，不代表邻接的功能图标或品牌资产。

全部应用目录另引用以下 API 36 目标手机原始 PackageManager 图标（均为 96×96，保留原图内容）：

| 素材 | 目标应用包 | 示例名称 |
| --- | --- | --- |
| `com.android.chrome-api36.png` | `com.android.chrome` | Chrome |
| `com.google.android.calendar-api36.png` | `com.google.android.calendar` | 日历 |
| `com.google.android.contacts-api36.png` | `com.google.android.contacts` | 联系人 |
| `com.google.android.dialer-api36.png` | `com.google.android.dialer` | 电话 |
| `com.google.android.apps.messaging-api36.png` | `com.google.android.apps.messaging` | 信息 |
| `com.google.android.apps.photos-api36.png` | `com.google.android.apps.photos` | 相册 |
| `com.android.camera2-api36.png` | `com.android.camera2` | 相机 |

这些素材只表示目标手机的真实应用内容，不是主控功能图标；明暗外观沿用原始颜色，不按主控主题重绘。
