import 'package:flutter/material.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/widgets/documents/system_file_share_form.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class TransferExportActions extends StatelessWidget {
  const TransferExportActions({
    super.key,
    required this.controller,
    required this.current,
    required this.taskId,
    required this.cacheReady,
  });
  final AppController controller;
  final Json current;
  final String taskId;
  final bool cacheReady;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (current['canExport'] == true &&
          (current['destinationScope'] != 'privateCache' || cacheReady) &&
          value(current, 'localPath').isNotEmpty) ...[
        StateNote(
          current['destinationScope'] == 'privateCache'
              ? '已取回本机暂存，尚未保存到系统位置。系统可能清理暂存内容。'
              : '已保存至 ${value(current, 'localPath')}',
        ),
        if (supportsSystemDocumentSave &&
            current['destinationScope'] == 'privateCache')
          FilledButton.icon(
            onPressed: () => DocumentExportRoute(
              taskId: taskId,
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
            onPressed: () => perform(context, controller, 'files.open', {
              'localPath': value(current, 'localPath'),
            }),
            icon: const Icon(
              LucideIcons.externalLink,
              size: DesignTokens.componentIconActionSize,
            ),
            label: const Text('用本机应用打开'),
          ),
          const SizedBox(height: DesignTokens.spacingSm),
          if (supportsSystemFileShare)
            OutlinedButton.icon(
              onPressed: () async {
                try {
                  final result = await sharePreparedFile(
                    context,
                    controller,
                    value(current, 'localPath'),
                  );
                  if (context.mounted) feedback(context, result);
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
          (current['destinationScope'] != 'privateCache' || cacheReady) &&
          supportsSystemDocumentSave) ...[
        StateNote(
          '这是已核验但不完整的本机暂存。系统保存不会补齐失败、变化或跳过的项目。',
          icon: LucideIcons.circleAlert,
        ),
        FilledButton.icon(
          onPressed: () => DocumentExportRoute(
            taskId: taskId,
            partial: true,
          ).push<void>(context),
          icon: const Icon(LucideIcons.folderOutput),
          label: const Text('保存已取回的部分'),
        ),
      ],
    ],
  );
}
