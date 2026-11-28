import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';
import 'package:scrcpy_connect/widgets/grouped_list_segment.dart';
import 'package:scrcpy_connect/widgets/list_row.dart';

/// 宫格项之间的间距（Ardot F1 2:1321 目录宫格：行列间距 8）。
const _gridGap = DesignTokens.spacingSm;

/// 宫格项的最小宽度：手机参考宽度 370 排四列（Ardot 宫格缩略项 37:2067 宽 86）。
const _minimumGridTile = 80.0;

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
      final indices = {
        for (final (index, entry) in entries.indexed)
          if (entry.path case final path?) ValueKey(path): index,
      };
      return SliverList.builder(
        itemCount: entries.length,
        findChildIndexCallback: (key) => indices[key],
        itemBuilder: (context, index) {
          final row = builder(entries[index], false);
          return GroupedListSegment.at(
            key: row.key,
            index: index,
            count: entries.length,
            separatorIndent: tileRowSeparatorIndent,
            child: row,
          );
        },
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
            bottom: rowIndex == rowCount - 1 ? 0 : _gridGap,
          ),
          child: Row(
            key: ValueKey(('file-grid-row', rowIndex)),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var column = 0; column < columns; column++) ...[
                if (column > 0) const SizedBox(width: _gridGap),
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

/// 手机参考布局为四列；宽窗口增加列数，窄手机不少于三列。
int fileGridColumnCount(BuildContext context) {
  final pageWidth = MediaQuery.sizeOf(context).width
      .clamp(0.0, DesignTokens.componentPageMaxWidth);
  final available = (pageWidth - DesignTokens.componentPagePadding * 2).clamp(
    1.0,
    double.infinity,
  );
  return ((available + _gridGap) / (_minimumGridTile + _gridGap)).floor().clamp(
    3,
    6,
  );
}
