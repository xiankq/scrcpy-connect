import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/workspace/gallery/preview/devices_workspace_gallery_preview_page.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

/// Controls plugin receipts without supplying decoded pixels or a native texture.
class _PlayerPlatform extends VideoPlayerPlatform {
  _PlayerPlatform({this.unavailable = false});
  final bool unavailable;
  final commands = <Map<String, Object?>>[];
  Duration position = Duration.zero;
  int? disposed;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => 41;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) async* {
    if (unavailable) {
      throw PlatformException(code: 'video_format', message: '受控播放器无法预览此视频格式。');
    }
    yield VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 78),
      size: const Size(1920, 1080),
    );
    yield VideoEvent(
      eventType: VideoEventType.bufferingUpdate,
      buffered: [DurationRange(Duration.zero, const Duration(seconds: 78))],
    );
  }

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand(key: ValueKey('controlled-platform-view'));

  @override
  Future<void> dispose(int playerId) async => disposed = playerId;

  @override
  Future<void> play(int playerId) async => commands.add({'command': 'play'});

  @override
  Future<void> pause(int playerId) async => commands.add({'command': 'pause'});

  @override
  Future<void> setVolume(int playerId, double volume) async =>
      commands.add({'command': 'volume', 'value': volume});

  @override
  Future<void> seekTo(int playerId, Duration value) async {
    position = value;
    commands.add({'command': 'seek', 'milliseconds': value.inMilliseconds});
  }

  @override
  Future<Duration> getPosition(int playerId) async => position;

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
}

void main() {
  for (final unavailable in [false, true]) {
    testWidgets(
      unavailable
          ? 'unavailable video offers its actual fallback'
          : 'initialized video keeps actual controls operable',
      (tester) async {
        final previous = VideoPlayerPlatform.instance;
        final platform = _PlayerPlatform(unavailable: unavailable);
        VideoPlayerPlatform.instance = platform;
        addTearDown(() => VideoPlayerPlatform.instance = previous);
        tester.view.physicalSize = const Size(402, 874);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 54, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 54, bottom: 34);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.resetPadding();
          tester.view.resetViewPadding();
        });
        final controller = createTestController((
          command, [
          params = const {},
        ]) async {
          if (command == 'media.preview') {
            return {
              'url': 'https://capture.invalid/forest.mp4',
              'mime': 'video/mp4',
            };
          }
          return {};
        });
        try {
          await tester.pumpWidget(
            RouterTestApp(
              controller: controller,
              theme: ConnectTokens.theme(Brightness.light),
              home: MediaPreviewPage(
                controller: controller,
                device: const {'id': 'phone', 'name': '我的手机'},
                file: const {
                  'path': '/sdcard/DCIM/森林片段.mp4',
                  'name': '森林片段.mp4',
                  'mime': 'video/mp4',
                },
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (unavailable) {
            expect(find.text('无法预览此视频格式'), findsOneWidget);
            expect(find.byType(VideoPlayer), findsNothing);
            expect(find.byType(Texture), findsNothing);
            expect(
              find.widgetWithText(FilledButton, '保存原文件').hitTestable(),
              findsOneWidget,
            );
          } else {
            expect(find.byType(VideoPlayer), findsOneWidget);
            expect(find.text('0:00 / 1:18'), findsOneWidget);
            expect(find.byTooltip('播放').hitTestable(), findsOneWidget);
            expect(find.byTooltip('静音').hitTestable(), findsOneWidget);
            expect(find.byType(Texture), findsNothing);

            platform.commands.clear();
            await tester.tap(find.byTooltip('播放'));
            await tester.pump();
            expect(find.byTooltip('暂停').hitTestable(), findsOneWidget);
            expect(platform.commands, contains(equals({'command': 'play'})));
            await tester.tap(find.byTooltip('静音'));
            await tester.pump();
            expect(find.byTooltip('打开声音').hitTestable(), findsOneWidget);
            expect(
              platform.commands,
              contains(equals({'command': 'volume', 'value': 0.0})),
            );

            final progress = tester.getRect(
              find.byType(VideoProgressIndicator),
            );
            await tester.tapAt(progress.center);
            await tester.pump();
            final seek = platform.commands
                .where((c) => c['command'] == 'seek')
                .last;
            expect(seek['milliseconds'], closeTo(39000, 1000));
            expect(find.text('0:39 / 1:18'), findsOneWidget);

            await tester.tap(find.byTooltip('打开声音'));
            await tester.pump();
            expect(
              platform.commands,
              contains(equals({'command': 'volume', 'value': 1.0})),
            );
            await tester.tap(find.byTooltip('暂停'));
            await tester.pump();
            expect(find.byTooltip('播放'), findsOneWidget);
            expect(platform.commands, contains(equals({'command': 'pause'})));
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          // Plugin stream cancellation finishes outside the test frame zone.
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          controller.dispose();
        }
        expect(platform.disposed, 41);
      },
    );
  }
}
