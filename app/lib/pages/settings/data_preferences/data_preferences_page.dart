import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'package:scrcpy_connect/pages/settings/data_preferences/widgets/metadata_import_preview.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';

import '../widgets/settings_row.dart';
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
      title: '设备记录与恢复',
      child: GroupedListView(
        padding: const EdgeInsets.all(DesignTokens.componentPagePadding),
        children: [
          if (operation.refreshPending) ...[
            SettingsGroup(
              children: [
                SettingsRow(
                  icon: AppIcons.refresh,
                  color: FunctionTone.archive,
                  title: '重新加载记录',
                  onTap: operation.busy ? null : actions.refreshRecords,
                ),
              ],
            ),
            const SizedBox(height: DesignTokens.componentListSectionGap),
          ],
          SettingsGroup(
            children: [
              SettingsRow(
                icon: LucideIcons.upload,
                color: FunctionTone.archive,
                title: '导出记录',
                subtitle: '保存为文件，可在其他主控导入',
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
              SettingsRow(
                icon: AppIcons.download,
                color: FunctionTone.archive,
                title: '导入记录',
                subtitle: '导入前可预览将新增的设备',
                onTap: operation.busy
                    ? null
                    : () => actions.importRecords(
                        pickFile: () async => (await FilePicker.pickFile(
                          type: FileType.custom,
                          allowedExtensions: ['json'],
                        ))?.path,
                        confirm: (preview) => !context.mounted
                            ? Future<bool?>.value(null)
                            : Navigator.of(context).push<bool>(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      MetadataImportPreview(preview: preview),
                                ),
                              ),
                      ),
              ),
            ],
          ),
          const SectionFooter('记录包含设备名称、连接方式和偏好，不含手机授权。'),
        ],
      ),
    );
  }
}
