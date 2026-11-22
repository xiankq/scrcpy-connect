import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_log.dart';
import 'package:scrcpy_connect/core/diagnostics/models/diagnostic_record.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_log_provider.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/adaptive_window.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/overlays.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

import '../widgets/settings_row.dart';

typedef _Filters = (LogLevel?, DiagnosticArea?);

class RuntimeLogsPage extends HookConsumerWidget {
  const RuntimeLogsPage({super.key, this.log, this.save});
  final DiagnosticLog? log;
  final Future<bool> Function(Uint8List bytes)? save;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logger = log ?? ref.watch(diagnosticLogProvider);
    useStream(logger?.changes);
    final filters = useState<_Filters>((null, null));
    final (level, area) = filters.value;
    final filterLabel = [
      if (level != null) _levelName(level),
      if (area != null) _areaName(area),
    ].join(' · ');
    final busy = useState(false);
    final entries = (logger?.recent ?? const <DiagnosticRecord>[]).reversed
        .where((record) => level == null || record.level == level)
        .where((record) => area == null || record.area == area)
        .toList();

    Future<void> chooseFilters() async {
      final window = windowEnvironmentOf(context);
      final centered =
          window.isDesktopWindow ||
          WindowEnvironment.sizeClassFor(
                window.width - window.insets.left - window.insets.right,
              ) !=
              WindowSizeClass.compact;
      final draft = _LogFilters(filters.value);
      final result = centered
          ? await showAppDialog<_Filters>(
              context: context,
              builder: (_) => Dialog(child: draft),
            )
          : await showAppModalSheet<_Filters>(
              context: context,
              builder: (_) => draft,
            );
      if (result != null && context.mounted) filters.value = result;
    }

    Future<void> exportLogs() async {
      busy.value = true;
      try {
        final bytes = await logger!.export();
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
    }

    Future<void> clearLogs() async {
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
        await logger!.clear();
        if (context.mounted) feedback(context, '运行日志已清空');
      } catch (_) {
        if (context.mounted) feedback(context, '日志未能清空，请稍后重试。');
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return PageFrame(
      title: '运行日志',
      child: GroupedListView.builder(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        itemCount: entries.length + 2,
        itemBuilder: (context, index) {
          final theme = Theme.of(context);
          final isHeader = index == 0;
          final isFooter = index == entries.length + 1;
          final labels = MaterialLocalizations.of(context);
          final warning = logger == null
              ? '本次运行未启用日志服务。'
              : logger.storageError != null
              ? '暂时无法写入本机存储，当前仅保留最近的内存记录。'
              : logger.historyIncomplete
              ? '部分日志无法读取，已显示可用记录。'
              : entries.isEmpty
              ? '暂无符合条件的日志。'
              : null;
          final Widget content;
          if (isHeader) {
            content = Column(
              children: [
                SettingsRow(
                  compact: true,
                  icon: LucideIcons.slidersHorizontal,
                  color: DesignTokens.colorListIconUtility,
                  title: '筛选',
                  value: filterLabel.isEmpty ? '全部' : filterLabel,
                  onTap: chooseFilters,
                ),
                if (warning != null) StateNote(warning),
              ],
            );
          } else if (isFooter) {
            content = Column(
              children: [
                SettingsRow(
                  compact: true,
                  icon: LucideIcons.download,
                  color: DesignTokens.colorListIconUtility,
                  title: '导出日志',
                  onTap: logger == null || busy.value ? null : exportLogs,
                ),
                SettingsRow(
                  compact: true,
                  icon: LucideIcons.trash2,
                  color: DesignTokens.colorListIconCoral,
                  title: '清空日志',
                  destructive: true,
                  onTap: logger == null || busy.value ? null : clearLogs,
                ),
              ],
            );
          } else {
            final record = entries[index - 1];
            final time = record.time.toLocal();
            final date = DateUtils.isSameDay(time, DateTime.now())
                ? '今天'
                : labels.formatShortDate(time);
            final firstOfDay =
                index == 1 ||
                !DateUtils.isSameDay(time, entries[index - 2].time.toLocal());
            final clock = [
              time.hour,
              time.minute,
              time.second,
            ].map((unit) => '$unit'.padLeft(2, '0')).join(':');
            final (icon, color) = switch (record.level) {
              .info => (
                LucideIcons.fileText,
                DesignTokens.colorListIconUtility,
              ),
              .warning => (
                LucideIcons.triangleAlert,
                DesignTokens.colorListIconAmber,
              ),
              .error => (LucideIcons.circleX, DesignTokens.colorListIconCoral),
            };
            content = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (firstOfDay)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(date, style: theme.textTheme.bodySmall),
                  ),
                SettingsRow(
                  compact: true,
                  icon: icon,
                  color: color,
                  title: _title(record),
                  subtitle: '$clock · ${_areaName(record.area)}',
                  onTap: record.fields.isEmpty
                      ? null
                      : () => showAppDialog<void>(
                          context: context,
                          title: Text(_title(record)),
                          content: SelectableText(
                            const JsonEncoder.withIndent('  ')
                                .convert(record.fields),
                            style: theme.textTheme.bodySmall,
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(
                                context,
                                rootNavigator: true,
                              ).pop(),
                              child: const Text('关闭'),
                            ),
                          ],
                        ),
                ),
              ],
            );
          }
          const radius = Radius.circular(DesignTokens.roundedLg);
          return Material(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.vertical(
              top: isHeader ? radius : Radius.zero,
              bottom: isFooter ? radius : Radius.zero,
            ),
            clipBehavior: Clip.antiAlias,
            child: content,
          );
        },
      ),
    );
  }
}

class _LogFilters extends HookWidget {
  const _LogFilters(this.initial);
  final _Filters initial;

  @override
  Widget build(BuildContext context) {
    final level = useState(initial.$1);
    final area = useState(initial.$2);
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: ListView(
          padding: const EdgeInsets.all(DesignTokens.spacingLg),
          shrinkWrap: true,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('日志筛选', style: theme.textTheme.titleLarge),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              ],
            ),
            Text('级别', style: theme.textTheme.titleMedium),
            Wrap(
              spacing: DesignTokens.spacingXs,
              children: [
                for (final option in <LogLevel?>[null, ...LogLevel.values])
                  ChoiceChip(
                    label: Text(option == null ? '全部' : _levelName(option)),
                    selected: level.value == option,
                    onSelected: (_) => level.value = option,
                  ),
              ],
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            Text('来源', style: theme.textTheme.titleMedium),
            Wrap(
              spacing: DesignTokens.spacingXs,
              children: [
                for (final option in <DiagnosticArea?>[
                  null,
                  ...DiagnosticArea.values,
                ])
                  ChoiceChip(
                    label: Text(option == null ? '全部' : _areaName(option)),
                    selected: area.value == option,
                    onSelected: (_) => area.value = option,
                  ),
              ],
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            FilledButton(
              onPressed: () =>
                  Navigator.pop<_Filters>(context, (level.value, area.value)),
              child: const Text('应用筛选'),
            ),
          ],
        ),
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
  'devices.changed' => '设备状态变化',
  'session.disconnected' => '控制会话已断开',
  'session.failed' => '控制会话失败',
  'session.stopped' => '控制会话已结束',
  'session.output.failed' => '画面输出失败',
  'audio.updated' => '设备声音状态变化',
  'log.dropped' => '日志写入繁忙，部分记录已丢弃',
  'video.prepare' => '视频准备完成',
  'video.texture' => '视频纹理已创建',
  'video.presentation' => '平台视频纹理已准备',
  _ => record.event,
};
