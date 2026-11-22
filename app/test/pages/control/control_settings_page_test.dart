import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/control/control_capabilities_provider.dart';
import 'package:scrcpy_connect/core/control/video_quality_provider.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_state.dart';
import 'package:scrcpy_connect/core/recovery/recovery_state_notifier.dart';
import 'package:scrcpy_connect/core/settings/models/preferences_state.dart';
import 'package:scrcpy_connect/core/settings/preferences_notifier.dart';
import 'package:scrcpy_connect/core/settings/settings_capabilities_provider.dart';
import 'package:scrcpy_connect/core/settings/settings_management.dart';
import 'package:scrcpy_connect/pages/control/settings/control_settings_page.dart';
import 'package:scrcpy_connect/styles/theme.dart';

void main() {
  for (final (name, size, brightness, textScale) in [
    ('浅色', const Size(390, 844), Brightness.light, 1.0),
    ('深色窄屏大字', const Size(320, 800), Brightness.dark, 2.0),
  ]) {
    testWidgets('$name：帧率弹层保留当前值，单独保存帧率上限', (tester) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const device = DeviceSnapshot(id: 'phone');
      final quality = _Quality();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recoveryStateProvider.overrideWith(_Recovery.new),
            preferencesProvider.overrideWith(_Preferences.new),
            settingsManagementProvider.overrideWithValue(_Settings()),
            videoQualityControlProvider.overrideWithValue(quality),
            videoQualityProvider(
              deviceId: device.id,
            ).overrideWith((_) => quality.readVideoQualityOptions(device.id)),
          ],
          child: MaterialApp(
            theme: ConnectTokens.theme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: const ControlSettingsPage(device: device),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rateRow = find.text('帧率上限');
      await tester.scrollUntilVisible(
        rateRow,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(tester.element(rateRow), alignment: 0.5);
      await tester.pumpAndSettle();
      expect(find.text('90 FPS'), findsOneWidget);
      await tester.tap(rateRow);
      await tester.pumpAndSettle();
      expect(find.text('30 FPS'), findsOneWidget);
      expect(find.text('60 FPS'), findsOneWidget);
      final selected = find.widgetWithText(ListTile, '90 FPS').last;
      expect(tester.widget<ListTile>(selected).selected, isTrue);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(quality.changes, isEmpty);

      await tester.tap(rateRow);
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 FPS'));
      await tester.pumpAndSettle();

      expect(quality.changes, [
        (device.id, const VideoQualityPatch(maxFps: 30)),
      ]);
      expect(find.text('30 FPS'), findsOneWidget);
      expect(find.text('90 FPS'), findsNothing);
      expect(find.text('1080P（清晰）'), findsOneWidget);
    });
  }
}

class _Quality implements VideoQualityControl {
  final changes = <(String, VideoQualityPatch)>[];
  var current = const VideoQuality(
    maxSize: 1080,
    maxFps: 90,
    bitRate: 4000000,
    codec: VideoCodec.h264,
  );

  @override
  Future<VideoQualityOptions> readVideoQualityOptions(String deviceId) async =>
      VideoQualityOptions(
        current: current,
        codecs: const [
          VideoCodecOption(
            codec: VideoCodec.h264,
            encoders: [VideoEncoder(codec: VideoCodec.h264, name: 'h264')],
            decoder: VideoDecoderCapability(
              codec: VideoCodec.h264,
              evidence: VideoDecoderEvidence.verified,
              canAttempt: true,
              reason: '',
            ),
          ),
        ],
        activeSessions: [],
      );

  @override
  Future<VideoQualityApplication> changeVideoQuality(
    String deviceId,
    VideoQualityPatch patch,
  ) async {
    changes.add((deviceId, patch));
    current = current.copyWith(maxFps: patch.maxFps!);
    return VideoQualityApplication(
      current: current,
      appliedToAll: true,
      appliedSessions: [],
      failures: [],
      skippedSessions: [],
      reason: '',
    );
  }
}

class _Preferences extends PreferencesNotifier {
  @override
  PreferencesState build() => PreferencesState();
}

class _Settings implements SettingsManagement {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Recovery extends RecoveryStateNotifier {
  @override
  RecoveryState build() => RecoveryState();
}
