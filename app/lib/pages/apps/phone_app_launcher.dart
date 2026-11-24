import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/devices/device_apps.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/control/app_open_claims_provider.dart';
import 'package:scrcpy_connect/core/media/media_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/media/video_sessions.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/router/remote_windows.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/adaptive_window.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart' show feedback;
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/overlays.dart';

Future<void> openPhoneApp(
  BuildContext context,
  WidgetRef ref,
  DeviceSnapshot device,
  DeviceApp app, {
  BuildContext? source,
}) async {
  final deviceId = device.id;
  final package = app.packageName;
  final videos = ref.read(videoSessionsProvider);
  final claims = ref.read(appOpenClaimsProvider);
  bool ownsScope() =>
      !claims.closed && identical(ref.read(videoSessionsProvider), videos);
  final release = claims.claim(deviceId, package);
  if (release == null) return;
  try {
    Future<List<VideoSessionView>> sessions() =>
        videos.readVideoSessions(deviceId: deviceId);
    VideoSessionView? pending(List<VideoSessionView> list) => list
        .where(
          (view) =>
              view.session.packageName == package &&
              view.session.launchOutcome == VideoLaunchOutcome.unknown,
        )
        .firstOrNull;
    VideoSessionView? retained(List<VideoSessionView> list) => list
        .where(
          (view) =>
              view.session.packageName == package &&
              !view.session.recordOnly &&
              !{
                VideoSessionStatus.stopped,
                VideoSessionStatus.failed,
              }.contains(view.session.status),
        )
        .firstOrNull;
    Future<void> openRecord(VideoSessionView record) => openRemoteRoute(
      context,
      deviceId: deviceId,
      sessionId: record.sessionId,
      appName: app.name,
    );

    final list = await sessions();
    if (!context.mounted || !ownsScope()) return;
    final unknown = pending(list);
    if (unknown != null) {
      await openRecord(unknown);
      return;
    }
    final active = retained(list);
    final api =
        ref
            .read(deviceListProvider)
            .devices
            .where((item) => item.id == deviceId)
            .firstOrNull
            ?.apiLevel ??
        device.apiLevel;
    final mode = await _chooseMode(
      context,
      app.name,
      deviceName(device),
      source: source,
      hasIndependentWindow: active != null,
      windowAvailable: active != null || api == null || api >= 29,
    );
    if (mode == null || !context.mounted || !ownsScope()) return;
    final latest = await sessions();
    if (!context.mounted || !ownsScope()) return;
    final unverified = pending(latest);
    if (unverified != null) {
      await openRecord(unverified);
      return;
    }
    final current = retained(latest);
    if (current != null && mode == AppOpenMode.window) {
      await openRecord(current);
      return;
    }
    if (current != null && mode == AppOpenMode.phone) {
      final windows = RemoteWindows.maybeOf(context);
      final pane = windows?.windowFor((
        deviceId: deviceId,
        packageName: package,
      ));
      if (pane?.close case final close?) {
        if (!await close(movingToPhone: true)) return;
      } else {
        await videos.stopVideo(ControlTarget(sessionId: current.sessionId));
        if (pane != null && windows?.mounted == true) windows!.remove(pane);
      }
      if (!context.mounted || !ownsScope()) return;
    }
    await openRemoteRoute(
      context,
      deviceId: deviceId,
      packageName: package,
      appName: app.name,
      onPhoneScreen: mode == AppOpenMode.phone,
    );
  } catch (error) {
    if (context.mounted && ownsScope()) {
      feedback(
        context,
        failureMessage(error, fallback: '暂时无法确认应用是否已打开。请先查看手机屏幕。'),
      );
    }
  } finally {
    release();
  }
}

Future<AppOpenMode?> _chooseMode(
  BuildContext context,
  String appName,
  String device, {
  required bool hasIndependentWindow,
  required bool windowAvailable,
  BuildContext? source,
}) {
  final theme = Theme.of(context);
  final phone = hasIndependentWindow ? '移回手机屏幕' : '在手机屏幕中打开';
  final window = hasIndependentWindow ? '切回独立应用' : '打开独立应用画面';
  final anchor = source?.mounted == true ? source!.findRenderObject() : null;
  if (hasIndependentWindow && anchor is RenderBox && anchor.hasSize) {
    final navigator = Navigator.of(context, rootNavigator: true);
    return liquid.showGlassContextMenu<AppOpenMode>(
      context: context,
      targetRect: anchor.localToGlobal(Offset.zero) & anchor.size,
      menuWidth: DesignTokens.componentAppContinuationMenuWidth,
      borderRadius: DesignTokens.componentMenuRounded,
      rowBorderRadius: DesignTokens.componentMenuItemRounded,
      settings: GlassMaterial.settings(context, variant: GlassVariant.menu),
      quality: GlassMaterial.quality(context),
      barrierColor: theme.brightness == Brightness.dark
          ? DesignTokens.componentModalScrimDarkBackgroundColor
          : DesignTokens.componentModalScrimBackgroundColor,
      actions: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            DesignTokens.componentMenuItemPadding,
            DesignTokens.spacingXxs,
            DesignTokens.componentMenuItemPadding,
            DesignTokens.spacingXs,
          ),
          child: Text(appName, style: theme.textTheme.titleMedium),
        ),
        for (final (mode, label, icon) in [
          (AppOpenMode.phone, phone, AppIcons.navigationDevices),
          (AppOpenMode.window, window, LucideIcons.panelsTopLeft),
        ])
          liquid.GlassMenuItem(
            title: label,
            height: DesignTokens.componentMenuItemHeight,
            titleStyle: theme.textTheme.labelLarge,
            icon: Icon(icon),
            iconColor: theme.colorScheme.onSurface,
            iconSize: DesignTokens.componentMenuItemSize,
            onTap: () => navigator.pop(mode),
          ),
      ],
    );
  }

  Widget actions(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: DesignTokens.spacingXs,
    children: [
      FilledButton(
        onPressed: () => Navigator.pop(context, AppOpenMode.phone),
        child: Text(phone, textAlign: TextAlign.center),
      ),
      OutlinedButton(
        onPressed: windowAvailable
            ? () => Navigator.pop(context, AppOpenMode.window)
            : null,
        child: Text(window, textAlign: TextAlign.center),
      ),
      if (!windowAvailable)
        Text('此设备当前不支持独立应用画面', style: theme.textTheme.bodySmall),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
    ],
  );
  final environment = windowEnvironmentOf(context);
  final width =
      environment.width - environment.insets.left - environment.insets.right;
  final centered =
      environment.isDesktopWindow ||
      WindowEnvironment.sizeClassFor(width) != WindowSizeClass.compact;
  return centered
      ? showAppDialog<AppOpenMode>(
          context: context,
          builder: (context) => AppAlertDialog(
            glass: true,
            title: Text(appName),
            content: Text(device),
            actions: [actions(context)],
          ),
        )
      : showAppModalSheet<AppOpenMode>(
          context: context,
          builder: (context) => SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(DesignTokens.spacingMd),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(appName, style: theme.textTheme.titleLarge),
                  const SizedBox(height: DesignTokens.spacingXxs),
                  Text(device, style: theme.textTheme.bodySmall),
                  const SizedBox(height: DesignTokens.spacingMd),
                  actions(context),
                ],
              ),
            ),
          ),
        );
}
