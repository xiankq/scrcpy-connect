import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/pages/settings/data_preferences/widgets/metadata_import_preview.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/stores/app_store.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';

class DataPreferencesPage extends StatelessWidget {
  const DataPreferencesPage({super.key, required this.controller});
  final AppStore controller;
  @override
  Widget build(BuildContext context) => PageFrame(
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

              onTap: () async {
                final result = await perform(
                  context,
                  controller,
                  'settings.export',
                );
                if (result != null && context.mounted) {
                  if (result['metadata'] is! Map) {
                    feedback(context, '尚未获得可导出的设备记录');
                    return;
                  }
                  try {
                    final saved = await FilePicker.saveFile(
                      fileName: 'interconnect-devices.json',
                      mimeType: 'application/json',
                      bytes: Uint8List.fromList(
                        utf8.encode(
                          const JsonEncoder.withIndent('  ')
                              .convert(result['metadata']),
                        ),
                      ),
                    );
                    if (saved != null && context.mounted) {
                      feedback(context, '设备记录已保存至 $saved');
                    }
                  } catch (e) {
                    if (context.mounted) feedback(context, '保存记录失败：$e');
                  }
                }
              },
            ),
            ActionRow(
              icon: LucideIcons.fileInput,
              title: '导入设备记录',

              onTap: () async {
                Json? result;
                try {
                  final picked = await FilePicker.pickFile(
                    type: FileType.custom,
                    allowedExtensions: ['json'],
                  );
                  if (picked?.path == null || !context.mounted) return;
                  final input = File(picked!.path!);
                  final size = await input.length();
                  if (size > 1024 * 1024 || size < 2) {
                    if (context.mounted) {
                      feedback(context, '设备记录文件须小于 1 MB，并包含有效的 JSON 内容。');
                    }
                    return;
                  }
                  final metadata = jsonDecode(await input.readAsString());
                  if (!context.mounted) return;
                  if (metadata is! Map) {
                    feedback(context, '此文件不包含有效的设备记录');
                    return;
                  }
                  final preview = await perform(
                    context,
                    controller,
                    'settings.import.preview',
                    {'metadata': metadata},
                  );
                  if (preview == null || !context.mounted) return;
                  final importGlobal = await showGlassModalSheet<bool>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => MetadataImportPreview(preview: preview),
                  );
                  if (importGlobal == null || !context.mounted) {
                    return;
                  }
                  result = await perform(
                    context,
                    controller,
                    'settings.import',
                    {
                      'metadata': metadata,
                      'fingerprint': preview['fingerprint'],
                      'expectedRevision': preview['expectedRevision'],
                      'importGlobalPreferences': importGlobal,
                    },
                  );
                } catch (e) {
                  if (context.mounted) feedback(context, '无法读取记录文件：$e');
                }
                if (result != null) {
                  await controller.loadSettings();
                  await controller.refreshDevices();
                  if (context.mounted) {
                    feedback(
                      context,
                      result['alreadyImported'] == true
                          ? '此文件已导入，已核对本机记录。'
                          : '设备记录已导入，请在被控手机重新核验授权。',
                    );
                  }
                }
              },
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
