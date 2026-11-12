import 'package:scrcpy_connect/core/devices/device_snapshot.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/files/file_catalog_entry.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/media_thumbnail.dart';
import 'package:scrcpy_connect/core/application/app_notifier.dart';

class GalleryMediaTile extends StatelessWidget {
  const GalleryMediaTile({
    super.key,
    required this.file,
    required this.controller,
    required this.device,
    required this.selected,
    required this.onTap,
  });

  final FileCatalogEntry file;
  final AppNotifier controller;
  final DeviceSnapshot device;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: file.name,
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignTokens.roundedMd),
        onTap: (file.canOpen && file.path?.isNotEmpty == true) ? onTap : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(DesignTokens.roundedMd),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (!(file.canOpen && file.path?.isNotEmpty == true))
                Container(
                  color: Theme.of(context).colorScheme.surface,
                  padding: const EdgeInsets.all(DesignTokens.spacingSm),
                  child: Center(
                    child: Text(
                      file.reason ?? '文件名无法解析为有效路径，暂时无法操作。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                )
              else
                MediaThumbnail(
                  name: file.name,
                  path: file.path!,
                  device: device,
                ),
              if (file.mime.startsWith('video'))
                const Positioned(
                  left: 8,
                  bottom: 8,
                  child: Icon(
                    LucideIcons.play,
                    color: Colors.white,
                    size: DesignTokens.componentIconActionSize,
                  ),
                ),
              if (selected)
                Container(
                  color: Colors.black38,
                  child: const Icon(
                    LucideIcons.circleCheck,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
