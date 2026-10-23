import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:scrcpy_connect/services/media_cache_lease.dart';

/// Local file playback is outside the packet-only remote media engine.
class VideoPreview extends StatelessWidget {
  const VideoPreview({
    super.key,
    required this.source,
    required this.fallback,
    this.cacheLease,
  });
  final String source;
  final VoidCallback fallback;
  final MediaCacheLease? cacheLease;

  @override
  Widget build(BuildContext context) => EmptyContent(
    icon: LucideIcons.video,
    title: '保存视频后打开',
    message: '此处不提供本地视频播放，可保存原文件后使用其他应用打开。',
    action: FilledButton(onPressed: fallback, child: const Text('保存原文件')),
  );
}
