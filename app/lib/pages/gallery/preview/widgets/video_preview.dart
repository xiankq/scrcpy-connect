import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
import 'package:scrcpy_connect/widgets/content.dart';

/// 本机文件播放不属于只接收原始压缩包的远控媒体引擎。
class VideoPreview extends StatelessWidget {
  const VideoPreview({super.key, required this.fallback});
  final VoidCallback fallback;

  @override
  Widget build(BuildContext context) => EmptyContent(
    icon: LucideIcons.video,
    title: '保存视频后打开',
    message: '此处不提供本地视频播放，可保存原文件后使用其他应用打开。',
    action: AppButton(
      label: '保存原文件',
      role: AppButtonRole.primary,
      onPressed: fallback,
    ),
  );
}
