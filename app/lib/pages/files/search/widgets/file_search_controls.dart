import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/files/file_search.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/chips.dart';
import 'package:scrcpy_connect/widgets/choice_picker.dart';

const fileSearchFilters = {
  FileCatalogFilter.all: '全部类型',
  FileCatalogFilter.images: '图片',
  FileCatalogFilter.videos: '视频',
  FileCatalogFilter.audio: '音频',
  FileCatalogFilter.documents: '文档',
  FileCatalogFilter.archives: '压缩包',
  FileCatalogFilter.folders: '文件夹',
};

/// 范围 chip 之间的间距（Ardot F3 2:1400 条件行：间距 8）。
const _chipGap = DesignTokens.spacingSm;

/// 搜索范围：两个单选 chip，选中项为 primary 底。
class FileSearchScopeSelector extends StatelessWidget {
  const FileSearchScopeSelector({
    super.key,
    required this.entireStorage,
    required this.onChanged,
  });

  final bool entireStorage;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: _chipGap,
    runSpacing: _chipGap,
    children: [
      for (final entire in [false, true])
        AppChip(
          label: entire ? '手机内部存储' : '当前目录及其子目录',
          selected: entireStorage == entire,
          onPressed: () => onChanged(entire),
        ),
    ],
  );
}

/// 文件类型：带下拉的 chip，点按打开单选弹层。
class FileSearchTypeField extends StatelessWidget {
  const FileSearchTypeField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final FileCatalogFilter value;
  final ValueChanged<FileCatalogFilter> onChanged;

  @override
  Widget build(BuildContext context) => AppChip(
    key: const ValueKey('file-search-type-field'),
    label: fileSearchFilters[value]!,
    selected: false,
    dropdown: true,
    onPressed: () async {
      final next = await showChoicePicker<FileCatalogFilter>(
        context: context,
        title: '选择文件类型',
        options: fileSearchFilters.keys,
        label: (option) => fileSearchFilters[option]!,
        isSelected: (option) => option == value,
      );
      if (next != null && context.mounted) onChanged(next);
    },
  );
}
