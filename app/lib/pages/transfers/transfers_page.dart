import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:scrcpy_connect/core/files/transfer_query_provider.dart';
import 'package:scrcpy_connect/pages/transfers/details/transfer_details_page.dart';
import 'package:scrcpy_connect/pages/transfers/widgets/transfer_history_row.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/async_content.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/workspace_panes.dart';

import 'models/transfer_history_entry.dart';
import 'transfer_history_provider.dart';

class TransfersPage extends HookConsumerWidget {
  const TransfersPage({super.key, this.embedded = false});
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(transferHistoryRowsProvider);
    final source = ref.watch(fileTransfersProvider);
    final finished = useState(false);
    final selection = useState<String?>(null);
    final clearing = useState(false);
    Future<void> refresh() => ref
        .refresh(transferHistoryProvider.future)
        .then<void>((_) {}, onError: (Object _, StackTrace _) {});
    final rows = query.value ?? const <TransferHistoryEntry>[];
    final visible = rows
        .where((row) => transferHistoryFinished(row) == finished.value)
        .toList();
    final selected = rows.where((row) => row.id == selection.value).firstOrNull;

    Future<void> clearHistory() async {
      if (clearing.value) return;
      clearing.value = true;
      try {
        if (!await confirm(
              context,
              '清空已结束的传输记录？',
              '手机原件、本机已保存文件和已取回的暂存文件都会保留。',
              action: '清空记录',
              danger: true,
            ) ||
            !context.mounted) {
          return;
        }
        final targets = [
          for (final row in visible)
            switch (row.batchId) {
              final batch? => FileTransferTarget.batch(batch),
              null => FileTransferTarget.task(row.task.id),
            },
        ];
        await source.clearTransferHistory(targets);
        if (!context.mounted) return;
        selection.value = null;
        await refresh();
      } catch (error) {
        if (context.mounted) feedback(context, '$error');
      } finally {
        if (context.mounted) clearing.value = false;
      }
    }

    return WorkspacePanes(
      onCloseDetail: selected == null ? null : () => selection.value = null,
      hasContent: visible.isNotEmpty || selected != null,
      builder: (context, split) {
        final current = selected ?? (split ? visible.firstOrNull : null);
        final representative = current == null
            ? null
            : _representative(current);
        return (
          list: PageFrame(
            root: embedded,
            pane: split,
            title: '文件传输',
            actions: [
              if (finished.value)
                GlassActionIcon(
                  tooltip: '清空记录',
                  onPressed: visible.isEmpty || clearing.value
                      ? null
                      : clearHistory,
                  icon: const Icon(LucideIcons.trash2),
                ),
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
              builder: (context, _) => RefreshIndicator(
                onRefresh: refresh,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    const PageChromeSliver(),
                    SliverPadding(
                      padding: const EdgeInsets.all(DesignTokens.spacingMd),
                      sliver: SliverToBoxAdapter(
                        child: ContentPanel(
                          padding: const EdgeInsets.all(
                            DesignTokens.componentConnectionTabsPadding,
                          ),
                          child: Row(
                            children: [
                              for (final (done, label) in [
                                (false, '传输中'),
                                (true, '已结束'),
                              ])
                                Expanded(
                                  child: Semantics(
                                    selected: finished.value == done,
                                    child: TextButton(
                                      style: TextButton.styleFrom(
                                        backgroundColor: finished.value == done
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .surfaceContainerHigh
                                            : null,
                                        foregroundColor: finished.value == done
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                            : Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                        shape: const RoundedRectangleBorder(
                                          borderRadius: BorderRadius.all(
                                            Radius.circular(
                                              DesignTokens
                                                  .componentConnectionTabSelectedRounded,
                                            ),
                                          ),
                                        ),
                                      ),
                                      onPressed: () {
                                        if (finished.value == done) return;
                                        finished.value = done;
                                        selection.value = null;
                                      },
                                      child: Text(
                                        label,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (visible.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: EmptyContent(
                          icon: LucideIcons.arrowUpDown,
                          title: finished.value ? '暂无已结束的传输' : '暂无正在传输的任务',
                          message: finished.value
                              ? '完成、失败或取消的任务会出现在这里。'
                              : '发送和接收文件时，可在这里查看进度。',
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: DesignTokens.spacingMd,
                        ),
                        sliver: SliverList.separated(
                          itemCount: visible.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: DesignTokens.spacingSm),
                          itemBuilder: (context, index) {
                            final row = visible[index];
                            return TransferHistoryRow(
                              key: ValueKey((source, row.id)),
                              row: row,
                              selected: split && row.id == current?.id,
                              refresh: refresh,
                              onOpen: () {
                                if (split) {
                                  selection.value = row.id;
                                } else {
                                  TransferDetailsRoute(
                                    taskId: _representative(row).id,
                                  ).push<void>(context);
                                }
                              },
                            );
                          },
                        ),
                      ),
                    const PageChromeBottomSliver(),
                  ],
                ),
              ),
            ),
          ),
          detail: representative == null
              ? const SizedBox.shrink()
              : TransferDetailsPage(
                  key: ValueKey(representative.id),
                  task: representative,
                  pane: split,
                  onBack: split ? null : () => selection.value = null,
                ),
        );
      },
    );
  }

  FileTransferSnapshot _representative(TransferHistoryEntry row) =>
      row.members
          .where((member) => member.parentId?.isNotEmpty != true)
          .firstOrNull ??
      row.task;
}
