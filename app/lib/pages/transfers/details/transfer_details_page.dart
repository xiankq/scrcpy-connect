import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:scrcpy_connect/core/files/transfer_query_provider.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/hooks/use_transfer_cache_lease.dart';
import 'package:scrcpy_connect/pages/transfers/details/widgets/conflict_panel.dart';
import 'package:scrcpy_connect/pages/transfers/details/widgets/transfer_export_actions.dart';
import 'package:scrcpy_connect/pages/transfers/details/widgets/transfer_result_row.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/async_content.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/file_transfer_labels.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

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
    return PageFrame(
      pane: pane,
      onBack: onBack,
      title: '传输详情',
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
              final leading = <Widget>[
                Text(
                  '${current.name}'
                  '${batch ? ' · $itemCount 项' : ''}',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: DesignTokens.spacingSm),
                Text(
                  statusText(status.name),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: DesignTokens.spacingXs),
                Text(
                  transferDetailDirection(current, remoteDevice),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: DesignTokens.spacingMd),
                if (current.kind == .directory && current.status == .finalizing)
                  const StateNote('目录结构已建立，仍在核验所选内容。请等待批次实际结果。'),
                if ((current.exportReason ?? '').isNotEmpty)
                  StateNote((current.exportReason ?? '')),
                if (cacheLease.hasError)
                  StateNote('暂存原件不可用：${cacheLease.error}。请重新取回原件后再保存或分享。'),
              ];
              final trailing = <Widget>[
                if (conflictItem != null)
                  ConflictPanel(
                    enabled:
                        (!query.isLoading && !query.hasError && query.hasValue),
                    key: ValueKey(('transfer-conflict', conflictItem.id)),
                    transfer: transferView(devices, conflictItem),
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
                if (canCancel)
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
                    child: Text(batch ? '取消剩余未完成项' : '取消传输'),
                  ),
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
                    '批次不会整体重放。请在逐项结果中打开要重试的项，确认来源和目标后单独重新传输。',
                    icon: LucideIcons.info,
                  ),
                if (batch && status == .completedWithSkips)
                  const StateNote(
                    '部分内容因符号链接或特殊文件被跳过，未作为完整原件传输。',
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
                ].contains(status))
                  StateNote(
                    (current.error ?? '请核对逐项结果。已完成与未完成内容分别保留，不会自动重复有未知结果的操作。'),
                    icon: LucideIcons.circleAlert,
                  ),
                const SizedBox(height: DesignTokens.spacingMd),
                TextButton(onPressed: refresh, child: const Text('重新检查结果')),
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
                  return TransferResultRow(
                    key: ValueKey((
                      'transfer-item',
                      current.id,
                      item.source,
                      item.destination,
                      row,
                    )),
                    transfer: item,
                    deviceName: remoteDevice,
                    onOpen: rawItem.id == current.id
                        ? null
                        : () =>
                              TransferDetailsRoute(taskId: rawItem.id)
                                  .push<void>(context),
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
