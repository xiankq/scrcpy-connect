import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/media_thumbnail.dart';
import 'package:scrcpy_connect/services/files/file_access.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';

class GalleryMediaTile extends StatelessWidget {
  const GalleryMediaTile({
    super.key,
    required this.file,
    required this.controller,
    required this.device,
    required this.selected,
    required this.onTap,
  });

  final Json file;
  final AppController controller;
  final Json device;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: value(file, 'name'),
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignTokens.roundedMd),
        onTap: fileCanOpen(file) ? onTap : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(DesignTokens.roundedMd),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (!fileCanOpen(file))
                Container(
                  color: Theme.of(context).colorScheme.surface,
                  padding: const EdgeInsets.all(DesignTokens.spacingSm),
                  child: Center(
                    child: Text(
                      fileUnavailableReason(file),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                )
              else
                MediaThumbnail(
                  file: file,
                  controller: controller,
                  device: device,
                ),
              if (value(file, 'mime').startsWith('video'))
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
