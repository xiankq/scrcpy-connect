import 'dart:io';

import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/file_transfer_labels.dart';
import 'package:scrcpy_connect/widgets/glass/glass_menu.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/utils/formatters.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';
import 'package:scrcpy_connect/pages/files/widgets/file_kind_style.dart';

import 'transfer_progress.dart';

import '../models/transfer_history_entry.dart';

bool transferHistoryActive(FileTransferSnapshot row) =>
    row.canCancel || row.status.isActive;

bool transferHistoryFinished(TransferHistoryEntry row) =>
    !transferHistoryActive(row.task) &&
    row.members.every(
      (task) =>
          !transferHistoryActive(task) &&
          !task.cleanupPending &&
          task.errorCode != 'result_unknown' &&
          task.status != .unknown &&
          task.status != .paused,
    );

class TransferHistoryRow extends HookConsumerWidget {
  const TransferHistoryRow({
    super.key,
    required this.row,
    required this.refresh,
    required this.onOpen,
    this.selected = false,
  });
  final TransferHistoryEntry row;
  final VoidCallback refresh;
  final VoidCallback onOpen;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = row.task;
    final transfers = ref.watch(fileTransfersProvider);
    final target = switch (row.batchId) {
      final id? => FileTransferTarget.batch(id),
      null => FileTransferTarget.task(task.id),
    };
    final busy = useValueNotifier(false, [transfers, target]);
    useValueListenable(busy);
    final currentBusy = useRef(busy)..value = busy;
    bool ownsScope() =>
        context.mounted &&
        identical(currentBusy.value, busy) &&
        identical(ref.read(fileTransfersProvider), transfers);
    final active = transferHistoryActive(task);
    final total = task.totalBytes ?? task.total ?? 0;
    final completed = task.completedBytes ?? task.transferred;
    final progress = transferProgressValue(completed, total);
    final devices = ref
        .watch(deviceListProvider)
        .devices
        .where((d) => d.id == task.deviceId);
    final name = devices.isEmpty
        ? (task.deviceName ?? '设备')
        : deviceName(devices.first);
    final direction = transferListDirection(task, name);

    Future<void> remove() async {
      if (busy.value) return;
      final unsaved =
          task.direction == .pull && task.destinationScope == .privateCache;
      if (!await confirm(
            context,
            active ? '停止并移除这项传输？' : '移除传输记录？',
            active
                ? '先停止正在进行的传输，再移除记录。已完成部分和文件会保留。'
                      '${unsaved ? '未保存的暂存内容将无法从此处保存。' : ''}'
                : '仅移除这条记录，不会删除已保存文件。'
                      '${unsaved ? '未保存的暂存内容将无法从此处保存。' : ''}',
            action: active ? '停止并移除' : '移除记录',
            danger: true,
          ) ||
          (!context.mounted || !ownsScope())) {
        return;
      }
      busy.value = true;
      try {
        if (active) {
          await transfers.cancelTransfer(target);
          var stopped = false;
          for (var check = 0; check < 60 && ownsScope(); check++) {
            final data = await transfers.readTransfers();
            if (!ownsScope()) return;
            final selected = data.transfers.where(
              (task) => switch (target) {
                FileTransferBatchTarget(:final id) => task.batchId == id,
                FileTransferTaskTarget(:final id) => task.id == id,
              },
            );
            if (selected.every((t) => !transferHistoryActive(t))) {
              stopped = true;
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
          if ((!context.mounted || !ownsScope())) return;
          if (!stopped) {
            feedback(context, '正在停止，结束后可移除记录。');
            return;
          }
        }
        await transfers.removeTransfer(target);
        if (context.mounted && ownsScope()) refresh();
      } catch (error) {
        if (context.mounted && ownsScope()) {
          feedback(
            context,
            failureMessage(error, fallback: '无法更新这条传输。请先查看它的当前状态。'),
          );
        }
      } finally {
        if (context.mounted && ownsScope()) busy.value = false;
      }
    }

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final path = task.localPath;
    final kind = FileKind.classify(name: task.name);
    final group = task.kind == .directory || row.members.length > 1;
    final iconColor = ConnectTokens.accent(
      context,
      group
          ? DesignTokens.colorListIconAmber
          : fileKindColor(kind, name: task.name),
    );
    final graphic = FeatureIcon(
      group ? LucideIcons.folder : fileKindIcon(kind),
      color: iconColor,
      size: DesignTokens.componentTransferCardThumbnailWidth,
    );
    final progressVisible =
        task.status == .running || task.status == .finalizing;
    final terminal = transferHistoryFinished(row);
    final issue = transferStatusHasIssue(task.status);
    final statusColor = issue
        ? colors.error
        : task.status == .completed || task.status == .completedWithSkips
        ? ConnectTokens.accent(context, ConnectTokens.mint)
        : colors.onSurfaceVariant;
    final stage = busy.value
        ? '正在停止…'
        : task.errorCode == 'result_unknown' || task.cleanupPending
        ? '结果待确认'
        : task.status == .conflict
        ? '待处理'
        : statusText(task.status.name);
    final amount = terminal
        ? transferResultSize(task)
        : total > 0
        ? '${bytes(completed)} / ${bytes(total)}'
        : completed > 0
        ? bytes(completed)
        : '';
    final ended = terminal && task.endedAt != null
        ? DateTime.fromMillisecondsSinceEpoch(task.endedAt! * 1000)
        : null;
    final localizations = MaterialLocalizations.of(context);
    final radius = BorderRadius.circular(DesignTokens.roundedLg);
    return Semantics(
      selected: selected,
      child: Material(
        color: selected ? colors.surfaceContainerHigh : colors.surface,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              DesignTokens.spacingMd,
              DesignTokens.spacingSm,
              DesignTokens.spacingXs,
              DesignTokens.spacingSm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (kind == FileKind.images && path != null && !group)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(DesignTokens.roundedMd),
                    child: Image.file(
                      File(path),
                      width: DesignTokens.componentTransferCardThumbnailWidth,
                      height: DesignTokens.componentTransferCardThumbnailWidth,
                      fit: BoxFit.cover,
                      cacheWidth: 144,
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) => graphic,
                    ),
                  )
                else
                  graphic,
                const SizedBox(width: DesignTokens.spacingSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              task.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: DesignTokens.spacingXs),
                          Flexible(
                            flex: 2,
                            child:
                                progressVisible &&
                                    progress != null &&
                                    !busy.value
                                ? Text(
                                    '${(progress * 100).floor()}%',
                                    textAlign: TextAlign.end,
                                    style: theme.textTheme.titleMedium,
                                  )
                                : DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: task.status == .conflict
                                          ? (theme.brightness == Brightness.dark
                                                ? DesignTokens
                                                      .colorAccentAmberSoftDark
                                                : DesignTokens
                                                      .colorAccentAmberSoft)
                                          : statusColor.withValues(
                                              alpha: DesignTokens
                                                  .componentFeatureIconOpacity,
                                            ),
                                      borderRadius: BorderRadius.circular(
                                        DesignTokens.roundedFull,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: DesignTokens.spacingXs,
                                        vertical: DesignTokens.spacingMicro,
                                      ),
                                      child: Text(
                                        stage,
                                        textAlign: TextAlign.end,
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(color: statusColor),
                                      ),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                      const SizedBox(height: DesignTokens.spacingXxs),
                      Row(
                        children: [
                          Icon(
                            task.direction == .push
                                ? LucideIcons.arrowUpFromLine
                                : LucideIcons.arrowDownToLine,
                            size: DesignTokens.componentIconSmallSize,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: DesignTokens.spacingXxs),
                          Flexible(
                            child: Text(
                              direction,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                      if (progressVisible) ...[
                        const SizedBox(height: DesignTokens.spacingXs),
                        TransferProgress(value: progress),
                      ],
                      if (amount.isNotEmpty ||
                          issue ||
                          ended != null ||
                          task.status == .conflict) ...[
                        const SizedBox(height: DesignTokens.spacingXxs),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                task.status == .conflict
                                    ? (task.direction == .push
                                          ? '手机中已有同名文件'
                                          : '本机已有同名文件')
                                    : issue
                                    ? transferStatusDescription(task)
                                    : amount,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: issue ? statusColor : null,
                                ),
                              ),
                            ),
                            if (ended != null) ...[
                              const SizedBox(width: DesignTokens.spacingXs),
                              Flexible(
                                child: Text(
                                  '${ended.month}/${ended.day} ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(ended), alwaysUse24HourFormat: true)}',
                                  textAlign: TextAlign.end,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (busy.value)
                  const SizedBox(
                    width: DesignTokens.componentIconButtonSize,
                    height: DesignTokens.componentIconButtonSize,
                    child: ContentLoadingIndicator(
                      size: DesignTokens.componentIconSmallSize,
                    ),
                  )
                else
                  GlassMenuButton(
                    icon: const Icon(AppIcons.more),
                    tooltip: '传输操作',
                    actions: [
                      GlassMenuAction(
                        label: '查看详情',
                        icon: const Icon(LucideIcons.info),
                        onPressed: onOpen,
                      ),
                      GlassMenuAction(
                        label: active ? '停止并移除…' : '移除记录',
                        icon: const Icon(AppIcons.delete),
                        destructive: true,
                        onPressed: remove,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
