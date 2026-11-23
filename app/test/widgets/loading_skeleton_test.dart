import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/motion.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/async_content.dart';
import 'package:scrcpy_connect/widgets/content_arrival.dart';
import 'package:scrcpy_connect/widgets/loading_skeleton.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('$brightness 骨架只改变占位像素，减少动态时保持静止', (tester) async {
      final boundaryKey = GlobalKey();
      final reduced = ValueNotifier(false);
      addTearDown(reduced.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: ConnectTokens.theme(brightness),
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: reduced,
              builder: (context, value, _) => MediaQuery(
                data: MediaQuery.of(context).copyWith(reduceMotion: value),
                child: Center(
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: const SizedBox(
                      width: 240,
                      child: LoadingSkeleton(
                        child: SkeletonBlock(width: 240, height: 40),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(SkeletonBlock), findsNothing);
      await tester.pump(skeletonDelay);
      await tester.pump();

      Future<int> centerPixel() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = boundary.toImageSync();
        try {
          final bytes = await tester.runAsync(
            () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
          );
          return bytes!.getUint32((20 * image.width + 120) * 4);
        } finally {
          image.dispose();
        }
      }

      final first = await centerPixel();
      final shape = tester.getRect(find.byType(SkeletonBlock));
      await tester.pump(const Duration(milliseconds: 360));
      expect(await centerPixel(), isNot(first));
      expect(tester.getRect(find.byType(SkeletonBlock)), shape);

      reduced.value = true;
      await tester.pump();
      final still = await centerPixel();
      await tester.pump(const Duration(milliseconds: 360));
      expect(await centerPixel(), still);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('骨架完成后原位淡入内容，刷新保留同一内容和交互', (tester) async {
    final state = ValueNotifier((loading: true, data: null as String?));
    addTearDown(state.dispose);
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: state,
            builder: (context, value, _) => AsyncContent<String>(
              loading: value.loading,
              data: value.data,
              error: null,
              loadingPlaceholder: const LoadingSkeleton(
                child: SkeletonBlock(width: 240, height: 40),
              ),
              onRefresh: () {},
              builder: (_, data) =>
                  TextButton(onPressed: () => taps++, child: Text(data)),
            ),
          ),
        ),
      ),
    );
    await tester.pump(skeletonDelay);
    expect(find.byType(SkeletonBlock), findsOneWidget);
    state.value = (loading: false, data: '文件准备完成');
    await tester.pump();
    final label = find.text('文件准备完成');
    final fade = find.descendant(
      of: find.byType(ContentArrival),
      matching: find.byType(FadeTransition),
    );
    expect(tester.widget<FadeTransition>(fade).opacity.value, lessThan(1));
    final position = tester.getRect(label);
    await tester.tap(label);
    expect(taps, 1);
    await tester.pumpAndSettle();
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
    state.value = (loading: true, data: '文件准备完成');
    await tester.pump();
    expect(find.byType(SkeletonBlock), findsNothing);
    expect(tester.getRect(label), position);
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
  });
}
