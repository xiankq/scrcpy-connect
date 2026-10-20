import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
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

String transferHistoryStatus(Json row) => switch (value(row, 'status')) {
  'completed'
      when row['direction'] == 'pull' &&
          row['destinationScope'] == 'privateCache' =>
    '已接收 · 待保存',
  'completed' => '已完成',
  'partialFailure' || 'partial' => '部分失败',
  'completedWithSkips' => '已完成，部分跳过',
  'running' => '传输中',
  'queued' => '等待传输',
  'cancelling' => '正在停止…',
  'finalizing' => '正在确认结果',
  'conflict' => '同名文件待处理',
  'cancelled' => '已停止',
  'interrupted' || 'paused' => '已中断',
  'failed' => '传输失败',
  'skipped' => '已跳过',
  _ => '状态待确认',
};

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
    final direction = row['direction'] == 'push' ? '发送到 $name' : '接收自 $name';
    final status = busy.value ? '正在停止并移除…' : transferHistoryStatus(row);

    Future<void> remove() async {
      if (busy.value) return;
      final unsaved =
          row['direction'] == 'pull' &&
          row['destinationScope'] == 'privateCache';
      if (!await confirm(
            context,
            active ? '停止并移除这条传输？' : '移除传输记录？',
            '${active ? '停止尚未完成的传输，并移除这条记录。' : '仅移除这条记录。'}已保存文件不受影响。${unsaved ? '未保存的暂存内容将无法从此处保存。' : ''}',
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
          top: DesignTokens.spacingSm,
          bottom: DesignTokens.spacingSm,
        ),
        child: Row(
          children: [
            ListIconBadge(
              icon: row['kind'] == 'directory'
                  ? LucideIcons.folder
                  : LucideIcons.file,
              backgroundColor: DesignTokens.colorListIconAmber,
            ),
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
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '$direction · '),
                        TextSpan(
                          text:
                              '$status${active && progress != null ? ' ${(progress * 100).floor()}%' : ''}',
                          style:
                              [
                                'failed',
                                'partialFailure',
                                'partial',
                              ].contains(row['status'])
                              ? TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                )
                              : null,
                        ),
                      ],
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (active) ...[
                    const SizedBox(height: DesignTokens.spacingXs),
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
