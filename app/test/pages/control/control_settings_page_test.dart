import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/control/control_capabilities_provider.dart';
import 'package:scrcpy_connect/core/control/video_quality_provider.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/recovery/recovery_state_notifier.dart';
import 'package:scrcpy_connect/core/settings/preferences_notifier.dart';
import 'package:scrcpy_connect/core/settings/settings_capabilities_provider.dart';
import 'package:scrcpy_connect/core/settings/settings_management.dart';
import 'package:scrcpy_connect/pages/control/settings/control_settings_page.dart';
import 'package:scrcpy_connect/styles/theme.dart';

import '../../support/fixed_state.dart';

void main() {
  testWidgets('窄屏大字下改帧率只保存帧率上限，取消不保存，清晰度保持原档位', (tester) async {
    tester.view
      ..physicalSize = const Size(320, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const device = DeviceSnapshot(id: 'phone');
    final quality = _Quality();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recoveryStateProvider.overrideWith(FixedRecovery.new),
          preferencesProvider.overrideWith(FixedPreferences.new),
          settingsManagementProvider.overrideWithValue(_Settings()),
          videoQualityControlProvider.overrideWithValue(quality),
          videoQualityProvider(deviceId: device.id)
              .overrideWith((_) => quality.readVideoQualityOptions(device.id)),
        ],
        child: MaterialApp(
          theme: ConnectTokens.theme(Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
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

    expect(quality.changes, [(device.id, const VideoQualityPatch(maxFps: 30))]);
    expect(find.text('30 FPS'), findsOneWidget);
    expect(find.text('90 FPS'), findsNothing);
    expect(find.text('1280P'), findsOneWidget);

    final clarityRow = find.text('清晰度');
    await Scrollable.ensureVisible(tester.element(clarityRow), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(clarityRow);
    await tester.pumpAndSettle();
    final currentSize = find.widgetWithText(ListTile, '1280P').last;
    expect(tester.widget<ListTile>(currentSize).selected, isTrue);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(quality.changes, hasLength(1));
  });
}

class _Quality implements VideoQualityControl {
  final changes = <(String, VideoQualityPatch)>[];
  var current = const VideoQuality(
    maxSize: 1280,
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

class _Settings implements SettingsManagement {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
