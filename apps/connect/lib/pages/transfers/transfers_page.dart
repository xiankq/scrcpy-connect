import 'package:scrcpy_connect/router/app_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/pages/transfers/widgets/transfer_batch_panel.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/transfer_state.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class TransfersPage extends HookConsumerWidget {
  const TransfersPage({
    super.key,
    required this.controller,
    this.embedded = false,
  });
  final AppController controller;
  final bool embedded;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appEventRevision = ref.watch(
      appControllerProvider.select((state) => state.eventRevision),
    );
    final revision = useState(0);
    final content = CommandView(
      refreshKey: '$appEventRevision:${revision.value}',
      controller: controller,
      command: 'transfers.list',
      emptyTitle: '暂时无法读取传输任务',
      builder: (context, data, refresh) {
        final tasks = objects(data['transfers']);
        final batches = objects(data['batches']);
        if (tasks.isEmpty && batches.isEmpty) {
          return const EmptyContent(
            icon: LucideIcons.arrowUpDown,
            title: '暂无传输任务',
            message: '在设备的文件管理或相册中取回内容，或发送本机文件。任务会在这里显示实际进度与结果。',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => refresh(),
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(24, 12, 24, embedded ? 120 : 24),
            itemCount: batches.length + tasks.length,
            separatorBuilder: (_, _) => const SizedBox(height: 16),
            itemBuilder: (context, i) {
              if (i < batches.length) {
                return TransferBatchPanel(
                  controller: controller,
                  batch: batches[i],
                  refresh: refresh,
                );
              }
              final task = transferView(controller, tasks[i - batches.length]);
              return InkWell(
                borderRadius: BorderRadius.circular(26),
                onTap: () => TransferDetailsRoute(
                  taskId: value(task, 'id', value(task, 'transferId')),
                ).push<void>(context),
                child: ContentPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          FeatureIcon(
                            task['kind'] == 'directory'
                                ? LucideIcons.folder
                                : task['direction'] == 'push'
                                ? LucideIcons.upload
                                : LucideIcons.download,
                            color: ConnectTokens.amber,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  value(task, 'name', '文件传输'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                Text(
                                  '${value(task, 'sourceLabel', value(task, 'deviceName'))} → ${value(task, 'destinationLabel', value(task, 'destination'))}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const Icon(LucideIcons.chevronRight, size: 18),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        statusText(value(task, 'status')),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (num.tryParse('${task['totalBytes']}')
                          case final total? when total > 0) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value:
                              ((num.tryParse('${task['completedBytes']}') ??
                                          0) /
                                      total)
                                  .clamp(0, 1)
                                  .toDouble(),
                          minHeight: 3,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${bytes(task['completedBytes'])} / ${bytes(total)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (value(task, 'error').isNotEmpty)
                        StateNote(
                          value(task, 'error'),
                          icon: LucideIcons.circleAlert,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
    if (embedded) {
      return SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '传输',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                  ),
                  IconButton(
                    tooltip: '刷新任务',
                    onPressed: () => revision.value++,
                    icon: const Icon(LucideIcons.refreshCw),
                  ),
                ],
              ),
            ),
            Expanded(child: content),
          ],
        ),
      );
    }
    return PageFrame(
      title: '传输中心',
      actions: [
        IconButton(
          tooltip: '刷新任务',
          onPressed: () => revision.value++,
          icon: const Icon(LucideIcons.refreshCw),
        ),
      ],
      child: content,
    );
  }
}
