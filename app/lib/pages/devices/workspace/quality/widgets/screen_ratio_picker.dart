import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/stores/app_store.dart';
import 'package:scrcpy_connect/models/remote_display_settings.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';

Future<void> chooseScreenRatio(
  BuildContext context,
  AppStore controller,
  String deviceId,
  Json preferences,
) async {
  const options = {
    'original': '原始比例',
    'auto': '自动适应可用空间',
    '9:16': '9:16',
    '3:4': '3:4',
    '1:1': '1:1',
    '16:9': '16:9',
    'custom': '自定义',
  };
  final choice = await showGlassDialog<String>(
    context: context,
    builder: (context) => GlassAlertDialog(
      title: const Text('屏幕比例'),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.sizeOf(context).height * .5,
        child: ListView(
          children: [
            for (final item in options.entries)
              ListTile(
                leading: ListIconBadge(
                  icon: LucideIcons.ratio,
                  backgroundColor: functionalIconColor(LucideIcons.ratio),
                ),
                title: Text(item.value),
                trailing: RemoteDisplaySettings(preferences).mode == item.key
                    ? const Icon(LucideIcons.check)
                    : null,
                onTap: () => Navigator.of(context).pop(item.key),
              ),
          ],
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  String? custom;
  if (choice == 'custom') {
    final input = await askText(
      context,
      title: '自定义屏幕比例',
      initial: '${preferences['remoteCustomRatio'] ?? '9:16'}',
      label: '宽:高，例如 9:16，范围 1:5 至 5:1',
    );
    if (input == null || !context.mounted) return;
    if (RemoteDisplaySettings.parseRatio(input) == null) {
      feedback(context, '请输入有效的宽:高，比例范围为 1:5 至 5:1。');
      return;
    }
    custom = input
        .trim()
        .split(RegExp(r'[:：/]'))
        .map((s) => s.trim())
        .join(':');
  }
  try {
    // 同一事务保存两个字段，避免失败后把新自定义比例与旧模式混用。
    await controller.updateDeviceSettings(deviceId, {
      'remoteAspectRatio': choice,
      'remoteCustomRatio': ?custom,
    });
    if (context.mounted) feedback(context, '屏幕比例已保存，用于新建画面。');
  } catch (error) {
    if (context.mounted) feedback(context, '$error');
  }
}
