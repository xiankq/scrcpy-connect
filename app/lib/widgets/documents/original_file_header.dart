import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class OriginalFileHeader extends StatelessWidget {
  const OriginalFileHeader({super.key, required this.name, this.kind = 'file'});

  final String name;
  final String kind;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      FeatureIcon(
        kind == 'directory' ? LucideIcons.folder : LucideIcons.file,
        // 文件格式色：文件夹 accent-amber，文档 accent-indigo（design.md「功能色」）。
        color: kind == 'directory'
            ? DesignTokens.colorAccentAmber
            : DesignTokens.colorAccentIndigo,
      ),
      const SizedBox(width: DesignTokens.spacingMd),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Tooltip(
              message: name,
              child: Text(
                name,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.of(context).headline,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
