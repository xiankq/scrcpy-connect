import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';
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
import 'package:design_system/design_system.dart';

class DataPreferencesPage extends StatelessWidget {
  const DataPreferencesPage({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => PageFrame(
    title: '设备记录与恢复',
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
              title: '导出设备名称与偏好',

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
                      feedback(context, '设备名称与偏好已保存至 $saved');
                    }
                  } catch (e) {
                    if (context.mounted) feedback(context, '保存记录失败：$e');
                  }
                }
              },
            ),
            ActionRow(
              icon: LucideIcons.fileInput,
              title: '恢复名称与偏好',

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
                  if (!await confirm(
                        context,
                        '恢复本机设备记录？',
                        '仅恢复名称与偏好。恢复的设备需要重新在被控手机授权，不会恢复主控身份。',
                        action: '恢复记录',
                      ) ||
                      !context.mounted) {
                    return;
                  }
                  result = await perform(
                    context,
                    controller,
                    'settings.import',
                    {'metadata': metadata},
                  );
                } catch (e) {
                  if (context.mounted) feedback(context, '无法读取记录文件：$e');
                }
                if (result != null) {
                  await controller.loadSettings();
                  await controller.refreshDevices();
                  if (context.mounted) feedback(context, '记录已读取，请在被控手机重新核验授权');
                }
              },
            ),
          ],
        ),
        const StateNote('移除设备只删除本机记录。若要撤销调试信任，请到被控手机的开发者选项中操作。'),
      ],
    ),
  );
}
