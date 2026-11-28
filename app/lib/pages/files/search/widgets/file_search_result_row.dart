import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart';
import 'package:scrcpy_connect/pages/files/widgets/file_entry_tiles.dart';
import 'package:scrcpy_connect/pages/files/widgets/file_kind_style.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:scrcpy_connect/widgets/list_row.dart';

/// 搜索结果行（Ardot F3 2:1400）：文件格式色块、名称、完整父目录，行尾箭头。
class FileSearchResultRow extends StatelessWidget {
  const FileSearchResultRow({
    super.key,
    required this.file,
    required this.folder,
    required this.onTap,
    required this.unavailableReason,
  });

  final FileCatalogEntry file;
  final bool folder;
  final VoidCallback? onTap;
  final String? unavailableReason;

  @override
  Widget build(BuildContext context) {
    final path = file.path ?? '';
    final reason = unavailableReason;
    final location = fileParentDirectoryLabel(path);
    final kind = FileKind.classify(name: file.name, mime: file.mime);
    return Semantics(
      button: onTap != null,
      child: Tooltip(
        message: path,
        child: AppListRow(
          leading: ListIconBadge(
            icon: folder ? folderKindIcon : fileKindIcon(kind),
            backgroundColor: folder
                ? folderKindColor
                : fileKindColor(kind, name: file.name, mime: file.mime),
          ),
          title: Text(file.name),
          titleMaxLines: 2,
          subtitle: reason != null
              ? FileUnavailableNote(reason)
              : location.isEmpty
              ? null
              : Text(location),
          chevron: true,
          onTap: onTap,
        ),
      ),
    );
  }
}

String fileParentDirectoryLabel(String path) {
  final separator = path.lastIndexOf('/');
  final parent = separator <= 0 ? '/' : path.substring(0, separator);
  if (parent == '/') return '设备根目录';
  final crumbs = fileBreadcrumbs(parent);
  if (parent == '/sdcard') return '手机存储';
  if (parent.startsWith('/sdcard/')) {
    return ['手机存储', ...crumbs.skip(1).map((crumb) => crumb.label)].join(' / ');
  }
  return crumbs.map((crumb) => crumb.label).join(' / ');
}
