import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/document_operation.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:scrcpy_connect/widgets/original_file_header.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class DocumentExportForm extends HookWidget {
  const DocumentExportForm({
    super.key,
    required this.controller,
    required this.localPath,
    required this.name,
    required this.kind,
    this.partial = false,
  });
  final AppController controller;
  final String localPath;
  final String name;
  final String kind;
  final bool partial;
  @override
  Widget build(BuildContext context) {
    final operation = useDocumentOperation(controller);
    final acknowledgedUnknown = useState(false);
    final result = operation.result;
    final status = value(result ?? {}, 'status');
    final unknown =
        result != null &&
        !['saved', 'partial', 'cancelled', 'failed'].contains(status);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        OriginalFileHeader(name: name, kind: kind, subtitle: '已取回的本机副本'),
        const SizedBox(height: 24),
        if (partial)
          const StateNote(
            '这是已核验但不完整的本机暂存。请核对缺失项目，系统保存不会补齐尚未取回的内容。',
            icon: LucideIcons.circleAlert,
          ),
        const Text('选择系统位置保存一份。只有系统确认写入完成后，才显示保存成功。本机暂存仍保留。'),
        const SizedBox(height: 24),
        if (operation.busy) ...[
          const LinearProgressIndicator(),
          const StateNote('正在等待系统选择或实际写入结果…'),
          TextButton(
            onPressed: operation.cancelling ? null : operation.cancel,
            child: Text(operation.cancelling ? '正在取消…' : '取消本次保存'),
          ),
        ],
        if (operation.error != null)
          StateNote(operation.error!, icon: LucideIcons.circleAlert),
        if (result != null)
          ContentPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(switch (status) {
                  'saved' => '已保存到系统位置',
                  'partial' => '部分内容已保存，请核对',
                  'cancelled' => '本次系统保存已取消',
                  'failed' => '本次保存未开始',
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
                for (final error in objects(result['errors']))
                  StateNote(
                    '${value(error, 'path')}：${value(error, 'message', '系统尚未确认结果')}',
                    icon: LucideIcons.circleAlert,
                  ),
                if (status == 'partial' || unknown)
                  const StateNote('请先在系统文件应用核对实际内容，已有结果不会自动重复写入。'),
                if (result['partialDestinationPossible'] == true &&
                    status != 'saved')
                  const StateNote('系统位置可能已留下部分内容。请在系统文件应用核对；本机暂存未被删除。'),
              ],
            ),
          ),
        if (unknown)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: acknowledgedUnknown.value,
            onChanged: (v) => acknowledgedUnknown.value = v ?? false,
            title: const Text('我已在系统文件应用核对，仍需重新保存'),
          ),
        if (!operation.busy && status != 'saved')
          FilledButton(
            onPressed: unknown && !acknowledgedUnknown.value
                ? null
                : () {
                    acknowledgedUnknown.value = false;
                    operation.run('documents.export', {
                      'localPath': localPath,
                      'name': name,
                      'kind': kind,
                      'conflict': 'ask',
                    });
                  },
            child: Text(result == null ? '选择系统位置并保存' : '重新选择系统位置'),
          ),
      ],
    );
  }
}
