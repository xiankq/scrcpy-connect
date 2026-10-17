import 'package:scrcpy_connect/router/app_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/pages/transfer_details/widgets/conflict_panel.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/transfer_state.dart';
import 'package:scrcpy_connect/services/media_cache_lease.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
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
          final status = value(current, 'status');
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
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    value(current, 'name', '文件传输'),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(statusText(status)),
                  const SizedBox(height: 8),
                  Text(
                    '${value(current, 'sourceLabel', value(current, 'source'))}\n→ ${value(current, 'destinationLabel', value(current, 'destination'))}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  if (current['kind'] == 'directory' && status == 'finalizing')
                    const StateNote('目录结构已建立，仍在核验所选内容。请等待批次实际结果。'),
                  if (value(current, 'exportReason').isNotEmpty)
                    StateNote(value(current, 'exportReason')),
                  if (cacheLease.hasError)
                    StateNote('暂存原件不可用：${cacheLease.error}。请重新取回原件后再保存或分享。'),
                  for (final item in objects(current['items']))
                    ActionRow(
                      icon: item['status'] == 'completed'
                          ? LucideIcons.circleCheck
                          : LucideIcons.circleAlert,
                      title: value(item, 'name'),
                      subtitle:
                          '${statusText(value(item, 'status'))}${value(item, 'error').isEmpty ? '' : ' · ${value(item, 'error')}'}',
                      color: item['status'] == 'completed'
                          ? ConnectTokens.mint
                          : ConnectTokens.amber,
                    ),
                  if (status == 'conflict')
                    ConflictPanel(
                      onResolve: (policy, all) async {
                        await perform(
                          context,
                          controller,
                          'transfers.resolve',
                          {
                            'transferId': current['id'],
                            'policy': policy,
                            'applyToAll': all,
                          },
                        );
                        refresh();
                      },
                    ),
                  if (current['canCancel'] == true)
                    OutlinedButton(
                      onPressed: () async {
                        if (await confirm(
                              context,
                              '取消未完成的传输？',
                              '已完成内容会保留。未完成的临时项将按实际情况清理，不会作为完整文件保存。',
                              action: '取消传输',
                            ) &&
                            context.mounted) {
                          await perform(
                            context,
                            controller,
                            'transfers.cancel',
                            {'transferId': current['id']},
                          );
                          refresh();
                        }
                      },
                      child: const Text('取消传输'),
                    ),
                  if (current['canRestart'] == true)
                    FilledButton(
                      onPressed: () async {
                        if (await confirm(
                              context,
                              '从头重新传输？',
                              '本次将从 0 开始，并重新检查来源与目标。来源已经变化时，需要重新确认，已有内容不会作为续传进度。',
                              action: '重新传输',
                            ) &&
                            context.mounted) {
                          await perform(
                            context,
                            controller,
                            'transfers.resume',
                            {'transferId': current['id'], 'restart': true},
                          );
                          refresh();
                        }
                      },
                      child: const Text('重新传输'),
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
                          taskId: value(task, 'id', value(task, 'transferId')),
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
                        icon: const Icon(LucideIcons.externalLink, size: 18),
                        label: const Text('用本机应用打开'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () async {
                          try {
                            if (current['destinationScope'] == 'privateCache') {
                              await controller.request('media.cache.retain', {
                                'localPath': value(current, 'localPath'),
                              });
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
                        icon: const Icon(LucideIcons.share2, size: 18),
                        label: const Text('系统分享'),
                      ),
                    ],
                  ],
                  if (['failed', 'partial', 'paused'].contains(status))
                    StateNote(
                      value(
                        current,
                        'error',
                        '请核对逐项结果。已完成与未完成内容分别保留，不会自动重复有未知结果的操作。',
                      ),
                      icon: LucideIcons.circleAlert,
                    ),
                  const SizedBox(height: 16),
                  TextButton(onPressed: refresh, child: const Text('重新检查结果')),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
