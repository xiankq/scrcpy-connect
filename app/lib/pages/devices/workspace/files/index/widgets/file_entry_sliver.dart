import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/file_browser_model.dart';

class FileEntrySliver extends StatelessWidget {
  const FileEntrySliver({
    super.key,
    required this.entries,
    required this.viewMode,
    required this.builder,
  });

  final List<Json> entries;
  final FileViewMode viewMode;
  final Widget Function(Json entry, bool grid) builder;

  @override
  Widget build(BuildContext context) {
    if (viewMode == FileViewMode.list) {
      return SliverList.builder(
        itemCount: entries.length,
        itemBuilder: (context, index) => builder(entries[index], false),
      );
    }
    final columns = fileGridColumnCount(context);
    final rowCount = (entries.length + columns - 1) ~/ columns;
    return SliverList.builder(
      itemCount: rowCount,
      itemBuilder: (context, rowIndex) {
        final start = rowIndex * columns;
        final end = (start + columns).clamp(0, entries.length);
        return Padding(
          padding: EdgeInsets.only(
            bottom: rowIndex == rowCount - 1
                ? DesignTokens.spacingZero
                : DesignTokens.spacingSm,
          ),
          child: Row(
            key: ValueKey(('file-grid-row', rowIndex)),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var column = 0; column < columns; column++) ...[
                if (column > 0) const SizedBox(width: DesignTokens.spacingSm),
                Expanded(
                  child: start + column < end
                      ? builder(entries[start + column], true)
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Phone reference width uses four columns: 370px of content minus three
/// 12px gaps leaves 83.5px per tile. Wider host windows may add columns, but a
/// narrow phone never drops below three readable columns.
int fileGridColumnCount(BuildContext context) {
  final pageWidth = MediaQuery.sizeOf(context).width
      .clamp(0.0, DesignTokens.componentPageContentMaxWidth);
  final available = (pageWidth - DesignTokens.spacingMd * 2).clamp(
    1.0,
    double.infinity,
  );
  const minimumTile = 80.0;
  return ((available + DesignTokens.spacingSm) /
          (minimumTile + DesignTokens.spacingSm))
      .floor()
      .clamp(3, 6);
}
