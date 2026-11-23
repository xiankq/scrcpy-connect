import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/form_controls.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/utils/formatters.dart';

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
    final theme = Theme.of(context);
    final name = transfer.name;
    final sourceLabel = (transfer.sourceLabel ?? '来源');
    final destinationLabel = (transfer.destinationLabel ?? '目标');
    final source = transfer.source;
    final destination = transfer.destination;
    final size = transfer.totalBytes ?? transfer.total;
    Future<void> resolve(FileTransferConflict policy) async {
      if (busy.value) return;
      busy.value = true;
      try {
        await onResolve(policy, all.value);
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: DesignTokens.spacingLg),
        ContentPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showTitle) ...[
                Text('同名文件', style: theme.textTheme.titleMedium),
                const SizedBox(height: DesignTokens.spacingXs),
              ],
              Text(name, style: theme.textTheme.titleLarge),
              const SizedBox(height: DesignTokens.spacingSm),
              Text(
                '${transfer.direction == .push ? '本次发送' : '本次取回'} · $sourceLabel'
                '${size == null ? '' : ' · ${bytes(size)}'}',
                style: theme.textTheme.bodyMedium,
              ),
              if (source.isNotEmpty)
                SelectableText(source, style: theme.textTheme.bodySmall),
              const SizedBox(height: DesignTokens.spacingSm),
              Text(
                '已有同名文件 · $destinationLabel',
                style: theme.textTheme.bodyMedium,
              ),
              if (destination.isNotEmpty)
                SelectableText(destination, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        const SizedBox(height: DesignTokens.spacingLg),
        FilledButton(
          style: pagePrimaryButtonStyle,
          onPressed: busy.value || !enabled ? null : () => resolve(.keepBoth),
          child: const Text('保留两份'),
        ),
        const SizedBox(height: DesignTokens.spacingXs),
        OutlinedButton(
          onPressed: busy.value || !enabled ? null : () => resolve(.skip),
          child: const Text('跳过此项'),
        ),
        const SizedBox(height: DesignTokens.spacingXs),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
            side: BorderSide(
              color: theme.colorScheme.error.withValues(alpha: 0.45),
            ),
          ),
          onPressed: busy.value || !enabled ? null : () => resolve(.replace),
          child: Text(transfer.direction == .push ? '替换手机上的文件' : '替换本机文件'),
        ),
        const SizedBox(height: DesignTokens.spacingMd),
        ContentPanel(
          padding: EdgeInsets.zero,
          child: CheckboxListTile(
            controlAffinity: ListTileControlAffinity.leading,
            value: all.value,
            onChanged: busy.value ? null : (next) => all.value = next ?? false,
            title: const Text('应用到本任务的后续冲突'),
          ),
        ),
      ],
    );
  }
}
