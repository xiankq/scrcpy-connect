import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'package:scrcpy_connect/pages/settings/data_preferences/widgets/metadata_import_preview.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';

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
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        children: [
          SettingsGroup(
            children: [
              SettingsRow(
                compact: true,
                icon: LucideIcons.download,
                color: DesignTokens.colorListIconPurple,
                title: '导入记录',
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
              SettingsRow(
                compact: true,
                icon: LucideIcons.upload,
                color: DesignTokens.colorListIconPurple,
                title: '导出记录',
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
              if (operation.refreshPending)
                SettingsRow(
                  compact: true,
                  icon: LucideIcons.refreshCw,
                  color: DesignTokens.colorListIconSlate,
                  title: '重新加载记录',
                  onTap: operation.busy ? null : actions.refreshRecords,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
