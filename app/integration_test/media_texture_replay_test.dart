import 'dart:ffi';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_codec/media_codec.dart';

/// 经真实解码器与 Windows 纹理重放固定 AV1 夹具；无需设备、ADB 服务、应用运行时或平台窗口像素。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('isolated decoded textures survive repeated creation', (
    tester,
  ) async {
    const libraryPath = String.fromEnvironment('MEDIA_CODEC_REPLAY_LIBRARY');
    expect(
      libraryPath,
      isNotEmpty,
      reason: 'Build the test-only replay library',
    );
    final library = DynamicLibrary.open(libraryPath);
    // 仅转发符号地址，Dart 不调用原生 SinkV1 ABI。
    final attach = library.lookup<Void>('replay_attach').address;
    final detach = library.lookup<Void>('replay_detach').address;
    final rounds = <Map<String, Object?>>[];
    binding.reportData = {'textureReplay': rounds};
    for (var round = 0; round < 3; round++) {
      final controller = MediaCodecController.video();
      try {
        await tester.runAsync(
          () => controller.open(
            MediaCodecSource(
              codec: 'av1',
              sourceId: 'offline-texture-replay',
              generation: round + 1,
              width: 320,
              height: 240,
              attachAddress: attach,
              detachAddress: detach,
            ),
          ),
        );
        final key = GlobalKey();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: 320,
                  height: 240,
                  child: Texture(textureId: controller.textureId!),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          final deadline = Stopwatch()..start();
          while (true) {
            final status = await controller.refresh();
            if ((status['frameCount'] as int) >= 24) break;
            if (deadline.elapsed > const Duration(seconds: 5)) {
              throw StateError(
                'The replay did not decode all 24 frames: $status',
              );
            }
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        });
        await tester.pump();
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        try {
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final colors = data.buffer
              .asUint32List(data.offsetInBytes, data.lengthInBytes ~/ 4)
              .toSet()
              .length;
          rounds.add({'round': round, 'flutterTextureColors': colors});
          expect(
            colors,
            greaterThan(8),
            reason: 'The isolated Flutter texture must contain fixture pixels',
          );
        } finally {
          image.dispose();
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(controller.dispose);
      }
    }
    debugPrint('[media-texture-replay] $rounds');
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);
}
