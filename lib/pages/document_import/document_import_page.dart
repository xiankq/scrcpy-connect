import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/document_operation.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class DocumentImportPage extends HookWidget {
  const DocumentImportPage({
    super.key,
    required this.controller,
    required this.device,
    required this.destination,
    required this.onSubmitted,
  });
  final AppController controller;
  final Json device;
  final String destination;
  final VoidCallback onSubmitted;
  @override
  Widget build(BuildContext context) {
    final operation = useDocumentOperation(controller);
    final reviewed = useState(false);
    final sending = useState(false);
    final result = operation.result;
    final partial = result?['status'] == 'partial';
    final imported = ['imported', 'partial'].contains(result?['status']);
    final name = value(result ?? {}, 'name');
    final safeName =
        name.isNotEmpty &&
        !name.contains('/') &&
        name != '.' &&
        name != '..' &&
        !name.contains('\u0000');
    final usable =
        imported &&
        safeName &&
        value(result ?? {}, 'localPath').isNotEmpty &&
        ((num.tryParse('${result?['files']}') ?? 0) +
                (num.tryParse('${result?['directories']}') ?? 0) >
            0);
    final target =
        '${destination.endsWith('/') ? destination.substring(0, destination.length - 1) : destination}/$name';
    return PageFrame(
      title: '发送本机文件夹',
      child: GroupedListView(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        children: [
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: FeatureIcon(
              LucideIcons.folderUp,
              color: ConnectTokens.amber,

              size: DesignTokens.componentFeatureIconSize,
            ),
          ),
          const SizedBox(height: DesignTokens.spacingMd),
          Text('选择要发送的文件夹', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: DesignTokens.spacingSm),
          const Text('系统只授权读取你选择的文件夹。内容先取回本机暂存，核对后再发送到设备；保留目录结构与空目录。'),
          const SizedBox(height: DesignTokens.spacingMd),
          if (operation.busy) ...[
            const LinearProgressIndicator(),
            const StateNote('正在等待系统选择或读取实际内容…'),
            TextButton(
              onPressed: operation.cancelling ? null : operation.cancel,
              child: Text(operation.cancelling ? '正在取消…' : '取消本次读取'),
            ),
          ],
          if (operation.error != null)
            StateNote(operation.error!, icon: LucideIcons.circleAlert),
          if (result != null)
            ContentPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    partial
                        ? '部分内容已取回，请先核对'
                        : result['status'] == 'imported'
                        ? '已取回本机暂存，尚未发送'
                        : result['status'] == 'cancelled'
                        ? '本次选择已取消'
                        : '尚未取得可发送内容',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (name.isNotEmpty) Text(name),
                  if (result['files'] is num && result['directories'] is num)
                    Text(
                      '${result['files']} 个文件 · ${result['directories']} 个文件夹 · ${bytes(result['bytes'])}',
                    ),
                  if (result['skipped'] is num &&
                      (result['skipped'] as num) > 0)
                    Text('跳过 ${result['skipped']} 项'),
                  for (final error in objects(result['errors']))
                    StateNote(
                      '${value(error, 'path')}：${value(error, 'message', '系统无法读取此项')}',
                      icon: LucideIcons.circleAlert,
                    ),
                  if (usable) Text('发送位置：$target'),
                  if (imported && !usable)
                    const StateNote('系统未提供有效的文件夹名称、路径或可发送内容，请重新选择。'),
                ],
              ),
            ),
          if (partial && usable)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: reviewed.value,
              onChanged: sending.value
                  ? null
                  : (v) => reviewed.value = v ?? false,
              title: const Text('我已核对，只发送已取回的内容'),
            ),
          if (usable)
            FilledButton(
              onPressed: sending.value || partial && !reviewed.value
                  ? null
                  : () async {
                      if (!await confirm(
                            context,
                            '发送此文件夹？',
                            '将“$name”发送到 ${deviceName(device)} 的 $target。同名内容逐项确认，不会自动覆盖。',
                            action: '确认发送',
                          ) ||
                          !context.mounted) {
                        return;
                      }
                      sending.value = true;
                      final response = await perform(
                        context,
                        controller,
                        'files.push',
                        {
                          'deviceId': device['id'],
                          'items': [
                            {
                              'source': result!['localPath'],
                              'destination': target,
                            },
                          ],
                          'conflict': 'ask',
                        },
                      );
                      if (context.mounted) {
                        sending.value = false;
                        if (response != null) onSubmitted();
                      }
                    },
              child: Text(
                sending.value
                    ? '正在建立传输…'
                    : partial
                    ? '发送已核对的内容'
                    : '发送此文件夹',
              ),
            ),
          if (!operation.busy)
            OutlinedButton(
              onPressed: sending.value
                  ? null
                  : () {
                      reviewed.value = false;
                      operation.run('documents.importDirectory', {});
                    },
              child: Text(result == null ? '选择系统文件夹' : '重新选择文件夹'),
            ),
        ],
      ),
    );
  }
}
