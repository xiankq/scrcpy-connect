import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';

class FileEntrySliver extends StatelessWidget {
  const FileEntrySliver({
    super.key,
    required this.entries,
    required this.viewMode,
    required this.builder,
  });

  final List<FileCatalogEntry> entries;
  final FileViewMode viewMode;
  final Widget Function(FileCatalogEntry entry, bool grid) builder;

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

/// 手机参考布局为四列：370 像素减去三个 12 像素间隔，每项 83.5 像素；宽窗口增加列数，窄手机不少于三列。
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
