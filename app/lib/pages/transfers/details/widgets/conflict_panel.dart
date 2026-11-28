import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/banner.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/form_controls.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/list_row.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/utils/formatters.dart';

/// 同名文件处理（Ardot T5 2:1698 / 2:1828）：警告横幅、两个版本、处理方式单选与「继续」。
///
/// 替换在提交前再次确认，因为原文件无法恢复。
class ConflictPanel extends HookWidget {
  const ConflictPanel({
    super.key,
    required this.transfer,
    required this.onResolve,
    this.enabled = true,
    this.showTitle = true,
  });
  final FileTransferSnapshot transfer;
  final bool enabled;
  final bool showTitle;
  final Future<void> Function(FileTransferConflict policy, bool all) onResolve;

  @override
  Widget build(BuildContext context) {
    final all = useState(false);
    final busy = useState(false);
    final choice = useState(FileTransferConflict.keepBoth);
    final name = transfer.name;
    final push = transfer.direction == .push;
    final sourceLabel = (transfer.sourceLabel ?? '来源');
    final destinationLabel = (transfer.destinationLabel ?? '目标');
    final source = transfer.source;
    final destination = transfer.destination;
    final size = transfer.totalBytes ?? transfer.total;
    final replaceLabel = push ? '替换手机上的文件' : '替换本机文件';
    final active = !busy.value && enabled;

    Future<void> resolve() async {
      if (busy.value) return;
      final policy = choice.value;
      if (policy == .replace &&
          (!await confirm(
                context,
                '$replaceLabel？',
                '$destinationLabel 上的「$name」会被此次文件替换，原文件无法恢复。',
                action: '替换',
                danger: true,
              ) ||
              !context.mounted)) {
        return;
      }
      busy.value = true;
      try {
        await onResolve(policy, all.value);
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    Widget option(FileTransferConflict value, String title, String? detail) =>
        Semantics(
          checked: choice.value == value,
          inMutuallyExclusiveGroup: true,
          child: AppListRow(
            enabled: active,
            selected: choice.value == value,
            onTap: () => choice.value = value,
            title: Text(title),
            subtitle: detail == null ? null : Text(detail),
            trailing: SelectionMark(
              selected: choice.value == value,
              enabled: active,
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTitle) const SectionTitle('同名文件'),
        if (!showTitle) const SizedBox(height: DesignTokens.spacingSm),
        AppBanner(
          tone: BannerTone.warning,
          message: '已有同名文件 · $destinationLabel「$name」',
        ),
        const SectionTitle('两个版本'),
        SettingsGroup(
          children: [
            AppListRow(
              title: Text(
                '${push ? '本次发送' : '本次取回'}'
                '${size == null ? '' : ' · ${bytes(size)}'}',
              ),
              subtitle: Text(
                source.isEmpty ? sourceLabel : '$sourceLabel · $source',
              ),
              subtitleMaxLines: 3,
            ),
            AppListRow(
              title: Text('已有同名文件 · $destinationLabel'),
              subtitle: destination.isEmpty ? null : Text(destination),
              subtitleMaxLines: 3,
            ),
          ],
        ),
        const SectionTitle('处理方式'),
        SettingsGroup(
          children: [
            option(.keepBoth, '保留两份', null),
            option(.skip, '跳过此项', push ? '保留手机上的文件，不发送此项' : '保留本机文件，不取回此项'),
            option(.replace, replaceLabel, '需要再次确认，原文件无法恢复'),
            ConnectSwitchRow(
              title: const Text('应用到本任务的后续冲突'),
              value: all.value,
              onChanged: busy.value ? null : (next) => all.value = next,
            ),
          ],
        ),
        const SizedBox(height: DesignTokens.spacingXxl),
        AppButton(
          label: '继续',
          role: AppButtonRole.primary,
          expand: true,
          busy: busy.value,
          onPressed: active ? resolve : null,
        ),
      ],
    );
  }
}
