import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/files/models/file_transfer_snapshot.dart';
import 'package:scrcpy_connect/pages/files/widgets/file_kind_style.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';
import 'package:scrcpy_connect/widgets/file_transfer_labels.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:scrcpy_connect/widgets/list_row.dart';

/// 「本次文件」分组中的一项（Ardot T2 2:2920）：格式色块、文件名与路径，行尾为本项结果。
///
/// 失败或待核对的项改用通知色警示图形。
class TransferResultRow extends StatelessWidget implements GroupedRow {
  const TransferResultRow({super.key, required this.transfer, this.onOpen});

  final FileTransferSnapshot transfer;
  final VoidCallback? onOpen;

  @override
  double get separatorIndent =>
      listRowSeparatorIndent(DesignTokens.componentIconTileSize);

  @override
  Widget build(BuildContext context) {
    final issue = transferStatusHasIssue(transfer.status);
    final kind = FileKind.classify(name: transfer.name);
    final folder = transfer.kind == .directory;
    final path = transfer.direction == .push
        ? transfer.destination
        : transfer.source;
    return AppListRow(
      onTap: onOpen,
      chevron: onOpen != null,
      leading: ListIconBadge(
        icon: issue
            ? LucideIcons.circleAlert
            : folder
            ? folderKindIcon
            : fileKindIcon(kind),
        backgroundColor: issue
            ? FunctionTone.notification
            : folder
            ? folderKindColor
            : fileKindColor(kind, name: transfer.name),
      ),
      title: Text(transfer.name),
      subtitle: path.isEmpty ? null : Text(path),
      value: transferStatusDescription(transfer),
    );
  }
}
