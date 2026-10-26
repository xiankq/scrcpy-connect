import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/models/file_browser.dart';

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
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: _action(
          context,
          '取回原文件',
          LucideIcons.download,
          onRetrieve,
          retrieveReason,
        ),
      ),
      Expanded(
        child: _action(
          context,
          '删除',
          LucideIcons.trash2,
          onDelete,
          deleteReason,
        ),
      ),
      Expanded(
        child: MenuAnchor(
          controller: menuController,
          consumeOutsideTap: true,
          style: const MenuStyle(
            alignment: Alignment.bottomCenter,
            backgroundColor: WidgetStatePropertyAll(Colors.transparent),
            surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
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
                      leadingIcon: const Icon(LucideIcons.pencil),
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
          builder: (context, menu, child) => _action(
            context,
            '更多',
            LucideIcons.ellipsis,
            () => menu.isOpen ? menu.close() : menu.open(),
            '',
          ),
        ),
      ),
    ],
  );

  Widget _action(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback? onPressed,
    String reason,
  ) => GlassTooltip(
    message: onPressed == null ? reason : label,
    child: TextButton(
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        minimumSize: const Size(
          DesignTokens.componentIconButtonSize,
          DesignTokens.componentNavigationHeight,
        ),
      ),
      onPressed: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: DesignTokens.componentIconSize),
          const SizedBox(height: DesignTokens.spacingXxs),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
