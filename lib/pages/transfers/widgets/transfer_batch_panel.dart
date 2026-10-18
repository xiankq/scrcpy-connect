import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:design_system/design_system.dart';

class TransferBatchPanel extends HookWidget {
  const TransferBatchPanel({
    super.key,
    required this.controller,
    required this.batch,
    required this.refresh,
  });
  final AppController controller;
  final Json batch;
  final VoidCallback refresh;
  @override
  Widget build(BuildContext context) {
    final cancelling = useState(false);
    return ContentPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            batch['direction'] == 'push'
                ? '发送到设备'
                : batch['destinationScope'] == 'privateCache'
                ? '取回本机暂存'
                : '取回到本机',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '${batch['fileCount'] ?? 0} 个文件 · ${batch['directoryCount'] ?? 0} 个文件夹',
          ),
          Text(
            statusText(value(batch, 'status')),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            '已完成 ${batch['completed'] ?? 0} / ${batch['itemCount'] ?? 0} 项 · 失败 ${batch['failed'] ?? 0} · 跳过 ${batch['skipped'] ?? 0}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if ((num.tryParse('${batch['total']}') ?? 0) > 0)
            Text(
              '${bytes(batch['transferred'])} / ${bytes(batch['total'])}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (batch['canCancel'] == true)
            TextButton(
              onPressed: cancelling.value
                  ? null
                  : () async {
                      if (!await confirm(
                            context,
                            '取消本批未完成的传输？',
                            '仅取消这一批。已完成内容会保留，正在处理的内容以逐项结果为准。',
                            action: '取消传输',
                          ) ||
                          !context.mounted) {
                        return;
                      }
                      cancelling.value = true;
                      await perform(context, controller, 'transfers.cancel', {
                        'batchId': batch['batchId'],
                      });
                      if (context.mounted) {
                        cancelling.value = false;
                        refresh();
                      }
                    },
              child: Text(cancelling.value ? '正在取消本批…' : '取消本批传输'),
            ),
        ],
      ),
    );
  }
}
