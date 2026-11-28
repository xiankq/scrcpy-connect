import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/content/media_thumbnail.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';
import 'package:scrcpy_connect/widgets/form_controls.dart';

/// 视频标签距缩略格边 6，内距左右 6、上下 2（Ardot 相册缩略格 37:2162「时长」）。
const _tagInset = 6.0;
const _tagPadding = EdgeInsets.symmetric(
  horizontal: 6.0,
  vertical: DesignTokens.spacingXxs,
);

/// 相册缩略格（Ardot 37:2162）：圆角 0，`block` 占位；视频右下角叠 `media-scrim`
/// 底的标签；选择态在缩略图正中叠放选择标记（Ardot 选择标记 · 叠放 44:5）。
class GalleryMediaTile extends StatelessWidget {
  const GalleryMediaTile({
    super.key,
    required this.file,
    required this.device,
    required this.selected,
    required this.onTap,
    this.selectionActive = false,
  });

  final FileCatalogEntry file;
  final DeviceSnapshot device;
  final bool selected;
  final VoidCallback onTap;

  /// 选择态下所有可用缩略格都显示选择标记。
  final bool selectionActive;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final available = file.canOpen && file.path?.isNotEmpty == true;
    return Semantics(
      label: file.name,
      selected: selected,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: available ? onTap : null,
        child: ColoredBox(
          color: colors.block,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (!available)
                Padding(
                  padding: const EdgeInsets.all(DesignTokens.spacingSm),
                  child: Center(
                    child: Text(
                      fileUnavailableReason(file),
                      textAlign: TextAlign.center,
                      style: type.footnote.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                )
              else
                MediaThumbnail(
                  name: file.name,
                  path: file.path!,
                  device: device,
                ),
              if (available && file.mime.startsWith('video/'))
                PositionedDirectional(
                  end: _tagInset,
                  bottom: _tagInset,
                  child: DecoratedBox(
                    decoration: const ShapeDecoration(
                      color: DesignTokens.colorMediaScrim,
                      shape: StadiumBorder(),
                    ),
                    child: Padding(
                      padding: _tagPadding,
                      child: Text(
                        '视频',
                        style: type.caption.copyWith(
                          color: DesignTokens.colorOnMedia,
                        ),
                      ),
                    ),
                  ),
                ),
              if (selectionActive && available)
                Center(child: SelectionMark(selected: selected, overlay: true)),
            ],
          ),
        ),
      ),
    );
  }
}
