import 'dart:convert';
import 'dart:typed_data';

import 'package:design_system/design_system.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:device_runtime/device_runtime.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/services/app_dependencies.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class RuntimeLogsPage extends HookConsumerWidget {
  const RuntimeLogsPage({super.key, this.log, this.save});
  final DiagnosticLog? log;
  final Future<bool> Function(Uint8List bytes)? save;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logger = log ?? ref.watch(appDependenciesProvider).diagnostics;
    useStream(logger?.changes);
    final level = useState<LogLevel?>(null);
    final area = useState<DiagnosticArea?>(null);
    final busy = useState(false);
    final entries = (logger?.recent ?? const <DiagnosticRecord>[])
        .where((r) => level.value == null || r.level == level.value)
        .where((r) => area.value == null || r.area == area.value)
        .toList()
        .reversed
        .toList();
    return PageFrame(
      title: '运行日志',
      actions: [
        GlassActionIcon(
          tooltip: '导出日志',
          icon: const Icon(LucideIcons.download),
          onPressed: logger == null || busy.value
              ? null
              : () async {
                  busy.value = true;
                  try {
                    final bytes = await logger.export();
                    if (!context.mounted) return;
                    final saved = save == null
                        ? await FilePicker.saveFile(
                                fileName: 'interconnect-runtime.jsonl',
                                mimeType: 'application/x-ndjson',
                                bytes: bytes,
                              ) !=
                              null
                        : await save!(bytes);
                    if (saved && context.mounted) feedback(context, '运行日志已导出');
                  } catch (_) {
                    if (context.mounted) feedback(context, '日志未能导出，请重新选择保存位置。');
                  } finally {
                    if (context.mounted) busy.value = false;
                  }
                },
        ),
        GlassActionIcon(
          tooltip: '清空日志',
          icon: const Icon(LucideIcons.trash2),
          onPressed: logger == null || busy.value
              ? null
              : () async {
                  if (!await confirm(
                        context,
                        '清空运行日志？',
                        '本机已有日志将被删除，之后仍会记录新的运行事件。',
                        action: '清空日志',
                      ) ||
                      !context.mounted) {
                    return;
                  }
                  busy.value = true;
                  try {
                    await logger.clear();
                    if (context.mounted) feedback(context, '运行日志已清空');
                  } catch (_) {
                    if (context.mounted) feedback(context, '日志未能清空，请稍后重试。');
                  } finally {
                    if (context.mounted) busy.value = false;
                  }
                },
        ),
      ],
      child: GroupedListView.builder(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        itemCount: entries.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const StateNote('日志仅保存在本机，自动清理较早记录。导出包含保留期内的全部日志，不受当前筛选影响。'),
                const SizedBox(height: DesignTokens.spacingMd),
                Wrap(
                  spacing: DesignTokens.spacingXs,
                  runSpacing: DesignTokens.spacingXs,
                  children: [
                    for (final filter in <LogLevel?>[null, ...LogLevel.values])
                      ChoiceChip(
                        label: Text(
                          filter == null ? '全部级别' : _levelName(filter),
                        ),
                        selected: level.value == filter,
                        onSelected: (_) => level.value = filter,
                      ),
                  ],
                ),
                const SizedBox(height: DesignTokens.spacingSm),
                DropdownButtonFormField<DiagnosticArea?>(
                  initialValue: area.value,
                  decoration: const InputDecoration(labelText: '日志来源'),
                  items: [
                    const DropdownMenuItem<DiagnosticArea?>(
                      value: null,
                      child: Text('全部来源'),
                    ),
                    for (final filter in DiagnosticArea.values)
                      DropdownMenuItem(
                        value: filter,
                        child: Text(_areaName(filter)),
                      ),
                  ],
                  onChanged: (value) => area.value = value,
                ),
                const SizedBox(height: DesignTokens.spacingMd),
                if (logger == null)
                  const StateNote('本次运行未启用日志服务。')
                else if (logger.storageError != null)
                  const StateNote('暂时无法写入本机存储，当前仅保留最近的内存记录。')
                else
                  const StateNote('显示最近300条记录。授权密钥、配对码、剪贴板、通知正文与媒体访问凭据不写入日志。'),
                if (entries.isEmpty) ...[
                  const SizedBox(height: DesignTokens.spacingLg),
                  const StateNote('暂无符合条件的日志'),
                ],
              ],
            );
          }
          final record = entries[index - 1];
          return Padding(
            padding: const EdgeInsets.symmetric(
              vertical: DesignTokens.spacingSm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title(record),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: DesignTokens.spacingXxs),
                Text(
                  '${record.time.toLocal().toIso8601String().replaceFirst('T', ' ')} · ${_areaName(record.area)} · ${_levelName(record.level)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (record.fields.isNotEmpty)
                  SelectableText(
                    const JsonEncoder.withIndent('  ').convert(record.fields),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

String _levelName(LogLevel level) => switch (level) {
  LogLevel.info => '信息',
  LogLevel.warning => '警告',
  LogLevel.error => '错误',
};

String _areaName(DiagnosticArea area) => switch (area) {
  DiagnosticArea.app => '应用',
  DiagnosticArea.connection => '连接',
  DiagnosticArea.video => '画面',
  DiagnosticArea.audio => '声音',
  DiagnosticArea.runtime => '核心',
};

String _title(DiagnosticRecord record) => switch (record.event) {
  'decoder.selected' =>
    '已选用解码器：${record.fields['decoder']}（${switch (record.fields['acceleration']) {
      'hardware' => '硬件解码',
      'software' => '软件解码',
      _ => '硬件加速状态未知',
    }}）',
  'decoder.failed' => '解码器尝试失败：${record.fields['decoder']}',
  'request.completed' => '操作已完成：${record.fields['command']}',
  'request.failed' => '操作未完成：${record.fields['command']}',
  'playback.failed' => '播放失败',
  'output.released' => '播放器释放回执',
  'app.started' => '应用启动',
  'bootstrap.started' => '正在初始化',
  'bootstrap.ready' => '初始化完成',
  'bootstrap.failed' => '初始化失败',
  'flutter.error' => '界面发生错误',
  'async.error' => '异步任务发生错误',
  'app.lifecycle' => '应用状态变化',
  'device.changed' => '设备连接状态变化',
  'session.disconnected' => '控制会话已断开',
  'audio.updated' => '设备声音状态变化',
  'log.dropped' => '日志写入繁忙，部分记录已丢弃',
  'video.prepare' => '视频准备完成',
  'video.texture' => '视频纹理已创建',
  'video.presentation' => '平台视频纹理已准备',
  _ => record.event,
};
