import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:design_system/design_system.dart';

class ConflictPanel extends HookWidget {
  const ConflictPanel({super.key, required this.onResolve});
  final Future<void> Function(String policy, bool all) onResolve;
  @override
  Widget build(BuildContext context) {
    final all = useState(false);
    final busy = useState(false);
    return ContentPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('目标中已有同名内容', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('选择如何处理此次冲突。替换可能覆盖目标中已有的内容。'),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: all.value,
            onChanged: busy.value ? null : (v) => all.value = v ?? false,
            title: const Text('应用到当前任务的后续冲突'),
          ),
          for (final option in const [
            ('keepBoth', '保留两份'),
            ('replace', '替换目标内容'),
            ('skip', '跳过此项'),
          ])
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: busy.value
                    ? null
                    : () async {
                        busy.value = true;
                        await onResolve(option.$1, all.value);
                        if (context.mounted) busy.value = false;
                      },
                child: Text(option.$2),
              ),
            ),
        ],
      ),
    );
  }
}
