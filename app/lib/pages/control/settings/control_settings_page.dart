import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/control/remote_display_settings.dart';
import 'package:scrcpy_connect/core/control/control_capabilities_provider.dart';
import 'package:scrcpy_connect/core/control/video_quality_provider.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/settings/settings_capabilities_provider.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';
import 'package:scrcpy_connect/core/settings/preferences_notifier.dart';
import 'package:scrcpy_connect/pages/control/settings/widgets/quality_option_row.dart';
import 'package:scrcpy_connect/pages/control/settings/widgets/quality_options_sheet.dart';
import 'package:scrcpy_connect/pages/control/settings/widgets/screen_ratio_picker.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/async_content.dart';
import 'package:scrcpy_connect/widgets/choice_row.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

String _codecReason(VideoCodecOption? option) {
  if (option == null) return '尚未确认这台设备的编码能力。';
  if (option.encoders.isEmpty) return '设备未枚举到此格式的编码器。';
  if (option.decoder.evidence == VideoDecoderEvidence.unavailable) {
    return option.decoder.reason;
  }
  if (option.decoder.evidence != VideoDecoderEvidence.verified &&
      option.available) {
    return '可尝试此格式；本机能否播放将在实际画面应用时确认。';
  }
  if (!option.available) return '尚未确认本机可用的解码器。${option.decoder.reason}';
  return '双方支持此格式，实际使用仍取决于设备资源。';
}

class ControlSettingsPage extends HookConsumerWidget {
  const ControlSettingsPage({super.key, required this.device});
  final DeviceSnapshot device;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsOwner = ref.watch(settingsManagementProvider);
    final quality = ref.watch(videoQualityControlProvider);
    final applying = useValueNotifier(false, [quality, device.id]);
    useValueListenable(applying);
    bool ownsQuality() =>
        context.mounted &&
        identical(ref.read(videoQualityControlProvider), quality);
    final applicationFailures = useValueNotifier<List<VideoQualityFailure>>(
      [],
      [quality, device.id],
    );
    useValueListenable(applicationFailures);
    final provider = videoQualityProvider(deviceId: device.id);
    final query = ref.watch(provider);
    Future<void> refresh() => ref
        .refresh(provider.future)
        .then<void>((_) {}, onError: (Object _, StackTrace _) {});
    final settings = ref.watch(
      preferencesProvider.select((state) => state.values),
    );
    final preferences =
        settings.deviceSettings[device.id] ?? const DevicePreferences();
    Widget toggle(
      String title,
      IconData icon,
      bool enabled,
      DevicePreferences Function(bool) change,
    ) => ConnectSwitchRow(
      title: Text(title),
      icon: icon,
      value: enabled,
      onChanged: (next) async {
        try {
          await ref
              .read(preferencesProvider.notifier)
              .updateDevice(device.id, change(next));
        } catch (error) {
          if (context.mounted &&
              identical(ref.read(settingsManagementProvider), settingsOwner)) {
            feedback(context, '$error');
          }
        }
      },
    );
    return PageFrame(
      title: '画面与控制',
      child: GroupedListView(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        children: [
          const SectionTitle('画面与手机屏幕'),
          SettingsGroup(
            children: [
              toggle(
                '显示导航键',
                LucideIcons.navigation,
                preferences.showNavigationBar ?? true,
                (next) => DevicePreferences(showNavigationBar: next),
              ),
              toggle(
                '新画面启动时点亮屏幕',
                LucideIcons.sun,
                preferences.wakeOnConnect ?? true,
                (next) => DevicePreferences(wakeOnConnect: next),
              ),
              toggle(
                '关闭最后画面时熄屏',
                LucideIcons.moon,
                preferences.lockOnClose ?? false,
                (next) => DevicePreferences(lockOnClose: next),
              ),
              toggle(
                '保持手机唤醒',
                LucideIcons.alarmClock,
                preferences.stayAwake ?? false,
                (next) => DevicePreferences(stayAwake: next),
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
                onTap: () =>
                    chooseScreenRatio(context, ref, device.id, preferences),
              ),
            ],
          ),
          PageChromePadding(
            padding: EdgeInsets.zero,
            showRecovery: false,
            child: AsyncContent<VideoQualityOptions>(
              loading: query.isLoading,
              data: query.value,
              error: query.error,
              onRefresh: refresh,
              emptyTitle: '尚未获得可用的画面选项',
              builder: (context, data) {
                final current = data.current;
                final codecs = data.codecs;
                final codec = codecs
                    .where((item) => item.codec == current.codec)
                    .firstOrNull;
                final available = codec?.available ?? false;
                Future<void> apply(VideoQualityPatch patch) async {
                  if (!ownsQuality() || applying.value) return;
                  applying.value = true;
                  final result = await performAction(
                    context,
                    () => quality.changeVideoQuality(device.id, patch),
                  );
                  if (!context.mounted || !ownsQuality()) return;
                  applying.value = false;
                  if (result != null) {
                    applicationFailures.value = result.failures;
                    if (result.failures.isNotEmpty) {
                      feedback(
                        context,
                        '设置已保存，${result.failures.length} 个画面未能应用。',
                      );
                    }
                    await refresh();
                  }
                }

                Future<QualityChoice<T>?> pick<T>(
                  String title,
                  IconData icon,
                  List<QualityChoice<T>> options,
                  T selected,
                ) => showGlassModalSheet<QualityChoice<T>>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => QualityOptionsSheet<T>(
                    title: title,
                    icon: icon,
                    options: options,
                    selected: selected,
                  ),
                );

                Future<void> chooseCodec() async {
                  final picked = await pick('编码格式', LucideIcons.film, [
                    for (final item in codecs)
                      QualityChoice(
                        value: item.codec,
                        label: item.codec.name,
                        available: item.available,
                        reason: _codecReason(item),
                      ),
                  ], current.codec);
                  if (picked != null && context.mounted) {
                    await apply(
                      VideoQualityPatch(
                        codec: picked.value,
                        encoder: (name: null),
                      ),
                    );
                  }
                }

                Future<void> chooseEncoder() async {
                  final picked = await pick<String?>('视频编码器', LucideIcons.cpu, [
                    QualityChoice(
                      value: null,
                      label: '自动选择',
                      available: available,
                      reason: available
                          ? '由这台设备为所选格式选择编码器。'
                          : _codecReason(codec),
                    ),
                    for (final encoder in codec?.encoders ?? <VideoEncoder>[])
                      QualityChoice(
                        value: encoder.name,
                        label: encoder.name,
                        available: available,
                        reason: available
                            ? '已从这台设备枚举。实际配置仍取决于设备资源。'
                            : _codecReason(codec),
                      ),
                  ], current.encoder);
                  if (picked != null && context.mounted) {
                    await apply(
                      VideoQualityPatch(encoder: (name: picked.value)),
                    );
                  }
                }

                final fields = [
                  (
                    title: '分辨率上限',
                    icon: LucideIcons.monitor,
                    value: current.maxSize,
                    choices: data.maxSizes,
                    label: (int n) => '$n px',
                    patch: (int n) => VideoQualityPatch(maxSize: n),
                  ),
                  (
                    title: '帧率',
                    icon: LucideIcons.gauge,
                    value: current.maxFps,
                    choices: data.frameRates,
                    label: (int n) => '$n fps',
                    patch: (int n) => VideoQualityPatch(maxFps: n),
                  ),
                  (
                    title: '码率',
                    icon: LucideIcons.network,
                    value: current.bitRate,
                    choices: data.bitRates,
                    label: (int n) => '${n ~/ 1000000} Mbps',
                    patch: (int n) => VideoQualityPatch(bitRate: n),
                  ),
                ];
                return GroupedListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  children: [
                    if (applying.value) const ContentLoadingIndicator(),
                    for (final failure in applicationFailures.value)
                      StateNote('${failure.name}：${failure.reason}'),
                    const SectionTitle('画面质量'),
                    SettingsGroup(
                      children: [
                        for (final preset in data.presets)
                          ChoiceRow<VideoQualityPreset>(
                            value: preset,
                            groupValue: current.preset,
                            onChanged: applying.value || !available
                                ? null
                                : (next) {
                                    if (next != null) {
                                      apply(VideoQualityPatch(preset: next));
                                    }
                                  },
                            title: Text(switch (preset) {
                              .smooth => '流畅',
                              .balanced => '均衡',
                              .clear => '清晰',
                            }),
                            leading: const ListIconBadge(
                              icon: LucideIcons.gauge,
                              backgroundColor: DesignTokens.colorListIconMint,
                            ),
                          ),
                      ],
                    ),
                    const SectionTitle('详细画质'),
                    SettingsGroup(
                      children: [
                        for (final field in fields)
                          QualityOptionRow(
                            title: field.title,
                            icon: field.icon,
                            currentValue: field.label(field.value),
                            onTap: applying.value
                                ? null
                                : () async {
                                    if (field.choices.isEmpty) {
                                      feedback(
                                        context,
                                        '当前设备没有返回可选择的${field.title}选项',
                                      );
                                      return;
                                    }
                                    final picked = await pick(
                                      field.title,
                                      field.icon,
                                      [
                                        for (final n in field.choices)
                                          QualityChoice(
                                            value: n,
                                            label: field.label(n),
                                            available: available,
                                            reason: available
                                                ? ''
                                                : '请先选择双方可用的编码格式。',
                                          ),
                                      ],
                                      field.value,
                                    );
                                    if (picked != null && context.mounted) {
                                      await apply(field.patch(picked.value));
                                    }
                                  },
                          ),
                        QualityOptionRow(
                          title: '编码格式',
                          icon: LucideIcons.film,
                          currentValue: codec?.codec.name ?? current.codec.name,
                          onTap: applying.value || codecs.isEmpty
                              ? null
                              : chooseCodec,
                        ),
                        QualityOptionRow(
                          title: '视频编码器',
                          icon: LucideIcons.cpu,
                          currentValue: current.encoder ?? '自动',
                          onTap: applying.value || codec == null
                              ? null
                              : chooseEncoder,
                        ),
                      ],
                    ),
                    if (!available ||
                        codec?.decoder.evidence !=
                            VideoDecoderEvidence.verified)
                      StateNote(_codecReason(codec)),
                    if (data.activeSessions.isNotEmpty) ...[
                      const SectionTitle('正在使用的画面'),
                      for (final stream in data.activeSessions)
                        ActionRow(
                          icon: LucideIcons.monitor,
                          title: stream.name,
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
