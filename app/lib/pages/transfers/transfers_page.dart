import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/widgets/tab_transition.dart';
import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:scrcpy_connect/core/files/transfer_query_provider.dart';
import 'package:scrcpy_connect/pages/transfers/details/transfer_details_page.dart';
import 'package:scrcpy_connect/pages/transfers/widgets/transfer_history_row.dart';
import 'package:scrcpy_connect/pages/transfers/widgets/transfer_task_card.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/async_content.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/form_controls.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/loading_skeleton.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/workspace_panes.dart';

import 'models/transfer_history_entry.dart';
import 'transfer_history_provider.dart';

/// 骨架卡高度：进行中卡片含进度区（Ardot T1 2:1633 约 116），已结束卡片约 104。
const _activeCardHeight = 116.0;
const _finishedCardHeight = 104.0;

class TransfersPage extends HookConsumerWidget {
  const TransfersPage({super.key, this.embedded = false});
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(transferHistoryRowsProvider);
    final source = ref.watch(fileTransfersProvider);
    final finished = useState(false);
    final ongoingScroll = useScrollController();
    final finishedScroll = useScrollController();
    final selection = useState<String?>(null);
    final clearing = useState(false);
    Future<void> refresh() => ref
        .refresh(transferHistoryProvider.future)
        .then<void>((_) {}, onError: (Object _, StackTrace _) {});
    final rows = query.value ?? const <TransferHistoryEntry>[];
    final (ongoingRows, finishedRows) = useMemoized(() {
      final ongoing = <TransferHistoryEntry>[];
      final completed = <TransferHistoryEntry>[];
      for (final row in rows) {
        (transferHistoryFinished(row) ? completed : ongoing).add(row);
      }
      final positions = {
        for (final (index, row) in completed.indexed) row.id: index,
      };
      completed.sort((a, b) {
        final time = (b.task.endedAt ?? 0).compareTo(a.task.endedAt ?? 0);
        return time == 0 ? positions[a.id]!.compareTo(positions[b.id]!) : time;
      });
      return (ongoing, completed);
    }, [rows]);
    final visible = finished.value ? finishedRows : ongoingRows;
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
        if (context.mounted) {
          feedback(
            context,
            failureMessage(error, fallback: '无法清空传输记录。请刷新列表后再试。'),
          );
        }
      } finally {
        if (context.mounted) clearing.value = false;
      }
    }

    final actions = [
      if (finished.value)
        GlassActionIcon(
          tooltip: '清空记录',
          onPressed: visible.isEmpty || clearing.value ? null : clearHistory,
          icon: const Icon(AppIcons.delete),
        ),
      GlassActionIcon(
        tooltip: '刷新任务',
        onPressed: refresh,
        icon: const Icon(AppIcons.refresh),
      ),
    ];
    return WorkspacePanes(
      onCloseDetail: selected == null ? null : () => selection.value = null,
      hasContent: visible.isNotEmpty || selected != null,
      builder: (context, split, useSideToolbar) {
        final current = selected ?? (split ? visible.firstOrNull : null);
        final representative = current == null
            ? null
            : _representative(current);
        final selector = Padding(
          padding: const EdgeInsets.fromLTRB(
            DesignTokens.spacingLg,
            0,
            DesignTokens.spacingLg,
            DesignTokens.spacingMd,
          ),
          child: ConnectSegmentedControl<bool>(
            onPage: true,
            options: const [(false, '传输中'), (true, '已结束')],
            selected: finished.value,
            onSelected: (done) {
              if (finished.value == done) return;
              finished.value = done;
              selection.value = null;
            },
          ),
        );
        Widget buildList({
          required bool loading,
          required bool done,
          required List<TransferHistoryEntry> entries,
        }) => RefreshIndicator(
          onRefresh: refresh,
          child: CustomScrollView(
            key: PageStorageKey(('transfer-history', done)),
            controller: done ? finishedScroll : ongoingScroll,
            primary: false,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (loading)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    DesignTokens.spacingLg,
                    0,
                    DesignTokens.spacingLg,
                    DesignTokens.spacingLg,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: SkeletonRows(
                      height: done ? _finishedCardHeight : _activeCardHeight,
                      leadingSize: transferThumbnailSize,
                      cardRadius: DesignTokens.componentListGroupRounded,
                      gap: DesignTokens.spacingMd,
                      lines: 3,
                      trailing: true,
                      progress: !done,
                    ),
                  ),
                )
              else if (entries.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyContent(
                    icon: LucideIcons.inbox,
                    title: done ? '暂无已结束的传输' : '暂无正在传输的任务',
                    message: done ? '完成、失败或取消的任务会出现在这里。' : '发送和接收文件时，可在这里查看进度。',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    DesignTokens.spacingLg,
                    0,
                    DesignTokens.spacingLg,
                    DesignTokens.spacingLg,
                  ),
                  sliver: SliverList.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: DesignTokens.spacingMd),
                    itemBuilder: (context, index) {
                      final row = entries[index];
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
            ],
          ),
        );
        Widget buildTabs({required bool loading}) => TabPaneStack(
          index: finished.value ? 1 : 0,
          children: [
            buildList(loading: loading, done: false, entries: ongoingRows),
            buildList(loading: loading, done: true, entries: finishedRows),
          ],
        );
        return (
          list: PageFrame(
            root: embedded,
            pane: split,
            title: '传输',
            primaryScrollController: finished.value
                ? finishedScroll
                : ongoingScroll,
            actions: useSideToolbar ? null : actions,
            child: PageChromeBody(
              child: Column(
                children: [
                  selector,
                  Expanded(
                    child: PageChromePadding(
                      padding: EdgeInsets.zero,
                      showRecovery: false,
                      child: AsyncContent<List<TransferHistoryEntry>>(
                        loading: query.isLoading,
                        data: query.value,
                        error: query.error,
                        onRefresh: refresh,
                        emptyTitle: '暂时无法读取传输任务',
                        loadingPlaceholder: buildTabs(loading: true),
                        builder: (context, _) => buildTabs(loading: false),
                      ),
                    ),
                  ),
                ],
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
          sideActions: useSideToolbar ? actions : const [],
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
