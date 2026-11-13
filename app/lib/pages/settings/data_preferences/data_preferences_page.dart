import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'package:scrcpy_connect/pages/settings/data_preferences/widgets/metadata_import_preview.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/overlays.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

import 'metadata_operation_notifier.dart';

class DataPreferencesPage extends HookConsumerWidget {
  const DataPreferencesPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = useMemoized(Object.new);
    final provider = metadataOperationProvider(scope: scope);
    final operation = ref.watch(provider);
    final actions = ref.read(provider.notifier);
    ref.listen(provider, (previous, next) {
      if (next.message != null && next.message != previous?.message) {
        feedback(context, next.message!);
      }
    });
    return PageFrame(
      title: '本地数据',
      child: GroupedListView(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        children: [
          Text('授权身份留在本机', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: DesignTokens.spacingMd),
          const Text('名称与偏好不等于连接许可。重装或更换主控后，即使恢复了设备记录，也需要在被控手机上重新授权。'),
          const SectionTitle('本机记录'),
          SettingsGroup(
            children: [
              ActionRow(
                icon: LucideIcons.fileOutput,
                title: '导出设备记录',

                enabled: !operation.busy,
                onTap: operation.busy
                    ? null
                    : () => actions.exportRecords(
                        saveFile: (bytes) => !context.mounted
                            ? Future<Uri?>.value(null)
                            : FilePicker.saveFile(
                                fileName: 'interconnect-devices.json',
                                mimeType: 'application/json',
                                bytes: bytes,
                              ),
                      ),
              ),
              ActionRow(
                icon: LucideIcons.fileInput,
                title: '导入设备记录',

                enabled: !operation.busy,
                onTap: operation.busy
                    ? null
                    : () => actions.importRecords(
                        pickFile: () async => (await FilePicker.pickFile(
                          type: FileType.custom,
                          allowedExtensions: ['json'],
                        ))?.path,
                        confirm: (preview) => !context.mounted
                            ? Future<bool?>.value(null)
                            : showAppModalSheet<bool>(
                                context: context,
                                isScrollControlled: true,
                                builder: (_) =>
                                    MetadataImportPreview(preview: preview),
                              ),
                      ),
              ),
              if (operation.refreshPending)
                ActionRow(
                  icon: LucideIcons.refreshCw,
                  title: '重新加载记录',
                  enabled: !operation.busy,
                  onTap: operation.busy ? null : actions.refreshRecords,
                ),
            ],
          ),
          const StateNote(
            '导出文件包含设备地址，请妥善保存，仅向信任的人分享。移除设备只删除本机记录；撤销调试信任请到被控手机的开发者选项中操作。',
          ),
        ],
      ),
    );
  }
}
