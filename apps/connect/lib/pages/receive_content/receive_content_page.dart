import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/pages/document_export/widgets/document_export_form.dart';
import 'package:scrcpy_connect/pages/transfer_details/widgets/conflict_panel.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/transfer_state.dart';
import 'package:scrcpy_connect/services/media_cache_lease.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/original_file_header.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:share_plus/share_plus.dart';

/// The task identity stays fixed while the selected original is prepared.
/// A completed cache download is the source of an explicit system handoff.
class ReceiveContentPage extends HookConsumerWidget {
  const ReceiveContentPage({
    super.key,
    required this.controller,
    required this.task,
    this.share = false,
  });
  final AppController controller;
  final Json task;
  final bool share;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revision = ref.watch(
      appControllerProvider.select((state) => state.eventRevision),
    );
    final busy = useState(false);
    final shareResult = useState<String?>(null);
    final taskId = value(task, 'id', value(task, 'transferId'));
    final source = transferView(controller, task);
    return PageFrame(
      title: share ? '分享原文件' : '保存原文件',
      subtitle: value(source, 'sourceLabel'),
      child: CommandView(
        controller: controller,
        command: 'transfers.get',
        params: {'transferId': taskId},
        refreshKey: revision,
        emptyTitle: '暂时无法核验原文件',
        builder: (context, data, refresh) {
          final current = transferView(controller, data);
          return HookBuilder(
            builder: (context) {
              final cacheLease = useTransferCacheLease(
                controller,
                current['canExport'] == true ||
                        [
                          'queued',
                          'running',
                          'finalizing',
                          'cancelling',
                          'conflict',
                        ].contains(current['status'])
                    ? taskId
                    : null,
              );
              final ready =
                  current['canExport'] == true &&
                  cacheLease.hasData &&
                  !cacheLease.hasError &&
                  value(current, 'localPath').isNotEmpty;
              final localPath = value(current, 'localPath');
              if (value(data, 'id', value(data, 'transferId')) != taskId ||
                  data['deviceId'] != task['deviceId'] ||
                  data['direction'] != 'pull' ||
                  data['destinationScope'] != 'privateCache') {
                return const EmptyContent(
                  icon: LucideIcons.fileWarning,
                  title: '原文件归属需要核对',
                  message: '当前记录不是这次取回的本机暂存。请返回原设备重新选择。',
                );
              }
              if (ready && !share) {
                return DocumentExportForm(
                  key: ValueKey('$taskId:$localPath'),
                  controller: controller,
                  localPath: localPath,
                  transferId: taskId,
                  name: value(current, 'name', '原文件'),
                  kind: current['kind'] == 'directory' ? 'directory' : 'file',
                );
              }
              final status = value(current, 'status');
              final completed =
                  num.tryParse('${current['completedBytes']}') ?? 0;
              final total = num.tryParse('${current['totalBytes']}') ?? 0;
              final pending = [
                'queued',
                'running',
                'finalizing',
                'cancelling',
              ].contains(status);
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  OriginalFileHeader(
                    name: value(current, 'name', '原文件'),
                    kind: value(current, 'kind', 'file'),
                    subtitle: '来源：${value(source, 'sourceLabel')}',
                  ),
                  const SizedBox(height: 24),
                  ContentPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          share ? LucideIcons.share2 : LucideIcons.download,
                          color: ConnectTokens.accent(
                            context,
                            ConnectTokens.amber,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          pending
                              ? '正在准备原文件'
                              : ready
                              ? '原文件已准备好'
                              : statusText(status),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (pending) ...[
                          const SizedBox(height: 12),
                          const Text('原文件完整取回前，不会保存或分享不完整内容。'),
                        ],
                      ],
                    ),
                  ),
                  if (pending) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: total > 0
                          ? (completed / total).clamp(0, 1).toDouble()
                          : null,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${bytes(completed)} / ${total > 0 ? bytes(total) : '大小待核验'}',
                    ),
                    const StateNote('离开本页后传输可继续，在传输中心查看。'),
                  ],
                  if (status == 'conflict')
                    ConflictPanel(
                      onResolve: (policy, all) async {
                        await perform(
                          context,
                          controller,
                          'transfers.resolve',
                          {
                            'transferId': taskId,
                            'policy': policy,
                            'applyToAll': all,
                          },
                        );
                        refresh();
                      },
                    ),
                  if (current['canCancel'] == true)
                    OutlinedButton(
                      onPressed: busy.value
                          ? null
                          : () async {
                              if (!await confirm(
                                    context,
                                    '取消准备原文件？',
                                    '只取消本次传输，已完成内容保留；不会删除被控手机上的原文件。',
                                    action: '取消本次传输',
                                  ) ||
                                  !context.mounted) {
                                return;
                              }
                              busy.value = true;
                              await perform(
                                context,
                                controller,
                                'transfers.cancel',
                                {'transferId': taskId},
                              );
                              if (context.mounted) {
                                busy.value = false;
                                refresh();
                              }
                            },
                      child: const Text('取消本次传输'),
                    ),
                  if (!pending && !ready && status != 'conflict')
                    StateNote(
                      cacheLease.hasError
                          ? '无法保留这份暂存：${cacheLease.error}'
                          : value(
                              current,
                              'error',
                              value(
                                current,
                                'exportReason',
                                '原文件尚未完整取回。请在传输详情核对结果；不会自动重新传输。',
                              ),
                            ),
                    ),
                  if (ready && share && current['kind'] != 'directory') ...[
                    const StateNote('将原文件副本交给系统选择的应用。分享面板返回不代表接收应用已经发送或保存。'),
                    if (shareResult.value != null)
                      StateNote(shareResult.value!),
                    FilledButton.icon(
                      onPressed: busy.value
                          ? null
                          : () async {
                              busy.value = true;
                              try {
                                await controller.execute(
                                  InteropCommand.mediaCacheRetain,
                                  {'localPath': localPath},
                                );
                                final result = await SharePlus.instance.share(
                                  ShareParams(files: [XFile(localPath)]),
                                );
                                if (!context.mounted) return;
                                shareResult.value = switch (result.status) {
                                  ShareResultStatus.success =>
                                    '已交给系统选择的应用，请在接收应用核对。',
                                  ShareResultStatus.dismissed =>
                                    '已关闭系统分享，原文件暂存仍保留。',
                                  ShareResultStatus.unavailable =>
                                    '系统没有提供分享结果，请在接收应用核对；不会自动重复分享。',
                                };
                              } catch (error) {
                                if (context.mounted) {
                                  shareResult.value = '系统分享未确认完成：$error';
                                }
                              } finally {
                                if (context.mounted) busy.value = false;
                              }
                            },
                      icon: const Icon(LucideIcons.share2),
                      label: Text(
                        shareResult.value == null ? '交给系统分享' : '重新打开系统分享',
                      ),
                    ),
                  ],
                  if (ready && share && current['kind'] == 'directory')
                    const StateNote('文件夹请先保存到系统位置，再从文件应用中选择需要分享的内容。'),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () =>
                        TransferDetailsRoute(taskId: taskId)
                            .push<void>(context),
                    child: const Text('查看本次传输详情'),
                  ),
                  TextButton(onPressed: refresh, child: const Text('重新核验原文件')),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
