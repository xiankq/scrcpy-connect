import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/transfer_query_provider.dart';
import 'package:scrcpy_connect/pages/transfers/widgets/transfer_history_row.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/async_content.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/recovery_status.dart';

import 'models/transfer_history_entry.dart';
import 'transfer_history_provider.dart';

class TransfersPage extends ConsumerWidget {
  const TransfersPage({super.key, this.embedded = false});
  final bool embedded;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(transferHistoryRowsProvider);
    final source = ref.watch(fileTransfersProvider);
    Future<void> refresh() => ref
        .refresh(transferHistoryProvider.future)
        .then<void>((_) {}, onError: (Object _, StackTrace _) {});
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
      child: AsyncContent<List<TransferHistoryEntry>>(
        loading: query.isLoading,
        data: query.value,
        error: query.error,
        onRefresh: refresh,
        emptyTitle: '暂时无法读取传输任务',
        builder: (context, rows) {
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
