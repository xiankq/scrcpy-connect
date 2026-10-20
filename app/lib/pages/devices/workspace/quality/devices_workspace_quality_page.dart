import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/choice_row.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:design_system/design_system.dart';

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

class QualityPage extends HookWidget {
  const QualityPage({
    super.key,
    required this.controller,
    required this.device,
  });
  final AppController controller;
  final Json device;
  @override
  Widget build(BuildContext context) {
    final applying = useState(false);
    return PageFrame(
      title: '画质',
      child: CommandView(
        controller: controller,
        command: 'session.quality.options',
        params: {'deviceId': device['id']},
        emptyTitle: '尚未获得可用的画质选项',
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
            // The bridge folds local canAttempt into available, retaining the
            // runtime probe kind instead of forwarding the per-codec flag.
            return item['canAttempt'] == true ||
                (item['canAttempt'] != false &&
                    data['decoderProbe'] == 'runtimeDecodeRequired');
          }

          final available = codecSelectable(codec);
          String codecReason(Json item) {
            if (item['available'] != true && value(item, 'reason').isNotEmpty) {
              return value(item, 'reason');
            }
            if ((item['targetStatus'] ?? item['status']) != 'available') {
              return value(item, 'reason', '尚未确认这台设备的编码能力。');
            }
            if (item['decoderStatus'] == 'unavailable') {
              return value(item, 'reason', '本机没有可用解码器。');
            }
            if (item['decoderStatus'] != 'available' && codecSelectable(item)) {
              return '可尝试此格式；本机能否播放将在新建窗口时确认。';
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
              if (result['appliesNextSession'] == true) {
                feedback(
                  context,
                  value(result, 'reason', '已保存，新建窗口时生效；已保留的窗口需关闭后重新打开。'),
                );
              }
              refresh();
            }
          }

          Future<Json?> pick(
            String title,
            List<Json> options,
            dynamic selected,
          ) => showGlassModalSheet<Json>(
            context: context,
            isScrollControlled: true,
            builder: (context) => SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .8,
                  minHeight: options.length > 8
                      ? MediaQuery.sizeOf(context).height * .8
                      : 0,
                ),
                child: GroupedListView.builder(
                  shrinkWrap: options.length <= 8,
                  padding: const EdgeInsets.only(
                    bottom: DesignTokens.spacingMd,
                  ),
                  itemCount: options.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.all(DesignTokens.spacingMd),
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      );
                    }
                    final item = options[index - 1];
                    return GlassTooltip(
                      message: value(item, 'reason'),
                      child: ListTile(
                        title: Text(value(item, 'label', value(item, 'name'))),

                        enabled: item['available'] == true,
                        trailing: selected == item['value']
                            ? const Icon(LucideIcons.check)
                            : null,
                        onTap: () => Navigator.pop(context, item),
                      ),
                    );
                  },
                ),
              ),
            ),
          );

          Future<void> chooseCodec() async {
            final picked = await pick('编码格式', [
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
            final picked = await pick('视频编码器', [
              {
                'label': '自动选择',
                'value': null,
                'available': available,
                'reason': available ? '由这台设备为所选格式选择编码器。' : codecReason(codec),
              },
              for (final encoder in objects(codec['encoders']))
                {
                  ...encoder,
                  'value': encoder['name'],
                  'label': encoder['name'],
                  'available': available && encoder['available'] == true,
                  'reason': !available
                      ? codecReason(codec)
                      : value(encoder, 'reason', '已从这台设备枚举。实际配置仍取决于设备资源。'),
                },
            ], current['videoEncoder']);
            if (picked != null && context.mounted) {
              await apply({'videoEncoder': picked['value']});
            }
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              ListTile optionRow({
                required String title,
                required String currentValue,
                required VoidCallback? onTap,
              }) {
                final theme = Theme.of(context).textTheme;
                final titleStyle = theme.bodyLarge!;
                final valueStyle = theme.bodySmall!;
                double textWidth(String text, TextStyle style) {
                  final painter = TextPainter(
                    text: TextSpan(text: text, style: style),
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                  )..layout();
                  final width = painter.width;
                  painter.dispose();
                  return width;
                }

                final stacked =
                    textWidth(title, titleStyle) +
                        textWidth(currentValue, valueStyle) >
                    constraints.maxWidth -
                        DesignTokens.spacingMd * 4 -
                        DesignTokens.componentIconSmallSize -
                        DesignTokens.spacingSm * 2;
                const chevron = Icon(
                  LucideIcons.chevronRight,
                  size: DesignTokens.componentIconSmallSize,
                );
                return ListTile(
                  minTileHeight: DesignTokens.componentRowHeight,
                  title: Text(title, style: titleStyle),
                  subtitle: stacked
                      ? Text(currentValue, style: valueStyle)
                      : null,
                  trailing: stacked
                      ? chevron
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(currentValue, style: valueStyle),
                            const SizedBox(width: DesignTokens.spacingSm),
                            chevron,
                          ],
                        ),
                  onTap: onTap,
                );
              }

              return GroupedListView(
                padding: const EdgeInsets.all(DesignTokens.spacingMd),
                children: [
                  const StateNote(
                    '调整会保存到这台设备，并在新建屏幕或应用窗口时生效。已保留的窗口继续使用原设置；关闭后重新打开即可应用。',
                  ),
                  if (applying.value) const LinearProgressIndicator(),
                  const SectionTitle('画质预设'),
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
                    ),
                  const SectionTitle('详细选项'),
                  for (final field in const [
                    ('maxSize', '分辨率上限'),
                    ('maxFps', '帧率'),
                    ('bitRate', '码率'),
                  ])
                    optionRow(
                      title: field.$2,
                      currentValue: qualityValueLabel(
                        field.$1,
                        current[field.$1],
                      ),
                      onTap: applying.value
                          ? null
                          : () async {
                              final options = objects(data[field.$1]);
                              if (options.isEmpty) {
                                feedback(context, '当前设备没有返回可选择的${field.$2}选项');
                                return;
                              }
                              final picked = await pick(field.$2, [
                                for (final item in options)
                                  {
                                    ...item,
                                    'available':
                                        available && item['available'] == true,
                                    if (!available) 'reason': '请先选择双方可用的编码格式。',
                                  },
                              ], current[field.$1]);
                              if (picked != null && context.mounted) {
                                await apply({field.$1: picked['value']});
                              }
                            },
                    ),
                  optionRow(
                    title: '编码格式',
                    currentValue: value(codec, 'name', codecId),
                    onTap: applying.value || codecs.isEmpty
                        ? null
                        : chooseCodec,
                  ),
                  optionRow(
                    title: '视频编码器',
                    currentValue: value(current, 'videoEncoder', '自动'),
                    onTap: applying.value || codec.isEmpty
                        ? null
                        : chooseEncoder,
                  ),
                  if (!available || codec['decoderStatus'] != 'available')
                    StateNote(codecReason(codec)),
                  const StateNote(
                    '可尝试的格式仍需打开实际画面后确认，保存设置不代表解码已通过。调整失败后保留原值；实际画质仍受设备性能与连接状况影响。',
                  ),
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
          );
        },
      ),
    );
  }
}
