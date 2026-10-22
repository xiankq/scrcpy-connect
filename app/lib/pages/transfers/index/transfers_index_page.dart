import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/pages/transfers/index/widgets/transfer_history_row.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/transfer_state.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/recovery_status.dart';

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
    final events = ref.watch(
      appControllerProvider.select((s) => s.eventRevision),
    );
    final revision = useState(0);
    return PageFrame(
      root: embedded,
      title: '文件传输',
      actions: [
        GlassActionIcon(
          tooltip: '刷新任务',
          onPressed: () => revision.value++,
          icon: const Icon(LucideIcons.refreshCw),
        ),
      ],
      child: CommandView(
        refreshKey: '$events:${revision.value}',
        controller: controller,
        command: 'transfers.list',
        emptyTitle: '暂时无法读取传输任务',
        builder: (context, data, refresh) {
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
          final active = rows.where(transferHistoryActive).toList();
          final recent = rows
              .where((row) => !transferHistoryActive(row))
              .toList();
          final entries = <({String? group, int? count, Json? row})>[
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
                  key: ValueKey(row['historyId']),
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

  void _open(BuildContext context, Json row) {
    final members = objects(row['members']);
    if (members.isEmpty) return;
    final roots = members
        .where((member) => value(member, 'parentId').isEmpty)
        .toList();
    final representative = roots.isEmpty ? members.first : roots.first;
    TransferDetailsRoute(taskId: value(representative, 'id'))
        .push<void>(context);
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

/// Each selection appears once; batch children live in its details.
List<Json> transferHistoryRows(AppController controller, Json data) {
  final groups = <String, List<Json>>{};
  for (final raw in objects(data['transfers'])) {
    final task = transferView(controller, raw);
    final batch = value(task, 'batchId');
    groups
        .putIfAbsent(
          batch.isEmpty ? 'task:${task['id']}' : 'batch:$batch',
          () => [],
        )
        .add(task);
  }
  final summaries = {
    for (final b in objects(data['batches'])) value(b, 'batchId'): b,
  };
  return [
    for (final group in groups.entries)
      (() {
        final members = group.value;
        final roots = members
            .where((t) => value(t, 'parentId').isEmpty)
            .toList();
        final first = roots.isEmpty ? members.first : roots.first;
        final batch = value(first, 'batchId');
        final summary = summaries[batch];
        final multiple = members.length > 1;
        return <String, dynamic>{
          ...first,
          if (multiple && summary != null) ...summary,
          'historyId': group.key,
          'members': members,
          'name':
              '${value(first, 'name', '文件传输')}'
              '${roots.length > 1
                  ? ' 等 ${members.length} 项'
                  : multiple
                  ? ' · ${members.length} 项'
                  : ''}',
          if (multiple) 'completedBytes': summary?['transferred'] ?? 0,
          if (multiple) 'totalBytes': summary?['total'],
          'removeParams': batch.isEmpty
              ? {'transferId': first['id']}
              : {'batchId': batch},
        };
      })(),
  ];
}
