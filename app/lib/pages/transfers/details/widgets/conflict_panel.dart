import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:design_system/design_system.dart';

class ConflictPanel extends HookWidget {
  const ConflictPanel({
    super.key,
    required this.transfer,
    required this.onResolve,
  });
  final Json transfer;
  final Future<void> Function(String policy, bool all) onResolve;

  @override
  Widget build(BuildContext context) {
    final all = useState(false);
    final busy = useState(false);
    final theme = Theme.of(context);
    final name = value(transfer, 'name', '同名文件');
    final sourceLabel = value(transfer, 'sourceLabel', '来源');
    final destinationLabel = value(transfer, 'destinationLabel', '目标');
    final source = value(transfer, 'source');
    final destination = value(transfer, 'destination');
    Future<void> resolve(String policy) async {
      if (busy.value) return;
      busy.value = true;
      try {
        await onResolve(policy, all.value);
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return ContentPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: DesignTokens.spacingXs),
          Text(
            '来源 · $sourceLabel${source.isEmpty ? '' : '\n$source'}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: DesignTokens.spacingSm),
          Text(
            '目标 · $destinationLabel${destination.isEmpty ? '' : '\n$destination'}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: DesignTokens.spacingSm),
          Text('替换将覆盖目标中的同名文件。', style: theme.textTheme.bodySmall),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: all.value,
            onChanged: busy.value ? null : (next) => all.value = next ?? false,
            title: const Text('应用到本任务的后续冲突'),
          ),
          const SizedBox(height: DesignTokens.spacingXs),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: busy.value ? null : () => resolve('keepBoth'),
              child: const Text('保留两份'),
            ),
          ),
          const SizedBox(height: DesignTokens.spacingXs),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(
                  color: theme.colorScheme.error.withValues(alpha: 0.45),
                ),
              ),
              onPressed: busy.value ? null : () => resolve('replace'),
              child: const Text('替换目标文件'),
            ),
          ),
          const SizedBox(height: DesignTokens.spacingXs),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                backgroundColor: theme.colorScheme.surfaceContainerHigh,
                side: BorderSide.none,
              ),
              onPressed: busy.value ? null : () => resolve('skip'),
              child: const Text('跳过此项'),
            ),
          ),
        ],
      ),
    );
  }
}
