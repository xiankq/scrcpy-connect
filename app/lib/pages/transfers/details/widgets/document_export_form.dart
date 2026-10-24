import 'package:scrcpy_connect/presentation/formatters.dart';
import 'package:scrcpy_connect/application/transport/json_readers.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/application/app_controller.dart';
import 'package:scrcpy_connect/presentation/document_operation_controller.dart';
import 'package:scrcpy_connect/media/media_cache_lease.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:scrcpy_connect/widgets/original_file_header.dart';
import 'package:scrcpy_connect/pages/transfers/details/widgets/file_delivery_path.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart' show confirm;
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'document_conflict_panel.dart';

class DocumentExportForm extends HookWidget {
  const DocumentExportForm({
    super.key,
    required this.controller,
    required this.localPath,
    required this.name,
    required this.kind,
    this.transferId,
    this.partial = false,
    this.sourceLabel = '被控设备',
  });
  final AppController controller;
  final String localPath;
  final String name;
  final String kind;
  final String? transferId;
  final bool partial;
  final String sourceLabel;
  @override
  Widget build(BuildContext context) {
    final cacheLease = useTransferCacheLease(controller, transferId);
    final operation = useDocumentOperationController(
      controller,
      exportSource: {
        'sourceId': transferId == null ? 'local' : 'transfer:$transferId',
        'localPath': localPath,
        'kind': kind,
      },
    );
    final reviewedOperation = useState<String?>(null);
    final acknowledgedUnknown =
        operation.recordOperationId != null &&
        reviewedOperation.value == operation.recordOperationId;
    final result = operation.result;
    final status = value(result ?? {}, 'status');
    final savedCounts = [
      result?['files'],
      result?['directories'],
      result?['bytes'],
    ];
    final confirmedEmpty =
        result?['partialDestinationPossible'] == false &&
        savedCounts.every((count) => count is num && count == 0);
    final hasSavedContent = savedCounts.any(
      (count) => count is num && count > 0,
    );
    final waiting = operation.busy || status == 'pending';
    final unknown =
        result != null &&
        status != 'saved' &&
        status != 'pending' &&
        (result['partialDestinationPossible'] == true ||
            !['partial', 'cancelled', 'failed'].contains(status));
    final deliveryState = status == 'saved'
        ? FileDeliveryMilestone.complete
        : unknown || status == 'failed' || operation.error != null
        ? FileDeliveryMilestone.attention
        : FileDeliveryMilestone.pending;
    if (transferId != null && (!cacheLease.hasData || cacheLease.hasError)) {
      return cacheLease.hasError
          ? StateNote('无法保留这份暂存：${cacheLease.error}。请返回原设备重新取回。')
          : const Center(child: CircularProgressIndicator.adaptive());
    }
    final errors = objects(result?['errors']);
    final leading = <Widget>[
      OriginalFileHeader(name: name, kind: kind),
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
          '这是已核验但不完整的本机暂存。请核对缺失项目，系统保存不会补齐尚未取回的内容。',
          icon: LucideIcons.circleAlert,
        ),
      const Text('选择系统位置保存一份。只有系统确认写入完成后，才显示保存成功。本机暂存仍保留。'),
      const SizedBox(height: DesignTokens.spacingLg),
      if (waiting) ...[
        const LinearProgressIndicator(),
        const StateNote('正在等待系统选择或实际写入结果…'),
        TextButton(
          onPressed: operation.cancelling ? null : operation.cancel,
          child: Text(operation.cancelling ? '正在取消…' : '取消本次保存'),
        ),
        if ((operation.operationId ?? operation.recordOperationId)
            case final owner?)
          DocumentConflictPanel(controller: controller, operationId: owner),
      ],
      if (operation.error != null)
        StateNote(operation.error!, icon: LucideIcons.circleAlert),
      if (operation.refreshing) const StateNote('正在核验这份原件的系统保存记录…'),
      if (!operation.loaded || status == 'pending' || unknown)
        TextButton(
          onPressed: operation.refreshing ? null : operation.refresh,
          child: const Text('重新核验系统保存'),
        ),
      if (result != null)
        ContentPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(switch (status) {
                'saved' => '已保存到系统位置',
                'partial' =>
                  hasSavedContent
                      ? '部分内容已保存，请核对'
                      : confirmedEmpty
                      ? '本次未保存内容'
                      : '保存未完成，请核对',
                'cancelled' => '本次系统保存已取消',
                'failed' => '本次保存未开始',
                'pending' => '上次系统保存尚未结束',
                _ => '系统保存结果待核对',
              }, style: Theme.of(context).textTheme.titleLarge),
              if (status == 'saved') const Text('如保存到了云盘，云端同步结果请在对应应用核对。'),
              if (value(result, 'name').isNotEmpty)
                Text('系统名称：${value(result, 'name')}'),
              if (result['files'] is num && result['directories'] is num)
                Text(
                  '${result['files']} 个文件 · ${result['directories']} 个文件夹 · ${bytes(result['bytes'])}',
                ),
              if (result['skipped'] is num && (result['skipped'] as num) > 0)
                Text('跳过 ${result['skipped']} 项'),
              if (status == 'partial' || unknown)
                const StateNote('请先在系统文件应用核对实际内容，已有结果不会自动重复写入。'),
              if (result['partialDestinationPossible'] == true &&
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
      if (!waiting && status != 'saved')
        FilledButton(
          onPressed:
              !operation.loaded ||
                  operation.refreshing ||
                  (unknown && !acknowledgedUnknown)
              ? null
              : () {
                  final reviewed = acknowledgedUnknown;
                  reviewedOperation.value = null;
                  operation.run('documents.export', {
                    'localPath': localPath,
                    'name': name,
                    'kind': kind,
                    'conflict': 'ask',
                  }, reviewed: reviewed);
                },
          child: Text(result == null ? '选择系统位置并保存' : '重新选择系统位置'),
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
                      !context.mounted) {
                    return;
                  }
                  await operation.run('documents.export', {
                    'localPath': localPath,
                    'name': name,
                    'kind': kind,
                    'conflict': 'ask',
                  }, additionalCopy: true);
                },
          child: const Text('再保存一份'),
        ),
    ];
    return GroupedListView.builder(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      itemCount: leading.length + errors.length + trailing.length,
      itemBuilder: (context, index) {
        if (index < leading.length) return leading[index];
        final errorIndex = index - leading.length;
        if (errorIndex < errors.length) {
          final error = errors[errorIndex];
          return StateNote(
            '${value(error, 'path')}：${value(error, 'message', '系统尚未确认结果')}',
            icon: LucideIcons.circleAlert,
          );
        }
        return trailing[errorIndex - errors.length];
      },
    );
  }
}
