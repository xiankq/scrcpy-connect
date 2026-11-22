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
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/async_content.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/content.dart';
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
    return PageFrame(
      titleStyle: Theme.of(context).textTheme.headlineMedium,
      pane: pane,
      onBack: onBack,
      title: standaloneConflict ? '同名文件' : '传输详情',
      actions: [
        IconButton(
          onPressed: refresh,
          tooltip: '重新检查结果',
          icon: const Icon(AppIcons.refresh),
        ),
      ],
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
          final canCancel = batch
              ? summary?.canCancel == true
              : current.canCancel;
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
              final theme = Theme.of(context);
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
              final statusContent = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          status == .running
                              ? current.direction == .pull
                                    ? '正在取回原件'
                                    : '正在发送'
                              : statusText(status.name),
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      if (progress != null && status != .conflict) ...[
                        const SizedBox(width: DesignTokens.spacingXs),
                        Flexible(
                          child: Text(
                            '${(progress * 100).floor()}%${amount.isEmpty ? '' : ' · $amount'}',
                            textAlign: TextAlign.end,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (status != .conflict &&
                      (status == .running ||
                          status == .finalizing ||
                          progress != null)) ...[
                    const SizedBox(height: DesignTokens.spacingSm),
                    TransferProgress(value: progress),
                  ],
                  if (amount.isNotEmpty && progress == null) ...[
                    const SizedBox(height: DesignTokens.spacingXs),
                    Text(amount, style: theme.textTheme.bodySmall),
                  ],
                  const SizedBox(height: DesignTokens.spacingXs),
                  Text(
                    current.direction == .pull &&
                            current.destinationScope == .privateCache
                        ? '$remoteDevice → 本机暂存'
                        : transferListDirection(current, remoteDevice),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              );
              final leading = standaloneConflict
                  ? const <Widget>[]
                  : <Widget>[
                      if (current.direction == .push)
                        ContentPanel(child: statusContent)
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: DesignTokens.spacingXs,
                          ),
                          child: statusContent,
                        ),
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
                      if (!batch)
                        ContentPanel(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              ActionRow(
                                icon: current.kind == .directory
                                    ? LucideIcons.folder
                                    : LucideIcons.file,
                                color: DesignTokens.colorListIconTransfer,
                                title: current.name,
                              ),
                              if ((current.direction == .push
                                      ? current.destination
                                      : current.source)
                                  case final path when path.isNotEmpty)
                                ActionRow(
                                  icon: LucideIcons.folder,
                                  color: current.direction == .push
                                      ? DesignTokens.colorListIconDocument
                                      : DesignTokens.colorListIconTransfer,
                                  title: current.direction == .push
                                      ? '手机目录'
                                      : '来源',
                                  value: current.kind == .directory
                                      ? path
                                      : p.posix.dirname(path),
                                ),
                            ],
                          ),
                        ),
                    ];
              final trailing = <Widget>[
                if (conflictItem != null)
                  ConflictPanel(
                    enabled:
                        (!query.isLoading && !query.hasError && query.hasValue),
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
                if (canCancel) ...[
                  const SizedBox(height: DesignTokens.spacingMd),
                  OutlinedButton(
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
                    style: OutlinedButton.styleFrom(
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(
                          Radius.circular(
                            DesignTokens.componentButtonSecondaryRounded,
                          ),
                        ),
                      ),
                      backgroundColor: theme.colorScheme.surface,
                      side: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                    child: Text(batch ? '停止剩余文件' : '停止传输'),
                  ),
                ],
                if (!batch && current.canRestart)
                  FilledButton(
                    onPressed:
                        !(!query.isLoading && !query.hasError && query.hasValue)
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
                    child: const Text('重新传输'),
                  )
                else if (batch &&
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
                  ),
                const SizedBox(height: DesignTokens.spacingMd),
              ];
              return GroupedListView.builder(
                padding: const EdgeInsets.all(DesignTokens.spacingMd),
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
                  return Material(
                    borderRadius: BorderRadius.vertical(
                      top: row == 0
                          ? const Radius.circular(
                              DesignTokens.componentContentPanelRounded,
                            )
                          : Radius.zero,
                      bottom: row == visibleItems.length - 1
                          ? const Radius.circular(
                              DesignTokens.componentContentPanelRounded,
                            )
                          : Radius.zero,
                    ),
                    color: theme.colorScheme.surface,
                    clipBehavior: Clip.antiAlias,
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
