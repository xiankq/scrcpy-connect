import 'dart:async';
import 'dart:io';

import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:scrcpy_connect/core/files/transfer_query_provider.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/hooks/use_transfer_cache_lease.dart';
import 'package:scrcpy_connect/pages/transfers/details/widgets/conflict_panel.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/utils/formatters.dart';
import 'package:scrcpy_connect/widgets/async_content.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/documents/document_export_form.dart';
import 'package:scrcpy_connect/widgets/documents/file_delivery_path.dart';
import 'package:scrcpy_connect/widgets/documents/original_file_header.dart';
import 'package:scrcpy_connect/widgets/documents/open_prepared_file.dart';
import 'package:scrcpy_connect/widgets/documents/system_file_share_form.dart';
import 'package:scrcpy_connect/widgets/file_transfer_labels.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/media_cache_blocker.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

/// 准备原件时任务身份保持不变，缓存下载完成后才作为明确系统交付的来源。
class ReceiveContentPage extends HookConsumerWidget {
  const ReceiveContentPage({
    super.key,
    required this.task,
    this.share = false,
    this.openAfterTransfer = false,
  });
  final bool openAfterTransfer;
  final FileTransferSnapshot task;
  final bool share;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(deviceListProvider).devices;
    final provider = transferDetailsProvider(task.id);
    final query = ref.watch(provider);
    final source = ref.watch(fileTransfersProvider);
    Future<void> refresh() => ref
        .refresh(provider.future)
        .then<void>((_) {}, onError: (Object _, StackTrace _) {});
    final owner = useMemoized(Object.new, [source, task.id]);
    final currentOwner = useRef(owner)..value = owner;
    final pageContext = context;
    bool ownsView() =>
        pageContext.mounted && identical(currentOwner.value, owner);
    final busy = useState(false);
    final shareResult = useState<String?>(null);
    final shareReviewed = useState(false);
    final taskId = task.id;
    final autoDeliveryAttempted = useMemoized(() => <String>{}, [
      source,
      taskId,
    ]);
    useEffect(() {
      busy.value = false;
      shareResult.value = null;
      shareReviewed.value = false;
      return null;
    }, [owner]);
    return PageFrame(
      title: openAfterTransfer
          ? '取回文件'
          : share && supportsSystemFileShare
          ? '分享原文件'
          : '保存原文件',
      child: AsyncContent<FileTransferSnapshot>(
        loading: query.isLoading,
        data: query.value,
        error: query.error,
        onRefresh: refresh,
        emptyTitle: '暂时无法读取原文件',
        failure: '请检查传输记录，确认文件是否已取回。',
        builder: (context, data) {
          final current = transferView(devices, data);
          return HookConsumer(
            key: ValueKey((source, task.id)),
            builder: (context, ref, _) {
              final cacheLease = useTransferCacheLease(
                ref,
                current.canExport || current.status.isActive ? taskId : null,
              );
              final ready =
                  (!query.isLoading && !query.hasError && query.hasValue) &&
                  current.canExport &&
                  cacheLease.hasData &&
                  !cacheLease.hasError &&
                  (current.localPath ?? '').isNotEmpty;
              final localPath = (current.localPath ?? '');
              Future<void> deliverShare() async {
                if (busy.value || !ready || current.kind == .directory) {
                  return;
                }
                busy.value = true;
                shareReviewed.value = false;
                try {
                  final result = await sharePreparedFile(
                    context,
                    ref,
                    localPath,
                  );
                  if (ownsView()) shareResult.value = result;
                } catch (error) {
                  if (ownsView()) {
                    shareResult.value = failureMessage(
                      error,
                      fallback: '暂时无法确认分享是否完成。请先查看接收文件的应用。',
                    );
                  }
                } finally {
                  if (ownsView()) busy.value = false;
                }
              }

              Future<void> openFile() async {
                if (busy.value || !ready) return;
                busy.value = true;
                try {
                  await performAction(
                    context,
                    () => openPreparedFile(context, ref, localPath),
                  );
                } finally {
                  if (ownsView()) busy.value = false;
                }
              }

              final route = ModalRoute.of(context);
              final owned =
                  data.id == taskId &&
                  data.deviceId == task.deviceId &&
                  data.direction == .pull &&
                  data.destinationScope == .privateCache;
              useEffect(
                () {
                  if (!owned ||
                      !ready ||
                      (!openAfterTransfer &&
                          (!share || !supportsSystemFileShare)) ||
                      current.kind == .directory ||
                      route?.isCurrent == false ||
                      autoDeliveryAttempted.contains(taskId)) {
                    return null;
                  }
                  var active = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!active ||
                        !context.mounted ||
                        route?.isCurrent == false ||
                        !autoDeliveryAttempted.add(taskId)) {
                      return;
                    }
                    unawaited(openAfterTransfer ? openFile() : deliverShare());
                  });
                  return () => active = false;
                },
                [
                  owned,
                  ready,
                  share,
                  openAfterTransfer,
                  taskId,
                  route?.isCurrent,
                ],
              );
              if (data.id != taskId ||
                  data.deviceId != task.deviceId ||
                  data.direction != .pull ||
                  data.destinationScope != .privateCache) {
                return const EmptyContent(
                  icon: LucideIcons.fileWarning,
                  title: '原文件归属需要核对',
                  message: '当前记录不是这次取回的本机暂存。请返回原设备重新选择。',
                );
              }
              if (ready &&
                  !openAfterTransfer &&
                  supportsSystemDocumentSave &&
                  (!share || !supportsSystemFileShare)) {
                return DocumentExportForm(
                  key: ValueKey('$taskId:$localPath'),
                  localPath: localPath,
                  transferId: taskId,
                  name: current.name,
                  kind: current.kind == .directory ? 'directory' : 'file',
                  sourceLabel: (current.sourceLabel ?? '被控设备'),
                );
              }
              final status = current.status;
              final completed = current.completedBytes ?? current.transferred;
              final total = current.totalBytes ?? current.total ?? 0;
              final pending = <FileTransferStatus>[
                .queued,
                .running,
                .finalizing,
                .cancelling,
              ].contains(status);
              return GroupedListView(
                padding: const EdgeInsets.all(DesignTokens.spacingMd),
                children: [
                  OriginalFileHeader(
                    name: current.name,
                    kind: current.kind.name,
                  ),
                  const SizedBox(height: DesignTokens.spacingLg),
                  ContentPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          share ? AppIcons.share : AppIcons.download,
                          color: ConnectTokens.accent(
                            context,
                            ConnectTokens.amber,
                          ),
                        ),
                        const SizedBox(height: DesignTokens.spacingSm),
                        Text(
                          pending
                              ? '正在准备原文件'
                              : ready
                              ? '原文件已准备好'
                              : statusText(status.name),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: DesignTokens.spacingSm),
                        FileDeliveryPath(
                          sourceLabel: (current.sourceLabel ?? '被控设备'),
                          systemLabel:
                              share && supportsSystemFileShare ||
                                  !supportsSystemDocumentSave
                              ? '接收应用'
                              : '系统副本',
                          staged: ready,
                          systemState: switch (status) {
                            .failed ||
                            .interrupted ||
                            .cancelled => FileDeliveryMilestone.attention,
                            .completed when ready =>
                              FileDeliveryMilestone.pending,
                            _ => FileDeliveryMilestone.pending,
                          },
                        ),
                        if (pending) ...[
                          const SizedBox(height: DesignTokens.spacingSm),
                          const Text('原文件完整取回前，不会保存或分享不完整内容。'),
                        ],
                      ],
                    ),
                  ),
                  if (pending) ...[
                    const SizedBox(height: DesignTokens.spacingMd),
                    if (total > 0)
                      LinearProgressIndicator(
                        value: (completed / total).clamp(0, 1).toDouble(),
                      )
                    else
                      const ContentLoadingIndicator(),
                    const SizedBox(height: DesignTokens.spacingXs),
                    Text(
                      '${bytes(completed)} / ${total > 0 ? bytes(total) : '大小未知'}',
                    ),
                    const StateNote('离开本页后传输可继续，在传输中心查看。'),
                  ],
                  if (status == .conflict)
                    ConflictPanel(
                      enabled:
                          (!query.isLoading &&
                          !query.hasError &&
                          query.hasValue),
                      transfer: transferView(devices, current),
                      onResolve: (policy, all) async {
                        await performAction(
                          context,
                          () => source.resolveConflict(
                            taskId,
                            policy,
                            applyToAll: all,
                          ),
                        );
                        refresh();
                      },
                    ),
                  if (current.canCancel)
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
                              await performAction(
                                context,
                                () => source.cancelTransfer(
                                  FileTransferTarget.task(taskId),
                                ),
                              );
                              if (context.mounted) {
                                busy.value = false;
                                refresh();
                              }
                            },
                      child: const Text('取消本次传输'),
                    ),
                  if (!pending && !ready && status != .conflict)
                    StateNote(
                      cacheLease.hasError
                          ? failureMessage(
                              cacheLease.error,
                              fallback: '临时文件已不可用。请从手机重新取回。',
                            )
                          : transferIssueMessage(current),
                    ),
                  if (!pending &&
                      !ready &&
                      isMediaCacheAdmissionFailure((current.errorCode ?? '')))
                    const MediaCacheBlocker(),
                  if (ready && openAfterTransfer && current.kind != .directory)
                    FilledButton.icon(
                      onPressed: busy.value ? null : openFile,
                      icon: const Icon(LucideIcons.externalLink),
                      label: const Text('使用本机应用打开'),
                    ),
                  if (ready &&
                      !openAfterTransfer &&
                      supportsSystemFileShare &&
                      (share || !supportsSystemDocumentSave) &&
                      current.kind != .directory) ...[
                    if (shareResult.value != null)
                      StateNote(shareResult.value!),
                    if (shareResult.value != null)
                      CheckboxListTile(
                        value: shareReviewed.value,
                        onChanged: busy.value
                            ? null
                            : (value) => shareReviewed.value = value == true,
                        title: const Text('我已在接收应用核对，仍需再次分享'),
                      ),
                    FilledButton.icon(
                      onPressed:
                          busy.value ||
                              shareResult.value != null && !shareReviewed.value
                          ? null
                          : deliverShare,
                      icon: const Icon(AppIcons.share),
                      label: Text(
                        shareResult.value == null ? '交给系统分享' : '重新打开系统分享',
                      ),
                    ),
                  ],
                  if (ready &&
                      !openAfterTransfer &&
                      supportsSystemFileShare &&
                      (share || !supportsSystemDocumentSave) &&
                      current.kind == .directory)
                    StateNote(
                      Platform.isAndroid
                          ? '文件夹请先保存到系统位置，再从文件应用中选择需要分享的内容。'
                          : '当前主控尚不支持将暂存文件夹保存到系统位置，请在手机上处理或从文件页选择其他传输方式。',
                    ),
                  const SizedBox(height: DesignTokens.spacingMd),
                  TextButton(
                    onPressed: () =>
                        TransferDetailsRoute(taskId: taskId)
                            .push<void>(context),
                    child: const Text('查看本次传输详情'),
                  ),
                  TextButton(onPressed: refresh, child: const Text('刷新文件状态')),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
