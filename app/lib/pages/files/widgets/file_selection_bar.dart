import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';
import 'package:scrcpy_connect/widgets/glass/glass_action_bar.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';

class FileSelectionBar extends StatelessWidget {
  const FileSelectionBar({
    super.key,
    required this.menuController,
    required this.onRetrieve,
    required this.retrieveReason,
    required this.onDelete,
    required this.deleteReason,
    required this.onRename,
    required this.viewMode,
    required this.onToggleView,
  });

  final MenuController menuController;
  final VoidCallback? onRetrieve, onDelete, onRename;
  final String retrieveReason, deleteReason;
  final FileViewMode viewMode;
  final VoidCallback onToggleView;

  @override
  Widget build(BuildContext context) => GlassActionBar(
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
      MenuAnchor(
        controller: menuController,
        consumeOutsideTap: true,
        alignmentOffset: const Offset(
          0,
          DesignTokens.componentFileActionBarPadding + DesignTokens.spacingXs,
        ),
        style: const MenuStyle(
          alignment: Alignment.bottomCenter,
          backgroundColor: WidgetStatePropertyAll(
            DesignTokens.colorTransparent,
          ),
          surfaceTintColor: WidgetStatePropertyAll(
            DesignTokens.colorTransparent,
          ),
          elevation: WidgetStatePropertyAll(0),
          padding: WidgetStatePropertyAll(EdgeInsets.zero),
        ),
        menuChildren: [
          GlassSurfaceGroup.isolated(
            child: Glass(
              padding: const EdgeInsets.symmetric(
                vertical: DesignTokens.spacingXs,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MenuItemButton(
                    leadingIcon: const Icon(LucideIcons.squarePen),
                    onPressed: onRename,
                    child: const Text('重命名'),
                  ),
                  MenuItemButton(
                    leadingIcon: Icon(
                      viewMode == FileViewMode.grid
                          ? LucideIcons.list
                          : LucideIcons.layoutGrid,
                    ),
                    onPressed: onToggleView,
                    child: Text(
                      viewMode == FileViewMode.grid ? '切换为列表' : '切换为宫格',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        builder: (context, menu, child) => GlassActionBarButton(
          label: '更多',
          icon: const Icon(AppIcons.more),
          onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        ),
      ),
    ],
  );
}
