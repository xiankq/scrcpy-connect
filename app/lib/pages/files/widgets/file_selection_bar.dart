import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';
import 'package:scrcpy_connect/widgets/glass/glass_action_bar.dart';
import 'package:scrcpy_connect/widgets/glass/glass_menu.dart';

class FileSelectionBar extends StatelessWidget {
  const FileSelectionBar({
    super.key,
    required this.menuController,
    required this.directory,
    required this.onRetrieve,
    required this.retrieveReason,
    required this.onDelete,
    required this.deleteReason,
    required this.onRename,
    required this.viewMode,
    required this.onToggleView,
  });

  final MenuController menuController;
  final String directory;
  final VoidCallback? onRetrieve, onDelete, onRename;
  final String retrieveReason, deleteReason;
  final FileViewMode viewMode;
  final VoidCallback onToggleView;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: DesignTokens.spacingMd),
          child: Text(
            '当前目录 · $directory',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: type.captionEmphasis.copyWith(color: colors.textSecondary),
          ),
        ),
        GlassActionBar(
          actions: [
            GlassActionBarButton(
              label: '取回原文件',
              icon: const Icon(AppIcons.download),
              onPressed: onRetrieve,
              tooltip: onRetrieve == null ? retrieveReason : null,
            ),
            GlassActionBarButton(
              label: '删除',
              icon: const Icon(AppIcons.delete),
              onPressed: onDelete,
              tooltip: onDelete == null ? deleteReason : null,
            ),
            GlassMenuButton(
              controller: menuController,
              label: '更多',
              tooltip: '更多',
              icon: const Icon(AppIcons.more),
              actions: [
                GlassMenuAction(
                  label: '重命名',
                  icon: const Icon(LucideIcons.squarePen),
                  onPressed: onRename,
                ),
                GlassMenuAction(
                  label: viewMode == FileViewMode.grid ? '切换为列表' : '切换为宫格',
                  icon: Icon(
                    viewMode == FileViewMode.grid
                        ? LucideIcons.list
                        : LucideIcons.layoutGrid,
                  ),
                  onPressed: onToggleView,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
