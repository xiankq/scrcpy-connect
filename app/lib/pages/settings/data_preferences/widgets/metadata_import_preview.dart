import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/settings/metadata_management.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:scrcpy_connect/widgets/list_row.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

import '../../widgets/settings_row.dart';

class MetadataImportPreview extends HookWidget {
  const MetadataImportPreview({super.key, required this.preview});
  final SettingsImportPreview preview;
  @override
  Widget build(BuildContext context) {
    final importGlobal = useState(false);
    final duplicate = preview.alreadyImported;
    final changes = preview.globalChanges;
    return PageFrame(
      title: '导入预览',
      onBack: () => Navigator.pop(context),
      bottom: AppButton(
        role: AppButtonRole.primary,
        expand: true,
        onPressed: () =>
            Navigator.pop(context, duplicate ? null : importGlobal.value),
        label: duplicate ? '完成' : '导入 ${preview.newRecords} 条记录',
      ),
      child: GroupedListView(
        padding: const EdgeInsets.all(DesignTokens.componentPagePadding),
        children: [
          SettingsGroup(
            children: [
              SettingsRow(
                icon: LucideIcons.smartphone,
                color: FunctionTone.archive,
                title: duplicate ? '此文件已经导入' : '将新增 ${preview.newRecords} 条记录',
                subtitle: duplicate
                    ? '上次新增 ${preview.receipt!.restored} 条记录'
                    : null,
              ),
            ],
          ),
          if (duplicate)
            StateNote(switch (preview.preferencesStatus) {
              ImportPreferencesStatus.matchesCurrent => '当前全局偏好与此文件一致。',
              ImportPreferencesStatus.needsReview => '全局偏好已变化，可在设置中核对当前值。',
              _ => '上次导入保留了本机全局偏好。',
            })
          else
            const StateNote('导入后，手机仍需单独授权。各设备的画质、电源和剪贴板偏好需重新设置。'),
          if (!duplicate && changes.isNotEmpty) ...[
            const SectionTitle('选项'),
            SettingsGroup(
              children: [
                ConnectSwitchRow(
                  icon: AppIcons.viewOptions,
                  title: const Text('同时导入全局偏好'),
                  value: importGlobal.value,
                  onChanged: (value) => importGlobal.value = value,
                ),
                if (importGlobal.value)
                  for (final change in changes)
                    AppListRow(
                      title: Text(_preferenceName(change.key)),
                      subtitle: Text(
                        '${_preferenceValue(change.current, key: change.key)} → ${_preferenceValue(change.imported, key: change.key)}',
                      ),
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String _preferenceName(String key) =>
    const {
      'appearance': '外观',
      'glassEffects': '液态玻璃',
      'backgroundKeepAlive': '后台保持',
      'notificationAlerts': '通知提醒',
      'callAlerts': '来电提醒',
      'adbBurstMode': '连接性能偏好',
      'fileViewMode': '文件显示方式',
      'fileSortKey': '文件排序',
      'fileSortAscending': '文件升序排列',
      'qualityPreset': '默认画质',
      'maxSize': '默认分辨率上限',
      'maxFps': '默认帧率',
      'videoBitRate': '默认码率',
      'videoCodec': '默认视频格式',
      'videoEncoder': '默认编码器',
    }[key] ??
    '全局偏好';
String _preferenceValue(Object? input, {required String key}) =>
    switch (input) {
      'automatic' when key == 'glassEffects' => '跟随平台',
      'premium' when key == 'glassEffects' => '极致',
      'standard' when key == 'glassEffects' => '标准',
      'off' when key == 'glassEffects' => '关闭',
      true => '开启',
      false => '关闭',
      null => '自动',
      'light' => '浅色',
      'dark' => '深色',
      'system' => '跟随系统',
      'grid' => '宫格',
      'list' => '列表',
      'name' => '名称',
      'size' => '大小',
      'modified' => '修改时间',
      'type' => '类型',
      'smooth' => '流畅',
      'balanced' => '均衡',
      'clear' => '清晰',
      _ => '$input',
    };
