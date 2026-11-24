import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/core/platform/background_status_provider.dart';
import 'package:scrcpy_connect/core/platform/platform_capabilities_provider.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';
import 'package:scrcpy_connect/core/settings/preferences_notifier.dart';
import 'package:scrcpy_connect/core/settings/settings_capabilities_provider.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/choice_picker.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/form_controls.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:scrcpy_connect/widgets/system_notifications.dart';

import 'widgets/settings_row.dart';

class SettingsPage extends HookConsumerWidget {
  const SettingsPage({super.key, this.embedded = false});
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(preferencesProvider);
    final settings = preferences.values;
    final owner = ref.watch(settingsManagementProvider);
    final controller = ref.watch(backgroundControlProvider);
    final background = ref.watch(backgroundStatusProvider);
    final alerts = useSystemNotifications(context, ref);
    useStream(alerts.changes);
    final infoReader = ref.watch(appInfoReaderProvider);
    final info = useFuture(useMemoized(infoReader, [infoReader]));
    final busy = useValueNotifier(false, [owner, controller, alerts]);
    useValueListenable(busy);

    bool current() =>
        context.mounted &&
        identical(owner, ref.read(settingsManagementProvider)) &&
        identical(controller, ref.read(backgroundControlProvider));

    Future<void> update(Future<void> Function() operation) async {
      if (busy.value) return;
      busy.value = true;
      try {
        await operation();
      } catch (error) {
        if (context.mounted && current()) {
          feedback(context, failureMessage(error, fallback: '无法保存设置。请重试。'));
        }
      } finally {
        if (current()) busy.value = false;
      }
    }

    Future<void> save(PreferenceChanges changes) =>
        ref.read(preferencesProvider.notifier).update(changes);

    Future<void> setAlert(
      bool enabled, {
      required bool isCall,
    }) => update(() async {
      if (enabled) {
        var status = await alerts.refreshStatus();
        if (!context.mounted || !current()) return;
        final requested = status.permissionGranted != true && status.canRequest;
        if (requested) {
          status = await alerts.requestPermission();
          if (!context.mounted || !current()) return;
        }
        final channelEnabled = isCall
            ? status.callChannelEnabled
            : status.notificationChannelEnabled;
        if (status.permissionGranted != true || channelEnabled == false) {
          if (!requested && status.canOpenSettings) {
            if (!await alerts.openSettings() && context.mounted && current()) {
              feedback(context, '请在系统设置中允许提醒。');
            }
          } else {
            feedback(
              context,
              status.reason.isEmpty ? '系统暂未允许提醒。' : status.reason,
            );
          }
          return;
        }
      }
      await save(
        isCall
            ? PreferenceChanges(callAlerts: enabled)
            : PreferenceChanges(notificationAlerts: enabled),
      );
    });

    Future<void> setBackground(bool enabled) => update(() async {
      final result = await controller.requestBackground(
        enabled: enabled,
        askNotificationPermission: enabled,
      );
      if (!context.mounted || !current()) return;
      ref.invalidate(backgroundStatusProvider);
      if (enabled && (result.requested == false || result.stopped)) {
        feedback(context, '无法在后台保持连接。请让应用保持在前台。');
        return;
      }
      await save(PreferenceChanges(backgroundKeepAlive: enabled));
    });

    useEffect(() {
      final listener = AppLifecycleListener(
        onResume: () {
          ref.invalidate(backgroundStatusProvider);
          alerts.refreshStatus();
        },
      );
      return listener.dispose;
    }, [alerts]);

    final enabled = !busy.value && preferences.error == null;
    final status = background.value;
    final alertStatus = alerts.status;
    final appearance = ConnectSegmentedControl<Appearance>(
      options: const [
        (Appearance.system, '系统'),
        (Appearance.light, '浅色'),
        (Appearance.dark, '深色'),
      ],
      selected: settings.appearance,
      onSelected: enabled
          ? (next) => update(() => save(PreferenceChanges(appearance: next)))
          : null,
    );
    final platformEffects = platformGlassEffects(Theme.of(context).platform);
    Future<void> chooseGlassEffects() async {
      final selected = await showChoicePicker<GlassEffects>(
        context: context,
        title: '液态玻璃',
        options: GlassEffects.values,
        label: (mode) => mode == GlassEffects.automatic
            ? '跟随平台（${_glassEffectsLabel(platformEffects)}）'
            : _glassEffectsLabel(mode),
        isSelected: (mode) => settings.glassEffects == mode,
      );
      if (selected == null || selected == settings.glassEffects || !current()) {
        return;
      }
      await update(() => save(PreferenceChanges(glassEffects: selected)));
    }

    void openBackground() => const BackgroundRoute().push<void>(context);
    Widget heading(String label) => Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        DesignTokens.spacingXs,
        DesignTokens.spacingSm,
        0,
        DesignTokens.spacingXs,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall,
        semanticsLabel: label,
      ),
    );
    return PageFrame(
      root: embedded,
      title: '设置',
      child: GroupedListView(
        padding: const EdgeInsets.fromLTRB(
          DesignTokens.spacingMd,
          0,
          DesignTokens.spacingMd,
          DesignTokens.spacingLg,
        ),
        children: [
          if (preferences.error case final error?) StateNote(error),
          heading('使用偏好'),
          SettingsGroup(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final room =
                      constraints.maxWidth /
                      MediaQuery.textScalerOf(context).scale(1);
                  return room >= 300
                      ? SettingsRow(
                          compact: true,
                          icon: LucideIcons.sun,
                          color: DesignTokens.colorListIconAmber,
                          title: '外观',
                          trailing: SizedBox(
                            width:
                                DesignTokens.componentAppearanceSelectorWidth,
                            child: appearance,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SettingsRow(
                              compact: true,
                              icon: LucideIcons.sun,
                              color: DesignTokens.colorListIconAmber,
                              title: '外观',
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                DesignTokens.spacingMd,
                                0,
                                DesignTokens.spacingMd,
                                DesignTokens.spacingXs,
                              ),
                              child: appearance,
                            ),
                          ],
                        );
                },
              ),
              SettingsRow(
                compact: true,
                icon: LucideIcons.layers,
                color: DesignTokens.colorListIconBlue,
                title: '液态玻璃',
                value: _glassEffectsLabel(settings.glassEffects),
                onTap: enabled ? chooseGlassEffects : null,
              ),
              SettingsRow(
                compact: true,
                icon: LucideIcons.appWindow,
                color: DesignTokens.colorListIconMint,
                title: '后台保持',
                trailing: status?.supported == false
                    ? Text('不支持', style: Theme.of(context).textTheme.bodySmall)
                    : ConnectSwitch(
                        value: settings.backgroundKeepAlive,
                        onChanged:
                            enabled &&
                                status?.supported == true &&
                                (status!.canRequest ||
                                    settings.backgroundKeepAlive)
                            ? setBackground
                            : null,
                      ),
              ),
              SettingsRow(
                compact: true,
                icon: LucideIcons.bell,
                color: DesignTokens.colorListIconCoral,
                title: '通知提醒',
                trailing: ConnectSwitch(
                  value: settings.notificationAlerts,
                  onChanged:
                      enabled &&
                          (alertStatus.supported || settings.notificationAlerts)
                      ? (value) => setAlert(value, isCall: false)
                      : null,
                ),
              ),
              SettingsRow(
                compact: true,
                icon: LucideIcons.phone,
                color: DesignTokens.colorListIconCoral,
                title: '来电提醒',
                trailing: ConnectSwitch(
                  value: settings.callAlerts,
                  onChanged:
                      enabled && (alertStatus.supported || settings.callAlerts)
                      ? (value) => setAlert(value, isCall: true)
                      : null,
                ),
              ),
              SettingsRow(
                compact: true,
                icon: LucideIcons.shieldCheck,
                color: DesignTokens.colorListIconMint,
                title: '后台运行',
                onTap: openBackground,
              ),
            ],
          ),
          heading('本机数据'),
          SettingsGroup(
            children: [
              SettingsRow(
                compact: true,
                icon: LucideIcons.hardDrive,
                color: DesignTokens.colorListIconSlate,
                title: '媒体暂存',
                onTap: () => const MediaCacheRoute().push<void>(context),
              ),
              SettingsRow(
                compact: true,
                icon: LucideIcons.archiveRestore,
                color: DesignTokens.colorListIconPurple,
                title: '设备记录与恢复',
                onTap: () => const DataPreferencesRoute().push<void>(context),
              ),
              SettingsRow(
                compact: true,
                icon: LucideIcons.keyRound,
                color: DesignTokens.colorListIconMint,
                title: '授权密钥',
                onTap: () => const AdbIdentityRoute().push<void>(context),
              ),
              SettingsRow(
                compact: true,
                icon: LucideIcons.fileText,
                color: DesignTokens.colorListIconUtility,
                title: '运行日志',
                onTap: () => const RuntimeLogsRoute().push<void>(context),
              ),
              SettingsRow(
                compact: true,
                icon: LucideIcons.circleHelp,
                color: DesignTokens.colorListIconUtility,
                title: '关于与更新',
                value: info.data?.version,
                onTap: () => const AppUpdatesRoute().push<void>(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _glassEffectsLabel(GlassEffects mode) => switch (mode) {
  GlassEffects.automatic => '跟随平台',
  GlassEffects.premium => '极致',
  GlassEffects.standard => '标准',
  GlassEffects.off => '关闭',
};
