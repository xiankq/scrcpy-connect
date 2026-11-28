import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:scrcpy_connect/core/files/transfer_query_provider.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/hooks/use_transfer_cache_lease.dart';
import 'package:scrcpy_connect/pages/transfers/details/widgets/conflict_panel.dart';
import 'package:scrcpy_connect/pages/transfers/details/widgets/transfer_export_actions.dart';
import 'package:scrcpy_connect/pages/transfers/details/widgets/transfer_result_row.dart';
import 'package:scrcpy_connect/pages/transfers/widgets/transfer_progress.dart';
import 'package:scrcpy_connect/widgets/grouped_list_segment.dart';
import 'package:scrcpy_connect/pages/transfers/widgets/transfer_task_card.dart';
import 'package:scrcpy_connect/pages/files/widgets/file_kind_style.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/async_content.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:scrcpy_connect/widgets/list_row.dart';
import 'package:scrcpy_connect/widgets/status_tag.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/utils/formatters.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/file_transfer_labels.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';

class TransferDetailsPage extends HookConsumerWidget {
  const TransferDetailsPage({
    super.key,
    required this.task,
    this.pane = false,
    this.onBack,
  });
  final bool pane;
  final VoidCallback? onBack;
  final FileTransferSnapshot task;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(deviceListProvider).devices;
    final provider = transferDetailsProvider(task.id);
    final query = ref.watch(provider);
    final source = ref.watch(fileTransfersProvider);
    Future<void> refresh() => ref
        .refresh(provider.future)
        .then<void>((_) {}, onError: (Object _, StackTrace _) {});
    final shown = query.value ?? task;
    final standaloneConflict =
        shown.status == .conflict &&
        (shown.itemCount <= 1 || (shown.parentId ?? '').isNotEmpty);
    final settled = !query.isLoading && !query.hasError && query.hasValue;

    /// 停止与重新传输在页面底部，只依赖当前记录。
    Widget? bottomAction(FileTransferSnapshot data) {
      final current = transferView(devices, data);
      final batch = current.itemCount > 1 && (current.parentId ?? '').isEmpty;
      final summary = current.batch;
      final canCancel = batch ? summary?.canCancel == true : current.canCancel;
      if (canCancel) {
        return AppButton(
          role: AppButtonRole.destructiveOnPage,
          expand: true,
          label: batch ? '停止剩余文件' : '停止传输',
          onPressed: () async {
            if (await confirm(
                  context,
                  batch ? '取消剩余未完成项？' : '取消未完成的传输？',
                  '已完成内容会保留。未完成的临时项将按实际情况清理，不会作为完整文件保存。',
                  action: batch ? '取消剩余项' : '取消传输',
                ) &&
                context.mounted) {
              await performAction(
                context,
                () => source.cancelTransfer(
                  batch
                      ? FileTransferTarget.batch(summary!.batchId)
                      : FileTransferTarget.task(current.id),
                ),
              );
              refresh();
            }
          },
        );
      }
      if (!batch && current.canRestart) {
        return AppButton(
          role: AppButtonRole.primary,
          expand: true,
          label: '重新传输',
          onPressed: !settled
              ? null
              : () async {
                  if (await confirm(
                        context,
                        '从头重新传输？',
                        '本次将从 0 开始，并重新检查来源与目标。来源已经变化时，需要重新确认，已有内容不会作为续传进度。',
                        action: '重新传输',
                      ) &&
                      context.mounted) {
                    await performAction(
                      context,
                      () => source.restartTransfer(current.id),
                    );
                    refresh();
                  }
                },
        );
      }
      return null;
    }

    return PageFrame(
      pane: pane,
      onBack: onBack,
      title: standaloneConflict ? '同名文件' : '传输详情',
      actions: [
        GlassActionIcon(
          onPressed: refresh,
          tooltip: '重新检查结果',
          icon: const Icon(AppIcons.refresh),
        ),
      ],
      bottom: switch (query.value) {
        final data? => bottomAction(data),
        null => null,
      },
      child: AsyncContent<FileTransferSnapshot>(
        loading: query.isLoading,
        data: query.value,
        error: query.error,
        onRefresh: refresh,
        emptyTitle: '暂时无法读取传输结果',
        builder: (context, data) {
          final current = transferView(devices, data);
          final rawItems = current.items;
          final items = rawItems.isEmpty ? [current] : rawItems;
          final itemCount = current.itemCount;
          // 子项保留自己的结果与重试入口，只有批次代表项展示完整子项列表。
          final batch = itemCount > 1 && (current.parentId ?? '').isEmpty;
          final summary = current.batch;
          final status = batch
              ? summary?.status ?? current.status
              : current.status;
          final conflictItem = batch
              ? items.where((item) => item.status == .conflict).firstOrNull
              : current.status == .conflict
              ? current
              : null;
          final visibleItems = batch ? items : const <FileTransferSnapshot>[];
          final remoteDevice = current.direction == .push
              ? (current.destinationLabel ?? '设备')
              : (current.sourceLabel ?? '设备');
          return HookConsumer(
            key: ValueKey((source, task.id)),
            builder: (context, ref, _) {
              final cacheLease = useTransferCacheLease(
                ref,
                current.destinationScope == .privateCache &&
                        (current.canExport ||
                            <FileTransferStatus>[
                              .queued,
                              .running,
                              .finalizing,
                              .cancelling,
                              .conflict,
                            ].contains(status))
                    ? current.id
                    : null,
              );
              final colors = AppColors.of(context);
              final completed = batch
                  ? summary?.transferred ?? 0
                  : current.completedBytes ?? current.transferred;
              final total = batch
                  ? summary?.total
                  : current.totalBytes ?? current.total;
              final progress = transferProgressValue(completed, total);
              final amount = total != null && total > 0
                  ? '${bytes(completed)} / ${bytes(total)}'
                  : completed > 0
                  ? bytes(completed)
                  : '';
              final stage = status == .running
                  ? current.direction == .pull
                        ? '正在取回原件'
                        : '正在发送'
                  : statusText(status.name);
              final issue = transferStatusHasIssue(status);
              final showPercent = progress != null && status != .conflict;
              final summaryCard = TransferTaskCard(
                thumbnail: TransferThumbnail(task: current, group: batch),
                title: current.name,
                direction:
                    '${current.direction == .push ? '发送' : '取回'} · '
                    '${current.direction == .pull && current.destinationScope == .privateCache ? '$remoteDevice → 本机暂存' : transferListDirection(current, remoteDevice)}',
                status: showPercent
                    ? TransferPercent(progress)
                    : StatusTag(
                        stage,
                        tone: issue
                            ? StatusTagTone.error
                            : status == .conflict
                            ? StatusTagTone.warning
                            : status == .completed ||
                                  status == .completedWithSkips
                            ? StatusTagTone.success
                            : StatusTagTone.neutral,
                      ),
                showProgress:
                    status != .conflict &&
                    (status == .running ||
                        status == .finalizing ||
                        progress != null),
                progress: progress,
                detail: showPercent
                    ? [
                        amount,
                        stage,
                      ].where((part) => part.isNotEmpty).join(' · ')
                    : amount,
              );
              final path = current.direction == .push
                  ? current.destination
                  : current.source;
              final kind = FileKind.classify(name: current.name);
              final folder = current.kind == .directory;
              final leading = standaloneConflict
                  ? const <Widget>[]
                  : <Widget>[
                      summaryCard,
                      if (current.kind == .directory &&
                          current.status == .finalizing)
                        const StateNote('已建好文件夹，正在检查里边的文件。'),
                      if ((current.exportReason ?? '').isNotEmpty &&
                          !current.canExport)
                        const StateNote('这个文件暂时无法保存。请先查看传输结果。'),
                      if (cacheLease.hasError)
                        StateNote(
                          failureMessage(
                            cacheLease.error,
                            fallback: '临时文件已不可用。请从手机重新取回后再保存或分享。',
                          ),
                        ),
                      const SectionTitle('本次文件'),
                      if (!batch) ...[
                        SettingsGroup(
                          children: [
                            AppListRow(
                              leading: ListIconBadge(
                                icon: folder
                                    ? folderKindIcon
                                    : fileKindIcon(kind),
                                backgroundColor: folder
                                    ? folderKindColor
                                    : fileKindColor(kind, name: current.name),
                              ),
                              title: Text(current.name),
                              value: stage,
                            ),
                          ],
                        ),
                        if (path.isNotEmpty) ...[
                          const SectionTitle('位置'),
                          SettingsGroup(
                            children: [
                              AppListRow(
                                title: Text(
                                  current.direction == .push ? '手机目录' : '来源',
                                ),
                                value: current.kind == .directory
                                    ? path
                                    : p.posix.dirname(path),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ];
              final trailing = <Widget>[
                if (conflictItem != null)
                  ConflictPanel(
                    enabled: settled,
                    key: ValueKey(('transfer-conflict', conflictItem.id)),
                    transfer: transferView(devices, conflictItem),
                    showTitle: !standaloneConflict,
                    onResolve: (policy, all) async {
                      await performAction(
                        context,
                        () => source.resolveConflict(
                          conflictItem.id,
                          policy,
                          applyToAll: all,
                        ),
                      );
                      refresh();
                    },
                  ),
                if (batch &&
                    <FileTransferStatus>[
                      .partialFailure,
                      .interrupted,
                      .cancelled,
                    ].contains(status))
                  const StateNote(
                    '请在列表里打开还没传完的项目，逐项检查后再重试。',
                    icon: LucideIcons.info,
                  ),
                if (batch && status == .completedWithSkips)
                  const StateNote(
                    '有些链接或特殊文件无法复制，已跳过。请查看每项结果。',
                    icon: LucideIcons.info,
                  ),
                const SizedBox(height: DesignTokens.spacingLg),
                TransferExportActions(
                  current: current,
                  taskId: current.id,
                  cacheReady: cacheLease.hasData && !cacheLease.hasError,
                ),
                if (<FileTransferStatus>[
                      .failed,
                      .partial,
                      .interrupted,
                      .paused,
                    ].contains(status) ||
                    current.cleanupPending ||
                    current.errorCode == 'result_unknown')
                  StateNote(
                    transferIssueMessage(current),
                    icon: LucideIcons.circleAlert,
                    color: colors.error,
                  ),
                const SizedBox(height: DesignTokens.spacingLg),
              ];
              return GroupedListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spacingLg,
                ),
                itemCount:
                    leading.length + visibleItems.length + trailing.length,
                findChildIndexCallback: (key) {
                  final index = trailing.indexWhere(
                    (widget) => widget.key == key,
                  );
                  return index < 0
                      ? null
                      : leading.length + visibleItems.length + index;
                },
                itemBuilder: (context, index) {
                  if (index < leading.length) return leading[index];
                  final row = index - leading.length;
                  if (row >= visibleItems.length) {
                    return trailing[row - visibleItems.length];
                  }
                  final rawItem = visibleItems[row];
                  final item = transferView(devices, rawItem);
                  return GroupedListSegment(
                    first: row == 0,
                    last: row == visibleItems.length - 1,
                    child: TransferResultRow(
                      key: ValueKey(('transfer-item', rawItem.id)),
                      transfer: item,
                      onOpen: rawItem.id == current.id
                          ? null
                          : () =>
                                TransferDetailsRoute(taskId: rawItem.id)
                                    .push<void>(context),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
