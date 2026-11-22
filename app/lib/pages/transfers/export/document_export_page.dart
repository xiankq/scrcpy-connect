import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/core/files/document_operation_notifier.dart';
import 'package:scrcpy_connect/core/files/system_documents.dart';
import 'package:scrcpy_connect/hooks/use_document_picker.dart';
import 'package:scrcpy_connect/hooks/use_transfer_cache_lease.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/utils/formatters.dart';
import 'package:scrcpy_connect/widgets/form_controls.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart' show confirm;
import 'package:scrcpy_connect/widgets/documents/document_conflict_panel.dart';
import 'package:scrcpy_connect/widgets/documents/file_delivery_path.dart';
import 'package:scrcpy_connect/widgets/documents/original_file_header.dart';
import 'package:scrcpy_connect/widgets/documents/system_file_share_form.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class DocumentExportPage extends HookConsumerWidget {
  const DocumentExportPage({
    super.key,
    required this.localPath,
    required this.name,
    required this.kind,
    this.transferId,
    this.partial = false,
    this.title,
    this.onBack,
    this.sourceLabel = '被控设备',
  });
  final String localPath;
  final String name;
  final String kind;
  final String? transferId;
  final bool partial;
  final String sourceLabel;
  final String? title;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heading =
        title ?? (!supportsSystemDocumentSave ? '系统分享原文件' : '保存到系统位置');
    if (!supportsSystemDocumentSave) {
      return PageFrame(
        title: heading,
        titleStyle: Theme.of(context).textTheme.headlineMedium,
        onBack: onBack,
        child: GroupedListView(
          padding: const EdgeInsets.all(DesignTokens.spacingLg),
          children: [
            SystemFileShareForm(
              key: ValueKey('$transferId:$localPath'),
              localPath: localPath,
              name: name,
              kind: kind,
              transferId: transferId,
              sourceLabel: sourceLabel,
            ),
          ],
        ),
      );
    }
    final cacheLease = useTransferCacheLease(ref, transferId);
    final scope = useMemoized(Object.new);
    final provider = documentOperationProvider(
      scope: scope,
      exportSource: DocumentSource(
        sourceId: transferId == null ? 'local' : 'transfer:$transferId',
        localPath: localPath,
        kind: DocumentKind.values.byName(kind),
      ),
    );
    final operation = ref.watch(provider);
    final actions = ref.read(provider.notifier);
    final currentOperation = actions.captureScope();
    useDocumentPicker(ref, actions);
    final reviewedOperation = useState<String?>(null);
    final acknowledgedUnknown =
        operation.recordOperationId != null &&
        reviewedOperation.value == operation.recordOperationId;
    final result = operation.result;
    final status = result?.status.name ?? '';
    final savedCounts = [result?.files, result?.directories, result?.bytes];
    final confirmedEmpty =
        result?.partialDestinationPossible == false &&
        savedCounts.every((count) => count != null && count == 0);
    final hasSavedContent = savedCounts.any(
      (count) => count != null && count > 0,
    );
    final waiting = operation.busy || status == 'pending';
    final unknown =
        result != null &&
        status != 'saved' &&
        status != 'pending' &&
        (result.partialDestinationPossible == true ||
            !['partial', 'cancelled', 'failed'].contains(status));
    final deliveryState = status == 'saved'
        ? FileDeliveryMilestone.complete
        : unknown || status == 'failed' || operation.error != null
        ? FileDeliveryMilestone.attention
        : FileDeliveryMilestone.pending;
    if (transferId != null && (!cacheLease.hasData || cacheLease.hasError)) {
      return PageFrame(
        title: heading,
        titleStyle: Theme.of(context).textTheme.headlineMedium,
        onBack: onBack,
        child: PageChromeBody(
          child: cacheLease.hasError
              ? StateNote(
                  failureMessage(
                    cacheLease.error,
                    fallback: '临时文件已不可用。请从手机重新取回。',
                  ),
                )
              : const Center(child: CircularProgressIndicator.adaptive()),
        ),
      );
    }
    final errors = result?.errors ?? <DocumentIssue>[];
    final leading = <Widget>[
      ContentPanel(
        child: OriginalFileHeader(name: name, kind: kind),
      ),
      const SizedBox(height: DesignTokens.spacingLg),
      ContentPanel(
        child: FileDeliveryPath(
          sourceLabel: sourceLabel,
          staged: true,
          systemState: deliveryState,
        ),
      ),
      const SizedBox(height: DesignTokens.spacingLg),
      if (partial)
        const StateNote(
          '目前只取回了部分文件。保存前请检查还缺哪些文件。',
          icon: LucideIcons.circleAlert,
        ),
      const Text('选择系统位置保存一份。只有系统确认写入完成后，才显示保存成功。本机暂存仍保留。'),
      const SizedBox(height: DesignTokens.spacingLg),
      if (waiting) ...[
        const ContentLoadingIndicator(),
        const StateNote('正在等待系统选择或实际写入结果…'),
        TextButton(
          onPressed: operation.cancelling ? null : actions.cancel,
          child: Text(operation.cancelling ? '正在取消…' : '取消本次保存'),
        ),
        if ((operation.operationId ?? operation.recordOperationId)
            case final owner?)
          DocumentConflictPanel(operationId: owner),
      ],
      if (operation.error != null)
        StateNote(operation.error!, icon: LucideIcons.circleAlert),
      if (operation.refreshing) const StateNote('正在检查这份文件是否已保存…'),
      if (!operation.loaded || status == 'pending' || unknown)
        TextButton(
          onPressed: operation.refreshing ? null : actions.refresh,
          child: const Text('检查保存结果'),
        ),
      if (result != null)
        ContentPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(switch (status) {
                'saved' => '系统已确认保存',
                'partial' =>
                  hasSavedContent
                      ? '部分内容已保存，请核对'
                      : confirmedEmpty
                      ? '本次未保存内容'
                      : '保存未完成，请核对',
                'cancelled' => '已取消选择位置',
                'failed' => '本次保存未开始',
                'pending' => '上次系统保存尚未结束',
                _ => '还没有保存回执',
              }, style: Theme.of(context).textTheme.titleLarge),
              if (status == 'saved') const Text('如保存到了云盘，云端同步结果请在对应应用核对。'),
              if ((result.name ?? '').isNotEmpty)
                Text('系统名称：${(result.name ?? '')}'),
              if (result.files != null && result.directories != null)
                Text(
                  '${result.files} 个文件 · ${result.directories} 个文件夹 · ${bytes(result.bytes)}',
                ),
              if ((result.skipped ?? 0) > 0) Text('跳过 ${result.skipped} 项'),
              if (status == 'partial' || unknown)
                const StateNote('请先在系统文件应用核对实际内容，已有结果不会自动重复写入。'),
              if (result.partialDestinationPossible == true &&
                  status != 'saved')
                const StateNote('系统位置可能已留下部分内容。请在系统文件应用核对；本机暂存未被删除。'),
            ],
          ),
        ),
    ];
    final trailing = <Widget>[
      if (unknown)
        CheckboxListTile(
          value: acknowledgedUnknown,
          onChanged: (v) => reviewedOperation.value = v == true
              ? operation.recordOperationId
              : null,
          title: const Text('我已在系统文件应用核对，仍需重新保存'),
        ),
      if (!waiting && status == 'saved')
        OutlinedButton(
          onPressed: !operation.loaded || operation.refreshing
              ? null
              : () async {
                  if (!await confirm(
                        context,
                        '再保存一份？',
                        '已经保存过这份原件。继续会重新选择系统位置并保存额外副本，不会自动覆盖已有内容。',
                        action: '选择新位置',
                      ) ||
                      !context.mounted ||
                      !currentOperation()) {
                    return;
                  }
                  await actions.export(name, additionalCopy: true);
                },
          child: const Text('再保存一份'),
        ),
    ];
    final action = waiting
        ? null
        : status != 'saved'
        ? FilledButton(
            style: pagePrimaryButtonStyle,
            onPressed:
                !operation.loaded ||
                    operation.refreshing ||
                    (unknown && !acknowledgedUnknown)
                ? null
                : () {
                    final reviewed = acknowledgedUnknown;
                    reviewedOperation.value = null;
                    actions.export(name, reviewed: reviewed);
                  },
            child: Text(result == null ? '选择系统位置并保存' : '重新选择系统位置'),
          )
        : transferId == null
        ? null
        : FilledButton(
            style: pagePrimaryButtonStyle,
            onPressed: () =>
                TransferDetailsRoute(taskId: transferId!).push<void>(context),
            child: const Text('返回传输'),
          );
    return PageFrame(
      title: heading,
      titleStyle: Theme.of(context).textTheme.headlineMedium,
      onBack: onBack,
      bottom: action == null
          ? null
          : Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spacingXs,
              ),
              child: action,
            ),
      child: GroupedListView.builder(
        padding: const EdgeInsets.all(DesignTokens.spacingLg),
        itemCount: leading.length + errors.length + trailing.length,
        itemBuilder: (context, index) {
          if (index < leading.length) return leading[index];
          final errorIndex = index - leading.length;
          if (errorIndex < errors.length) {
            final error = errors[errorIndex];
            return StateNote(
              '${error.path.isEmpty ? '' : '${error.path}\n'}${failureCodeMessage(error.code, fallback: '暂时无法确认保存结果。请先查看保存位置。')}',
              icon: LucideIcons.circleAlert,
            );
          }
          return trailing[errorIndex - errors.length];
        },
      ),
    );
  }
}
