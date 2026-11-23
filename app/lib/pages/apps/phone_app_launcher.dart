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
import 'package:scrcpy_connect/core/settings/preferences_notifier.dart';
import 'package:scrcpy_connect/core/settings/settings_capabilities_provider.dart';
import 'package:scrcpy_connect/core/media/video_sessions.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/router/remote_windows.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/overlays.dart';

Future<void> openPhoneApp(
  BuildContext context,
  WidgetRef ref,
  DeviceSnapshot device,
  DeviceApp app, {
  bool changeMode = false,
  bool existingTask = false,
}) async {
  final deviceId = device.id;
  final package = app.packageName;
  final videos = ref.read(videoSessionsProvider);
  final settings = ref.read(settingsManagementProvider);
  final claims = ref.read(appOpenClaimsProvider);
  bool ownsScope() =>
      context.mounted &&
      !claims.closed &&
      identical(ref.read(videoSessionsProvider), videos) &&
      identical(ref.read(settingsManagementProvider), settings);
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

    var list = await sessions();
    if (!context.mounted || !ownsScope()) return;
    final unknown = pending(list);
    if (unknown != null) {
      await openRecord(unknown);
      return;
    }
    final active = retained(list);
    if (active != null && !changeMode) {
      await openRecord(active);
      return;
    }
    final api = int.tryParse(
      ((ref
                      .read(deviceListProvider)
                      .devices
                      .where((item) => item.id == device.id)
                      .firstOrNull ??
                  device)
              .apiLevel
              ?.toString() ??
          ''),
    );
    var mode = ref
        .read(preferencesProvider)
        .values
        .appOpenModes[deviceId]?[package];
    final choose =
        changeMode ||
        mode == null ||
        mode == AppOpenMode.window && (api == null || api < 29);
    if (choose) {
      mode = await _chooseMode(
        context,
        app,
        windowAvailable: api == null || api >= 29,
      );
      if (mode == null || !context.mounted || !ownsScope()) return;
      list = await sessions();
      if (!context.mounted || !ownsScope()) return;
      final unknown = pending(list);
      if (unknown != null) {
        await openRecord(unknown);
        return;
      }
    }
    final current = retained(list);
    if ((current != null && mode == AppOpenMode.phone ||
            mode == AppOpenMode.window && existingTask && current == null) &&
        !await confirm(
          context,
          '切换应用打开方式？',
          '这可能移动手机上已有的应用任务，原画面可能随之改变。',
          action: '继续打开',
        )) {
      return;
    }
    if (!context.mounted || !ownsScope()) return;
    if (choose) {
      await ref
          .read(preferencesProvider.notifier)
          .rememberAppOpenMode(deviceId, package, mode);
      if (!context.mounted || !ownsScope()) return;
    }
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
        if (!await close()) return;
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
  DeviceApp app, {
  required bool windowAvailable,
}) => showAppModalSheet<AppOpenMode>(
  context: context,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(app.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: DesignTokens.spacingSm),
            FilledButton(
              onPressed: () => Navigator.pop(context, AppOpenMode.phone),
              child: const Text('在手机屏幕打开'),
            ),
            const SizedBox(height: DesignTokens.spacingSm),
            Tooltip(
              message: windowAvailable ? '' : '此设备当前不支持独立应用画面',
              child: OutlinedButton(
                onPressed: windowAvailable
                    ? () => Navigator.pop(context, AppOpenMode.window)
                    : null,
                child: const Text('打开独立应用画面'),
              ),
            ),
            const SizedBox(height: DesignTokens.spacingXs),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    ),
  ),
);
