import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class OriginalFileHeader extends StatelessWidget {
  const OriginalFileHeader({super.key, required this.name, this.kind = 'file'});

  final String name;
  final String kind;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FeatureIcon(
        kind == 'directory' ? LucideIcons.folder : LucideIcons.file,
        color: ConnectTokens.amber,
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
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
