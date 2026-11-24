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
import 'package:scrcpy_connect/widgets/dialogs.dart' show feedback;
import 'package:scrcpy_connect/widgets/overlays.dart';

Future<void> openPhoneApp(
  BuildContext context,
  WidgetRef ref,
  DeviceSnapshot device,
  DeviceApp app,
) async {
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
      app,
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
  DeviceApp app, {
  required bool hasIndependentWindow,
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
              child: Text(hasIndependentWindow ? '移回手机屏幕' : '在手机屏幕中打开'),
            ),
            const SizedBox(height: DesignTokens.spacingSm),
            Tooltip(
              message: windowAvailable ? '' : '此设备当前不支持独立应用画面',
              child: OutlinedButton(
                onPressed: windowAvailable
                    ? () => Navigator.pop(context, AppOpenMode.window)
                    : null,
                child: Text(hasIndependentWindow ? '切回独立应用' : '打开独立应用画面'),
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
