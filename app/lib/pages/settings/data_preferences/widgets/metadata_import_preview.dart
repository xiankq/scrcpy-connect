import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';

class MetadataImportPreview extends HookWidget {
  const MetadataImportPreview({super.key, required this.preview});
  final Json preview;
  @override
  Widget build(BuildContext context) {
    final importGlobal = useState(false);
    final duplicate = preview['alreadyImported'] == true;
    final receipt = jsonObject(preview['receipt']);
    final changes = objects(preview['globalChanges']);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              duplicate ? '此文件已经导入' : '预览设备记录',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            Text(
              duplicate
                  ? '上次已新增 ${receipt['restored'] ?? 0} 条记录，不会重复追加。'
                  : '将新增 ${preview['newRecords']} 条未授权的设备记录。',
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            const Text('不能恢复连接许可，也不会恢复文件中的每设备画质、电源与剪贴板设置。本机已有的设备记录与偏好会保留。'),
            if (duplicate) ...[
              const SizedBox(height: DesignTokens.spacingMd),
              Text(switch (preview['preferencesStatus']) {
                'matchesCurrent' => '当前全局偏好与此文件一致。',
                'needsReview' => '上次选择了导入全局偏好，当前值与文件不一致。请到对应设置中核对；这里不会重新应用旧设置。',
                _ => '上次导入保留了本机全局偏好。',
              }),
            ] else if (changes.isNotEmpty) ...[
              const SizedBox(height: DesignTokens.spacingMd),
              ConnectSwitchRow(
                contentPadding: EdgeInsets.zero,
                title: const Text('同时导入全局偏好'),
                value: importGlobal.value,
                onChanged: (next) => importGlobal.value = next,
              ),
              Text(
                '默认保留本机设置。开启后将应用以下变更：',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              for (final change in changes)
                Padding(
                  padding: const EdgeInsets.only(top: DesignTokens.spacingSm),
                  child: Text(
                    '${_preferenceName(value(change, 'key'))}：${_preferenceValue(change['current'])} → ${_preferenceValue(change['imported'])}',
                  ),
                ),
            ],
            const SizedBox(height: DesignTokens.spacingLg),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, duplicate ? null : importGlobal.value),
              child: Text(duplicate ? '完成' : '导入 ${preview['newRecords']} 条记录'),
            ),
            if (!duplicate)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
          ],
        ),
      ),
    );
  }
}

String _preferenceName(String key) =>
    const {
      'appearance': '外观',
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
String _preferenceValue(Object? input) => switch (input) {
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
