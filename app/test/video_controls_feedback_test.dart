import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/workspace/gallery/preview/widgets/video_preview.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _PlayerPlatform extends VideoPlayerPlatform {
  final commands = <String>[];
  Duration position = Duration.zero;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => 42;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) async* {
    yield VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 100),
      size: const Size(1920, 1080),
    );
  }

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand();

  @override
  Future<void> dispose(int playerId) async {}

  @override
  Future<void> play(int playerId) async => commands.add('play');

  @override
  Future<void> pause(int playerId) async => commands.add('pause');

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> seekTo(int playerId, Duration value) async {
    position = value;
    commands.add('seek');
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
  for (final reduceMotion in [false, true]) {
    testWidgets(
      'video glass feedback preserves cancellation, playback and scrubbing with reduceMotion=$reduceMotion',
      (tester) async {
        final previous = VideoPlayerPlatform.instance;
        final platform = _PlayerPlatform();
        VideoPlayerPlatform.instance = platform;
        addTearDown(() => VideoPlayerPlatform.instance = previous);
        tester.view.physicalSize = const Size(402, 874);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: ConnectTokens.theme(Brightness.dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: reduceMotion),
              child: child!,
            ),
            home: Scaffold(
              body: VideoPreview(
                source: 'https://test.invalid/clip.mp4',
                fallback: () => fail('The initialized player must stay usable'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final feedback = find.ancestor(
          of: find.byType(VideoProgressIndicator),
          matching: find.byType(GlassPressFeedback),
        );
        expect(feedback, findsOneWidget);
        final transform = find.descendant(
          of: feedback,
          matching: find.byWidgetPredicate(
            (widget) => widget is Transform && !widget.transformHitTests,
          ),
        );
        double scale() =>
            tester.widget<Transform>(transform).transform.entry(0, 0);
        final play = find.byTooltip('播放');
        final bounds = tester.getRect(play);
        final feedbackBounds = tester.getRect(feedback);
        platform.commands.clear();
        final press = await tester.startGesture(bounds.center);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(scale(), reduceMotion ? 1 : greaterThan(1));
        expect(tester.getRect(feedback), feedbackBounds);
        expect(tester.getSize(play), bounds.size);
        await press.cancel();
        await tester.pumpAndSettle();
        expect(scale(), closeTo(1, .001));
        expect(platform.commands, isNot(contains('play')));

        await tester.tap(play);
        await tester.pump();
        expect(platform.commands, contains('play'));
        expect(find.byTooltip('暂停'), findsOneWidget);
        final progress = tester.getRect(find.byType(VideoProgressIndicator));
        final drag = await tester.startGesture(
          Offset(progress.left + progress.width * .2, progress.center.dy),
        );
        await drag.moveTo(
          Offset(progress.left + progress.width * .4, progress.center.dy),
        );
        await tester.pump();
        await drag.moveTo(
          Offset(progress.left + progress.width * .75, progress.center.dy),
        );
        await tester.pump();
        await drag.up();
        await tester.pump();
        expect(platform.commands, contains('seek'));
        expect(platform.position.inMilliseconds, closeTo(75000, 1000));
        await tester.tap(find.byTooltip('暂停'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('播放'), findsOneWidget);
        expect(scale(), closeTo(1, .001));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
}
