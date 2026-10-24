import 'package:scrcpy_connect/presentation/formatters.dart';
import 'package:scrcpy_connect/application/transport/json_readers.dart';
import 'package:scrcpy_connect/application/transport/application_request.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/pages/transfers/widgets/transfer_direction_badge.dart';
import 'package:scrcpy_connect/application/app_controller.dart';
import 'package:scrcpy_connect/presentation/transfer_presentation.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';

bool transferHistoryActive(Json row) =>
    row['canCancel'] == true ||
    [
      'queued',
      'running',
      'finalizing',
      'cancelling',
      'conflict',
    ].contains(row['status']);

class TransferHistoryRow extends HookWidget {
  const TransferHistoryRow({
    super.key,
    required this.controller,
    required this.row,
    required this.refresh,
    required this.onOpen,
  });
  final AppController controller;
  final Json row;
  final VoidCallback refresh;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final busy = useState(false);
    final active = transferHistoryActive(row);
    final total = num.tryParse('${row['totalBytes']}') ?? 0;
    final completed = num.tryParse('${row['completedBytes']}') ?? 0;
    final progress = total > 0
        ? (completed / total).clamp(0, 1).toDouble()
        : null;
    final devices = controller.snapshot().devices.where(
      (d) => d['id'] == row['deviceId'],
    );
    final name = devices.isEmpty
        ? value(row, 'deviceName', '设备')
        : deviceName(devices.first);
    final direction = transferListDirection(row, name);
    final statusDescription = busy.value
        ? '正在停止…'
        : transferStatusDescription(row);
    final issue = transferStatusHasIssue(value(row, 'status'));

    Future<void> remove() async {
      if (busy.value) return;
      final unsaved =
          row['direction'] == 'pull' &&
          row['destinationScope'] == 'privateCache';
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
          !context.mounted) {
        return;
      }
      busy.value = true;
      final params = jsonObject(row['removeParams']);
      try {
        if (active) {
          await controller.request('transfers.cancel', params);
          var stopped = false;
          for (var check = 0; check < 60 && context.mounted; check++) {
            final data = await controller.request('transfers.list');
            final selected = objects(data['transfers']).where(
              (t) => params['batchId'] != null
                  ? t['batchId'] == params['batchId']
                  : t['id'] == params['transferId'],
            );
            if (selected.every((t) => !transferHistoryActive(t))) {
              stopped = true;
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
          if (!context.mounted) return;
          if (!stopped) {
            feedback(context, '正在停止，结束后可移除记录。');
            return;
          }
        }
        await controller.request('transfers.remove', params);
        if (context.mounted) refresh();
      } catch (error) {
        if (context.mounted) feedback(context, '$error');
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return InkWell(
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
            TransferDirectionBadge(transfer: row),
            const SizedBox(width: DesignTokens.spacingSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value(row, 'name', '文件传输'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: DesignTokens.spacingXxs),
                  Text(direction, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: DesignTokens.spacingXxs),
                  Text(
                    statusDescription,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: issue ? Theme.of(context).colorScheme.error : null,
                    ),
                  ),
                  if (active) ...[
                    const SizedBox(height: DesignTokens.spacingXxs),
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
    );
  }
}
