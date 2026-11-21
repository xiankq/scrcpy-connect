import 'dart:io';

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
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';

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
    final progress = total > 0
        ? (completed / total).clamp(0, 1).toDouble()
        : null;
    final devices = ref
        .watch(deviceListProvider)
        .devices
        .where((d) => d.id == task.deviceId);
    final name = devices.isEmpty
        ? (task.deviceName ?? '设备')
        : deviceName(devices.first);
    final direction = transferListDirection(task, name);
    final statusDescription = busy.value
        ? '正在停止…'
        : transferStatusDescription(task);
    final issue = transferStatusHasIssue(task.status);

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
        if (context.mounted && ownsScope()) feedback(context, '$error');
      } finally {
        if (context.mounted && ownsScope()) busy.value = false;
      }
    }

    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(DesignTokens.roundedLg);
    final path = task.localPath;
    final extension = task.name.split('.').last.toLowerCase();
    final image = const {
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'bmp',
    }.contains(extension);
    final formatIcon = ListIconBadge(
      icon: switch (extension) {
        'zip' || 'gz' || 'rar' || '7z' => LucideIcons.archive,
        'mp4' || 'mov' || 'mkv' => LucideIcons.video,
        'mp3' || 'wav' || 'flac' => LucideIcons.music,
        'pdf' || 'txt' || 'docx' => LucideIcons.fileText,
        _ => image ? LucideIcons.image : LucideIcons.file,
      },
      backgroundColor: DesignTokens.colorListIconBlue,
    );
    return Semantics(
      selected: selected,
      child: Material(
        color: selected ? colors.surfaceContainerHigh : colors.surface,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.only(
              left: DesignTokens.spacingMd,
              right: DesignTokens.spacingXs,
              top: DesignTokens.spacingXs,
              bottom: DesignTokens.spacingXs,
            ),
            child: Row(
              children: [
                if (image && path != null && row.members.length == 1)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(DesignTokens.roundedMd),
                    child: Image.file(
                      File(path),
                      width: DesignTokens.componentIconButtonSize,
                      height: DesignTokens.componentIconButtonSize,
                      fit: BoxFit.cover,
                      cacheWidth: 132,
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) => formatIcon,
                    ),
                  )
                else if (task.kind == .directory || row.members.length > 1)
                  const ListIconBadge(
                    icon: LucideIcons.folder,
                    backgroundColor: DesignTokens.colorListIconAmber,
                  )
                else
                  formatIcon,
                const SizedBox(width: DesignTokens.spacingSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.name,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: DesignTokens.spacingXxs),
                      Row(
                        children: [
                          Icon(
                            task.direction == .push
                                ? LucideIcons.arrowUpFromLine
                                : LucideIcons.arrowDownToLine,
                            size: DesignTokens.componentIconSmallSize,
                            color: colors.primary,
                          ),
                          const SizedBox(width: DesignTokens.spacingXxs),
                          Flexible(
                            child: Text(
                              direction,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: DesignTokens.spacingXxs),
                      Text(
                        statusDescription,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: issue
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                      ),
                      if (active) ...[
                        const SizedBox(height: DesignTokens.spacingXxs),
                        if (progress == null)
                          const ContentLoadingIndicator()
                        else
                          LinearProgressIndicator(
                            value: progress,
                            minHeight: DesignTokens.spacingMicro,
                            borderRadius: BorderRadius.circular(
                              DesignTokens.roundedFull,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                if (busy.value)
                  const Padding(
                    padding: EdgeInsets.all(DesignTokens.spacingSm),
                    child: SizedBox(
                      width: DesignTokens.componentIconSmallSize,
                      height: DesignTokens.componentIconSmallSize,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  GlassMenuButton(
                    icon: const Icon(LucideIcons.ellipsis),
                    tooltip: '传输操作',
                    actions: [
                      GlassMenuAction(
                        label: '查看详情',
                        icon: const Icon(LucideIcons.info),
                        onPressed: onOpen,
                      ),
                      GlassMenuAction(
                        label: active ? '停止并移除…' : '移除记录',
                        icon: const Icon(LucideIcons.trash2),
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
