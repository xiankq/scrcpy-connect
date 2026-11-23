import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content/media_thumbnail.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';

class GalleryMediaTile extends StatelessWidget {
  const GalleryMediaTile({
    super.key,
    required this.file,
    required this.device,
    required this.selected,
    required this.onTap,
  });

  final FileCatalogEntry file;
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
                      fileUnavailableReason(file),
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
              if (file.canOpen &&
                  file.path?.isNotEmpty == true &&
                  file.mime.startsWith('video/')) ...[
                const Center(
                  child: Icon(
                    LucideIcons.play,
                    color: DesignTokens.colorWhite,
                    size: DesignTokens.componentIconActionSize,
                    shadows: [Shadow(blurRadius: DesignTokens.spacingXs)],
                  ),
                ),
                Positioned(
                  left: DesignTokens.spacingXs,
                  bottom: DesignTokens.spacingXs,
                  child: Text(
                    '视频',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: DesignTokens.colorWhite,
                      shadows: const [
                        Shadow(blurRadius: DesignTokens.spacingXs),
                      ],
                    ),
                  ),
                ),
              ],
              if (selected)
                Container(
                  color: DesignTokens
                      .componentMediaThumbnailSelectionBackgroundColor,
                  child: const Icon(
                    LucideIcons.circleCheck,
                    color: DesignTokens.colorWhite,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
