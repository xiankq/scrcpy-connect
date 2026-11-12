import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/files/file_transfer_snapshot.dart';
import 'package:scrcpy_connect/core/files/transfer_history_notifier.dart';
import 'package:scrcpy_connect/core/application/app_dependencies_provider.dart';
import 'package:scrcpy_connect/widgets/async_content.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/pages/transfers/index/widgets/transfer_history_row.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/core/application/app_notifier.dart';
import 'package:scrcpy_connect/widgets/file_transfer_labels.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/recovery_status.dart';

class TransfersPage extends ConsumerWidget {
  const TransfersPage({
    super.key,
    required this.controller,
    this.embedded = false,
  });
  final AppNotifier controller;
  final bool embedded;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(transferHistoryProvider);
    final source = ref.watch(
      appDependenciesProvider.select((value) => value.fileTransfers),
    );
    Future<void> refresh() =>
        ref.read(transferHistoryProvider.notifier).refresh();
    return PageFrame(
      root: embedded,
      title: '文件传输',
      actions: [
        GlassActionIcon(
          tooltip: '刷新任务',
          onPressed: refresh,
          icon: const Icon(LucideIcons.refreshCw),
        ),
      ],
      child: AsyncContent<FileTransferCollection>(
        loading: query.loading,
        data: query.data,
        error: query.error,
        onRefresh: refresh,
        emptyTitle: '暂时无法读取传输任务',
        builder: (context, data) {
          final rows = transferHistoryRows(controller, data);
          if (rows.isEmpty) {
            return const PageChromeBody(
              child: EmptyContent(
                icon: LucideIcons.arrowUpDown,
                title: '暂无传输',
                message: '发送或接收文件后，可在这里查看进度和结果。',
              ),
            );
          }
          final active = rows
              .where((row) => transferHistoryActive(row.task))
              .toList();
          final recent = rows
              .where((row) => !transferHistoryActive(row.task))
              .toList();
          final entries =
              <({String? group, int? count, TransferHistoryEntry? row})>[
                if (active.isNotEmpty)
                  (group: '进行中', count: active.length, row: null),
                for (final row in active) (group: null, count: null, row: row),
                if (recent.isNotEmpty)
                  (group: '最近', count: recent.length, row: null),
                for (final row in recent) (group: null, count: null, row: row),
              ];
          return RefreshIndicator(
            onRefresh: () async => refresh(),
            child: ListView.builder(
              padding:
                  const EdgeInsets.fromLTRB(
                    DesignTokens.spacingMd,
                    DesignTokens.spacingSm,
                    DesignTokens.spacingMd,
                    DesignTokens.spacingLg,
                  ) +
                  PageChromePadding.of(context),
              itemCount: entries.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return const RecoveryStatus(padding: EdgeInsets.zero);
                }
                final entry = entries[index - 1];
                if (entry.group != null) {
                  return _TransferGroupHeader(
                    title: entry.group!,
                    count: entry.count!,
                  );
                }
                final row = entry.row!;
                return TransferHistoryRow(
                  key: ValueKey((source, row.id)),
                  controller: controller,
                  row: row,
                  refresh: refresh,
                  onOpen: () => _open(context, row),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _open(BuildContext context, TransferHistoryEntry row) {
    if (row.members.isEmpty) return;
    final representative =
        row.members
            .where((member) => member.parentId?.isNotEmpty != true)
            .firstOrNull ??
        row.members.first;
    TransferDetailsRoute(taskId: representative.id).push<void>(context);
  }
}

class _TransferGroupHeader extends StatelessWidget {
  const _TransferGroupHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      0,
      DesignTokens.spacingSm,
      0,
      DesignTokens.spacingXs,
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        Text('$count 项', style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

/// 每次选择在列表出现一次，批次子项放在详情中。
List<TransferHistoryEntry> transferHistoryRows(
  AppNotifier controller,
  FileTransferCollection data,
) {
  final groups = <String, List<FileTransferSnapshot>>{};
  for (final raw in data.transfers) {
    final task = transferView(controller.snapshot().devices, raw);
    final batch = task.batchId;
    groups
        .putIfAbsent(
          batch == null || batch.isEmpty ? 'task:${task.id}' : 'batch:$batch',
          () => [],
        )
        .add(task);
  }
  final summaries = {for (final batch in data.batches) batch.batchId: batch};
  return [
    for (final group in groups.entries)
      (() {
        final members = group.value;
        final roots = members
            .where((task) => task.parentId?.isNotEmpty != true)
            .toList();
        final first = roots.isEmpty ? members.first : roots.first;
        final batch = first.batchId;
        final summary = summaries[batch];
        final multiple = members.length > 1;
        var displayed = first;
        if (multiple && summary != null) {
          displayed = displayed.copyWith(
            deviceId: summary.deviceId,
            direction: summary.direction,
            destinationScope: summary.destinationScope,
            status: summary.status,
            itemCount: summary.itemCount,
            canCancel: summary.canCancel,
          );
        }
        displayed = displayed.copyWith(
          name:
              '${first.name}${roots.length > 1
                  ? ' 等 ${members.length} 项'
                  : multiple
                  ? ' · ${members.length} 项'
                  : ''}',
          completedBytes: multiple
              ? summary?.transferred ?? 0
              : first.completedBytes,
          totalBytes: multiple ? summary?.total : first.totalBytes,
        );
        return (
          id: group.key,
          task: displayed,
          members: members,
          batchId: batch?.isNotEmpty == true ? batch : null,
        );
      })(),
  ];
}
