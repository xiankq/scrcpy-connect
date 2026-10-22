import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/pages/transfers/details/widgets/conflict_panel.dart';
import 'package:scrcpy_connect/pages/transfers/details/widgets/transfer_result_row.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/transfer_state.dart';
import 'package:scrcpy_connect/services/media_cache_lease.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

class TransferDetailsPage extends HookConsumerWidget {
  const TransferDetailsPage({
    super.key,
    required this.controller,
    required this.task,
  });
  final AppController controller;
  final Json task;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appEventRevision = ref.watch(
      appControllerProvider.select((state) => state.eventRevision),
    );
    final revision = useState(0);
    return PageFrame(
      title: '传输详情',
      child: CommandView(
        refreshKey: '$appEventRevision:${revision.value}',
        controller: controller,
        command: 'transfers.get',
        params: {'transferId': task['id']},
        emptyTitle: '暂时无法读取传输结果',
        builder: (context, data, refresh) {
          final current = transferView(controller, {...task, ...data});
          final rawItems = objects(current['items']);
          final items = rawItems.isEmpty ? [current] : rawItems;
          final itemCount =
              num.tryParse('${current['itemCount']}')?.toInt() ?? items.length;
          // A child item keeps its own result and retry entry; only the batch
          // representative shows the open list of every item.
          final batch = itemCount > 1 && value(current, 'parentId').isEmpty;
          final summary = jsonObject(current['batch']);
          final status = batch
              ? value(summary, 'status', value(current, 'status'))
              : value(current, 'status');
          final canCancel = batch
              ? summary['canCancel'] == true
              : current['canCancel'] == true;
          final conflictItem = batch
              ? items.where((item) => item['status'] == 'conflict').firstOrNull
              : current['status'] == 'conflict'
              ? current
              : null;
          final visibleItems = batch ? items : const <Json>[];
          final remoteDevice = current['direction'] == 'push'
              ? value(current, 'destinationLabel', '设备')
              : value(current, 'sourceLabel', '设备');
          return HookBuilder(
            builder: (context) {
              final cacheLease = useTransferCacheLease(
                controller,
                current['destinationScope'] == 'privateCache' &&
                        (current['canExport'] == true ||
                            [
                              'queued',
                              'running',
                              'finalizing',
                              'cancelling',
                              'conflict',
                            ].contains(status))
                    ? value(current, 'id', value(current, 'transferId'))
                    : null,
              );
              final leading = <Widget>[
                Text(
                  '${value(current, 'name', '文件传输')}'
                  '${batch ? ' · $itemCount 项' : ''}',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: DesignTokens.spacingSm),
                Text(
                  statusText(status),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: DesignTokens.spacingXs),
                Text(
                  transferDetailDirection(current, remoteDevice),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: DesignTokens.spacingMd),
                if (current['kind'] == 'directory' &&
                    value(current, 'status') == 'finalizing')
                  const StateNote('目录结构已建立，仍在核验所选内容。请等待批次实际结果。'),
                if (value(current, 'exportReason').isNotEmpty)
                  StateNote(value(current, 'exportReason')),
                if (cacheLease.hasError)
                  StateNote('暂存原件不可用：${cacheLease.error}。请重新取回原件后再保存或分享。'),
              ];
              final trailing = <Widget>[
                if (conflictItem != null)
                  ConflictPanel(
                    key: ValueKey((
                      'transfer-conflict',
                      value(conflictItem, 'id'),
                    )),
                    transfer: transferView(controller, {
                      ...conflictItem,
                      'deviceId':
                          conflictItem['deviceId'] ?? current['deviceId'],
                      'direction':
                          conflictItem['direction'] ?? current['direction'],
                      'destinationScope':
                          conflictItem['destinationScope'] ??
                          current['destinationScope'],
                    }),
                    onResolve: (policy, all) async {
                      await perform(context, controller, 'transfers.resolve', {
                        'transferId': conflictItem['id'],
                        'policy': policy,
                        'applyToAll': all,
                      });
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
                        await perform(
                          context,
                          controller,
                          'transfers.cancel',
                          batch
                              ? {'batchId': value(summary, 'batchId')}
                              : {'transferId': current['id']},
                        );
                        refresh();
                      }
                    },
                    child: Text(batch ? '取消剩余未完成项' : '取消传输'),
                  ),
                if (!batch && current['canRestart'] == true)
                  FilledButton(
                    onPressed: () async {
                      if (await confirm(
                            context,
                            '从头重新传输？',
                            '本次将从 0 开始，并重新检查来源与目标。来源已经变化时，需要重新确认，已有内容不会作为续传进度。',
                            action: '重新传输',
                          ) &&
                          context.mounted) {
                        await perform(context, controller, 'transfers.resume', {
                          'transferId': current['id'],
                          'restart': true,
                        });
                        refresh();
                      }
                    },
                    child: const Text('重新传输'),
                  )
                else if (batch &&
                    [
                      'partialFailure',
                      'interrupted',
                      'cancelled',
                    ].contains(status))
                  const StateNote(
                    '批次不会整体重放。请在逐项结果中打开要重试的项，确认来源和目标后单独重新传输。',
                    icon: LucideIcons.info,
                  ),
                if (batch && status == 'completedWithSkips')
                  const StateNote(
                    '部分内容因符号链接或特殊文件被跳过，未作为完整原件传输。',
                    icon: LucideIcons.info,
                  ),
                if (current['canExport'] == true &&
                    (current['destinationScope'] != 'privateCache' ||
                        cacheLease.hasData && !cacheLease.hasError) &&
                    value(current, 'localPath').isNotEmpty) ...[
                  StateNote(
                    current['destinationScope'] == 'privateCache'
                        ? '已取回本机暂存，尚未保存到系统位置。系统可能清理暂存内容。'
                        : '已保存至 ${value(current, 'localPath')}',
                  ),
                  if (Platform.isAndroid &&
                      current['destinationScope'] == 'privateCache')
                    FilledButton.icon(
                      onPressed: () => DocumentExportRoute(
                        taskId: value(current, 'id', value(task, 'transferId')),
                        partial: false,
                      ).push<void>(context),
                      icon: const Icon(LucideIcons.folderOutput),
                      label: const Text('保存到系统位置'),
                    ),
                  if (current['kind'] == 'directory')
                    StateNote(
                      current['destinationScope'] == 'privateCache'
                          ? '文件夹结构已取回。保存到系统位置后，可在文件应用中查看。'
                          : '文件夹结构已取回，请在保存位置查看。',
                    ),
                  if (current['kind'] != 'directory') ...[
                    FilledButton.icon(
                      onPressed: () => perform(
                        context,
                        controller,
                        'files.open',
                        {'localPath': value(current, 'localPath')},
                      ),
                      icon: const Icon(
                        LucideIcons.externalLink,
                        size: DesignTokens.componentIconActionSize,
                      ),
                      label: const Text('用本机应用打开'),
                    ),
                    const SizedBox(height: DesignTokens.spacingSm),
                    OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          if (current['destinationScope'] == 'privateCache') {
                            await controller.execute(
                              InteropCommand.mediaCacheRetain,
                              {'localPath': value(current, 'localPath')},
                            );
                          }
                          await SharePlus.instance.share(
                            ShareParams(
                              files: [XFile(value(current, 'localPath'))],
                            ),
                          );
                        } catch (error) {
                          if (context.mounted) {
                            feedback(context, '系统分享失败：$error');
                          }
                        }
                      },
                      icon: const Icon(
                        LucideIcons.share2,
                        size: DesignTokens.componentIconActionSize,
                      ),
                      label: const Text('系统分享'),
                    ),
                  ],
                ],
                if (current['canExportPartial'] == true &&
                    (current['destinationScope'] != 'privateCache' ||
                        cacheLease.hasData && !cacheLease.hasError) &&
                    Platform.isAndroid) ...[
                  StateNote(
                    '这是已核验但不完整的本机暂存。系统保存不会补齐失败、变化或跳过的项目。',
                    icon: LucideIcons.circleAlert,
                  ),
                  FilledButton.icon(
                    onPressed: () => DocumentExportRoute(
                      taskId: value(current, 'id', value(task, 'transferId')),
                      partial: true,
                    ).push<void>(context),
                    icon: const Icon(LucideIcons.folderOutput),
                    label: const Text('保存已取回的部分'),
                  ),
                ],
                if ([
                  'failed',
                  'partial',
                  'interrupted',
                  'paused',
                ].contains(status))
                  StateNote(
                    value(
                      current,
                      'error',
                      '请核对逐项结果。已完成与未完成内容分别保留，不会自动重复有未知结果的操作。',
                    ),
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
                  final item = transferView(controller, {
                    ...rawItem,
                    'deviceId': rawItem['deviceId'] ?? current['deviceId'],
                    'direction': rawItem['direction'] ?? current['direction'],
                    'destinationScope':
                        rawItem['destinationScope'] ??
                        current['destinationScope'],
                  });
                  return TransferResultRow(
                    key: ValueKey((
                      'transfer-item',
                      value(current, 'id'),
                      value(item, 'source'),
                      value(item, 'destination'),
                      row,
                    )),
                    transfer: item,
                    deviceName: remoteDevice,
                    onOpen:
                        rawItem['id'] == null ||
                            value(rawItem, 'id') == value(current, 'id')
                        ? null
                        : () =>
                              TransferDetailsRoute(taskId: value(rawItem, 'id'))
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
