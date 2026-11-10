import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/models/remote_display_settings.dart';
import 'package:scrcpy_connect/pages/devices/workspace/quality/widgets/screen_ratio_picker.dart';
import 'package:scrcpy_connect/stores/app_store.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/choice_row.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

import 'widgets/quality_option_row.dart';
import 'widgets/quality_options_sheet.dart';

String qualityValueLabel(String field, dynamic input) {
  final raw = input?.toString() ?? '';
  final number = num.tryParse(raw);
  if (number == null) return raw.isEmpty ? '由设备协商' : raw;
  String compact(num value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
  if (number <= 0) return field == 'maxFps' ? '不限帧率' : '自动';
  return switch (field) {
    'maxSize' => '${compact(number)} px',
    'maxFps' => '${compact(number)} fps',
    'bitRate' => '${compact(number / 1000000)} Mbps',
    _ => raw,
  };
}

class QualityPage extends HookConsumerWidget {
  const QualityPage({
    super.key,
    required this.controller,
    required this.device,
  });
  final AppStore controller;
  final Json device;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final applying = useState(false);
    final applicationFailures = useState<List<Json>>([]);
    final settings = ref.watch(
      appStoreProvider.select((state) => state.settings),
    );
    final preferences = jsonObject(
      jsonObject(settings['deviceSettings'])[device['id']],
    );
    return PageFrame(
      title: '画面与控制',
      child: GroupedListView(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        children: [
          const SectionTitle('画面与手机屏幕'),
          SettingsGroup(
            children: [
              for (final option in const [
                ('showNavigationBar', '显示导航键', LucideIcons.navigation, true),
                ('wakeOnConnect', '新画面启动时点亮屏幕', LucideIcons.sun, true),
                ('lockOnClose', '关闭最后画面时熄屏', LucideIcons.moon, false),
                ('stayAwake', '保持手机唤醒', LucideIcons.alarmClock, false),
              ])
                ConnectSwitchRow(
                  title: Text(option.$2),
                  icon: option.$3,
                  value: preferences[option.$1] as bool? ?? option.$4,
                  onChanged: (next) async {
                    try {
                      await controller.updateDeviceSetting(
                        value(device, 'id'),
                        option.$1,
                        next,
                      );
                    } catch (error) {
                      if (context.mounted) feedback(context, '$error');
                    }
                  },
                ),
            ],
          ),
          const SectionTitle('屏幕布局'),
          SettingsGroup(
            children: [
              ActionRow(
                icon: LucideIcons.ratio,
                title: '屏幕比例',
                trailing: Text(RemoteDisplaySettings(preferences).label),
                onTap: () => chooseScreenRatio(
                  context,
                  controller,
                  value(device, 'id'),
                  preferences,
                ),
              ),
            ],
          ),
          PageChromePadding(
            padding: EdgeInsets.zero,
            showRecovery: false,
            child: CommandView(
              controller: controller,
              command: 'session.quality.options',
              params: {'deviceId': device['id']},
              emptyTitle: '尚未获得可用的画面选项',
              builder: (context, data, refresh) {
                final current = data['current'] is Map<Object?, Object?>
                    ? jsonObject(data['current'])
                    : <String, dynamic>{};
                final codecs = objects(data['codecs']);
                final codecId = value(current, 'videoCodec');
                final matching = codecs.where((item) => item['id'] == codecId);
                final codec = matching.firstOrNull ?? <String, dynamic>{};
                bool codecSelectable(Json item) {
                  if (item['available'] != true ||
                      item['decoderStatus'] == 'unavailable' ||
                      (item['targetStatus'] ?? item['status']) != 'available') {
                    return false;
                  }
                  if (item['decoderStatus'] == 'available') return true;
                  // 桥接将本机 canAttempt 合入 available，保留运行时探测类型，不直接透传逐编解码器标志。
                  return item['canAttempt'] == true ||
                      (item['canAttempt'] != false &&
                          data['decoderProbe'] == 'runtimeDecodeRequired');
                }

                final available = codecSelectable(codec);
                String codecReason(Json item) {
                  if (item['available'] != true &&
                      value(item, 'reason').isNotEmpty) {
                    return value(item, 'reason');
                  }
                  if ((item['targetStatus'] ?? item['status']) != 'available') {
                    return value(item, 'reason', '尚未确认这台设备的编码能力。');
                  }
                  if (item['decoderStatus'] == 'unavailable') {
                    return value(item, 'reason', '本机没有可用解码器。');
                  }
                  if (item['decoderStatus'] != 'available' &&
                      codecSelectable(item)) {
                    return '可尝试此格式；本机能否播放将在实际画面应用时确认。';
                  }
                  if (item['decoderStatus'] != 'available') {
                    return '尚未确认本机可用的解码器。${value(item, 'reason')}';
                  }
                  return '双方支持此格式，实际使用仍取决于设备资源。';
                }

                Future<void> apply(Json patch) async {
                  if (applying.value) return;
                  applying.value = true;
                  final result = await perform(
                    context,
                    controller,
                    'session.quality',
                    {'deviceId': device['id'], ...patch},
                  );
                  if (!context.mounted) return;
                  applying.value = false;
                  if (result != null) {
                    final failed = objects(result['failures']);
                    applicationFailures.value = failed;
                    if (failed.isNotEmpty) {
                      feedback(context, '设置已保存，${failed.length} 个画面未能应用。');
                    }
                    refresh();
                  }
                }

                Future<Json?> pick(
                  String title,
                  IconData icon,
                  List<Json> options,
                  dynamic selected,
                ) => showGlassModalSheet<Json>(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) => QualityOptionsSheet(
                    title: title,
                    icon: icon,
                    options: options,
                    selected: selected,
                  ),
                );

                Future<void> chooseCodec() async {
                  final picked = await pick('编码格式', LucideIcons.film, [
                    for (final item in codecs)
                      {
                        ...item,
                        'label': value(item, 'name', value(item, 'id')),
                        'value': item['id'],
                        'available': codecSelectable(item),
                        'reason': codecReason(item),
                      },
                  ], codecId);
                  if (picked != null && context.mounted) {
                    await apply({
                      'videoCodec': picked['value'],
                      'videoEncoder': null,
                    });
                  }
                }

                Future<void> chooseEncoder() async {
                  final picked = await pick('视频编码器', LucideIcons.cpu, [
                    {
                      'label': '自动选择',
                      'value': null,
                      'available': available,
                      'reason': available
                          ? '由这台设备为所选格式选择编码器。'
                          : codecReason(codec),
                    },
                    for (final encoder in objects(codec['encoders']))
                      {
                        ...encoder,
                        'value': encoder['name'],
                        'label': encoder['name'],
                        'available': available && encoder['available'] == true,
                        'reason': !available
                            ? codecReason(codec)
                            : value(
                                encoder,
                                'reason',
                                '已从这台设备枚举。实际配置仍取决于设备资源。',
                              ),
                      },
                  ], current['videoEncoder']);
                  if (picked != null && context.mounted) {
                    await apply({'videoEncoder': picked['value']});
                  }
                }

                return GroupedListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  children: [
                    if (applying.value) const ContentLoadingIndicator(),
                    for (final failure in applicationFailures.value)
                      StateNote(
                        '${value(failure, 'name', '画面')}：${value(failure, 'reason', '本次设置未能应用')}',
                      ),
                    const SectionTitle('画面质量'),
                    SettingsGroup(
                      children: [
                        for (final preset in objects(data['presets']))
                          ChoiceRow<String>(
                            value: value(preset, 'id'),
                            groupValue: value(current, 'preset'),
                            onChanged:
                                applying.value ||
                                    !available ||
                                    preset['available'] != true
                                ? null
                                : (v) => apply({'preset': v}),
                            title: Text(value(preset, 'name')),
                            leading: ListIconBadge(
                              icon: LucideIcons.gauge,
                              backgroundColor: DesignTokens.colorListIconMint,
                            ),
                          ),
                      ],
                    ),
                    const SectionTitle('详细画质'),
                    SettingsGroup(
                      children: [
                        for (final field in const [
                          ('maxSize', '分辨率上限'),
                          ('maxFps', '帧率'),
                          ('bitRate', '码率'),
                        ])
                          QualityOptionRow(
                            title: field.$2,
                            icon: switch (field.$1) {
                              'maxSize' => LucideIcons.monitor,
                              'maxFps' => LucideIcons.gauge,
                              _ => LucideIcons.network,
                            },
                            currentValue: qualityValueLabel(
                              field.$1,
                              current[field.$1],
                            ),
                            onTap: applying.value
                                ? null
                                : () async {
                                    final options = objects(data[field.$1]);
                                    if (options.isEmpty) {
                                      feedback(
                                        context,
                                        '当前设备没有返回可选择的${field.$2}选项',
                                      );
                                      return;
                                    }
                                    final picked = await pick(
                                      field.$2,
                                      switch (field.$1) {
                                        'maxSize' => LucideIcons.monitor,
                                        'maxFps' => LucideIcons.gauge,
                                        _ => LucideIcons.network,
                                      },
                                      [
                                        for (final item in options)
                                          {
                                            ...item,
                                            'available':
                                                available &&
                                                item['available'] == true,
                                            if (!available)
                                              'reason': '请先选择双方可用的编码格式。',
                                          },
                                      ],
                                      current[field.$1],
                                    );
                                    if (picked != null && context.mounted) {
                                      await apply({field.$1: picked['value']});
                                    }
                                  },
                          ),
                        QualityOptionRow(
                          title: '编码格式',
                          icon: LucideIcons.film,
                          currentValue: value(codec, 'name', codecId),
                          onTap: applying.value || codecs.isEmpty
                              ? null
                              : chooseCodec,
                        ),
                        QualityOptionRow(
                          title: '视频编码器',
                          icon: LucideIcons.cpu,
                          currentValue: value(current, 'videoEncoder', '自动'),
                          onTap: applying.value || codec.isEmpty
                              ? null
                              : chooseEncoder,
                        ),
                      ],
                    ),
                    if (!available || codec['decoderStatus'] != 'available')
                      StateNote(codecReason(codec)),
                    if (objects(data['activeStreams']).isNotEmpty) ...[
                      const SectionTitle('正在使用的画面'),
                      for (final stream in objects(data['activeStreams']))
                        ActionRow(
                          icon: LucideIcons.monitor,
                          title: value(stream, 'name', '手机屏幕'),
                        ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
