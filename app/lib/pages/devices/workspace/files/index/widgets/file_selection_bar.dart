import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class FileSelectionBar extends StatelessWidget {
  const FileSelectionBar({
    super.key,
    required this.count,
    required this.onRename,
    required this.onRetrieve,
    required this.onDelete,
    required this.onClear,
  });

  final int count;
  final VoidCallback? onRename;
  final VoidCallback? onRetrieve;
  final VoidCallback? onDelete;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      DesignTokens.spacingMd,
      DesignTokens.spacingXs,
      DesignTokens.spacingMd,
      DesignTokens.spacingSm,
    ),
    child: Row(
      children: [
        Expanded(child: Text('已选择 $count 项')),
        GlassToolbarGroup(
          children: [
            GlassActionIcon(
              tooltip: '重命名所选',
              onPressed: onRename,
              icon: const Icon(LucideIcons.pencil),
            ),
            GlassActionIcon(
              tooltip: '取回所选原文件',
              onPressed: onRetrieve,
              icon: const Icon(LucideIcons.download),
            ),
            GlassActionIcon(
              tooltip: '删除所选',
              onPressed: onDelete,
              icon: const Icon(LucideIcons.trash2, color: ConnectTokens.danger),
            ),
            GlassActionIcon(
              tooltip: '取消选择',
              onPressed: onClear,
              icon: const Icon(LucideIcons.x),
            ),
          ],
        ),
      ],
    ),
  );
}
