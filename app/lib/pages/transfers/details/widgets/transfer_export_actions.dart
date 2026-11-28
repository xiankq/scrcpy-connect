import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/core/files/models/file_transfer_snapshot.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/documents/open_prepared_file.dart';
import 'package:scrcpy_connect/widgets/documents/system_file_share_form.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class TransferExportActions extends ConsumerWidget {
  const TransferExportActions({
    super.key,
    required this.current,
    required this.taskId,
    required this.cacheReady,
  });
  final FileTransferSnapshot current;
  final String taskId;
  final bool cacheReady;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saveOffered =
        supportsSystemDocumentSave && current.destinationScope == .privateCache;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (current.canExport &&
            (current.destinationScope != .privateCache || cacheReady) &&
            (current.localPath ?? '').isNotEmpty) ...[
          StateNote(
            current.destinationScope == .privateCache
                ? '已取回本机暂存，尚未保存到系统位置。系统可能清理暂存内容。'
                : '已保存至 ${(current.localPath ?? '')}',
          ),
          if (saveOffered) ...[
            AppButton(
              role: AppButtonRole.primary,
              expand: true,
              onPressed: () => DocumentExportRoute(
                taskId: taskId,
                partial: false,
              ).push<void>(context),
              icon: LucideIcons.folderOutput,
              label: '保存到系统位置',
            ),
            const SizedBox(height: DesignTokens.spacingMd),
          ],
          if (current.kind == .directory)
            StateNote(
              current.destinationScope == .privateCache
                  ? '文件夹结构已取回。保存到系统位置后，可在文件应用中查看。'
                  : '文件夹结构已取回，请在保存位置查看。',
            ),
          if (current.kind != .directory) ...[
            AppButton(
              role: saveOffered
                  ? AppButtonRole.secondaryOnPage
                  : AppButtonRole.primary,
              expand: true,
              onPressed: () => performAction(
                context,
                () => openPreparedFile(context, ref, current.localPath!),
              ),
              icon: LucideIcons.externalLink,
              label: '用本机应用打开',
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            if (supportsSystemFileShare)
              AppButton(
                role: AppButtonRole.secondaryOnPage,
                expand: true,
                onPressed: () async {
                  try {
                    final result = await sharePreparedFile(
                      context,
                      ref,
                      (current.localPath ?? ''),
                    );
                    if (context.mounted) feedback(context, result.message);
                  } catch (error) {
                    if (context.mounted) {
                      feedback(
                        context,
                        failureMessage(error, fallback: '无法打开系统分享。你可以先保存文件。'),
                      );
                    }
                  }
                },
                icon: AppIcons.share,
                label: '系统分享',
              ),
          ],
        ],
        if (current.canExportPartial &&
            (current.destinationScope != .privateCache || cacheReady) &&
            supportsSystemDocumentSave) ...[
          StateNote(
            '目前只取回了部分文件。继续保存只会保存已取回的文件。',
            icon: LucideIcons.circleAlert,
          ),
          AppButton(
            role: AppButtonRole.primary,
            expand: true,
            onPressed: () => DocumentExportRoute(
              taskId: taskId,
              partial: true,
            ).push<void>(context),
            icon: LucideIcons.folderOutput,
            label: '保存已取回的部分',
          ),
        ],
      ],
    );
  }
}
