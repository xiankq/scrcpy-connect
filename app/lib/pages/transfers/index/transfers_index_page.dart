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
      title: '传输',
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
              itemCount: rows.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return const RecoveryStatus(padding: EdgeInsets.zero);
                }
                final row = rows[index - 1];
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
    if (members.length == 1) {
      TransferDetailsRoute(taskId: value(members.single, 'id'))
          .push<void>(context);
      return;
    }
    showGlassModalSheet<void>(
      context: context,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * .7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(DesignTokens.spacingMd),
              child: Text(
                value(row, 'name'),
                style: Theme.of(sheetContext).textTheme.bodyMedium,
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: members.length,
                itemBuilder: (context, index) {
                  final member = members[index];
                  return ListTile(
                    leading: Icon(
                      member['kind'] == 'directory'
                          ? LucideIcons.folder
                          : LucideIcons.file,
                      color: ConnectTokens.amber,
                      size: DesignTokens.componentIconSize,
                    ),
                    title: Text(
                      value(member, 'name', '文件'),
                      style: Theme.of(sheetContext).textTheme.bodyMedium,
                    ),
                    subtitle: Text(
                      transferHistoryStatus(member),
                      style: Theme.of(sheetContext).textTheme.bodySmall,
                    ),
                    trailing: const Icon(
                      LucideIcons.chevronRight,
                      size: DesignTokens.componentIconSmallSize,
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      TransferDetailsRoute(taskId: value(member, 'id'))
                          .push<void>(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
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
              '${value(first, 'name', '文件传输')}${roots.length > 1 ? ' 等 ${roots.length} 项' : ''}',
          if (multiple) 'completedBytes': summary?['transferred'] ?? 0,
          if (multiple) 'totalBytes': summary?['total'],
          'removeParams': batch.isEmpty
              ? {'transferId': first['id']}
              : {'batchId': batch},
        };
      })(),
  ];
}
