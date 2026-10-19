import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/workspace/gallery/preview/devices_workspace_gallery_preview_page.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'ios_pages_capture_test.dart' as capture;
import 'support/router_test_app.dart';
import 'support/test_controller.dart';

/// Controls plugin receipts only. The view deliberately supplies no decoded
/// image or native texture, so captures prove production chrome, not playback.
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

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundary,
  Brightness appearance,
  String state,
  _PlayerPlatform platform,
) async {
  final output = Platform.environment['CONNECT_VIDEO_CAPTURE_DIR'];
  if (output == null) return;
  final filename = 'video-${appearance.name}-$state';
  final layout = capture.captureLayout(boundary);
  await tester.runAsync(() async {
    final directory = await Directory(output).create(recursive: true);
    final image =
        await (boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    await File('${directory.path}/$filename.png').writeAsBytes(bytes);
    await File('${directory.path}/$filename.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({
        'capturedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'sourceState': platform.unavailable ? 'w4Qqmf' : 'OLDRn',
        'screenshot': '$filename.png',
        'screenshotSha256': sha256.convert(bytes).toString(),
        'appAppearance': appearance.name,
        'mediaAppearance': 'dark, as selected by production MediaPreviewPage',
        'state': state,
        'captureScope': 'production MediaPreviewPage and VideoPreview; controlled VideoPlayerPlatform receipts',
        'materialBackend': 'widget-test-fallback',
        'nativeDecodedPixelsSupplied': false,
        'platformView': 'transparent test view; background is production media ink',
        'safeArea': {'top': 54, 'bottom': 34},
        'playerCommands': platform.commands,
        ...layout,
      })}\n',
    );
    image.dispose();
  });
}

void main() {
  for (final appearance in Brightness.values) {
    for (final unavailable in [false, true]) {
      testWidgets(
        '${unavailable ? 'unavailable video offers its actual fallback' : 'initialized video keeps actual controls operable'} in ${appearance.name} appearance',
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
          if (Platform.environment.containsKey('CONNECT_VIDEO_CAPTURE_DIR')) {
            for (final font in [
              (
                'packages/lucide_icons_flutter/Lucide',
                'packages/lucide_icons_flutter/assets/lucide.ttf',
              ),
              ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
            ]) {
              await (FontLoader(
                font.$1,
              )..addFont(rootBundle.load(font.$2))).load();
            }
            final bytes = File(
              '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
            ).readAsBytesSync();
            for (final family in ['Roboto', 'ConnectCaptureCJK', 'Ahem']) {
              await (FontLoader(
                family,
              )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
            }
          }
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
          final boundary = GlobalKey();
          try {
            await tester.pumpWidget(
              RepaintBoundary(
                key: boundary,
                child: RouterTestApp(
                  controller: controller,
                  theme: capture.captureTheme(appearance),
                  home: MediaPreviewPage(
                    controller: controller,
                    device: capture.device,
                    file: const {
                      'path': '/sdcard/DCIM/森林片段.mp4',
                      'name': '森林片段.mp4',
                      'mime': 'video/mp4',
                    },
                  ),
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
              await _capture(
                tester,
                boundary,
                appearance,
                'unavailable',
                platform,
              );
            } else {
              expect(find.byType(VideoPlayer), findsOneWidget);
              expect(find.text('0:00 / 1:18'), findsOneWidget);
              expect(find.byTooltip('播放').hitTestable(), findsOneWidget);
              expect(find.byTooltip('静音').hitTestable(), findsOneWidget);
              expect(find.byType(Texture), findsNothing);
              await _capture(tester, boundary, appearance, 'paused', platform);

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
              await _capture(
                tester,
                boundary,
                appearance,
                'playing-muted-seek',
                platform,
              );

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
            // Stream cancellation may finish in the real async zone entered by
            // PNG capture; let that disposal receipt drain before restoring it.
            await tester.runAsync(() => Future<void>.delayed(Duration.zero));
            controller.dispose();
          }
          expect(platform.disposed, 41);
        },
      );
    }
  }
}
