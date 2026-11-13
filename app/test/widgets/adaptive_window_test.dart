import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/platform/window_environment.dart';
import 'package:scrcpy_connect/widgets/adaptive_window.dart';

void main() {
  testWidgets('projects MediaQuery fold posture without a host override', (
    tester,
  ) async {
    WindowEnvironment? observed;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: const Size(700, 500),
          displayFeatures: const [
            DisplayFeature(
              bounds: Rect.fromLTWH(349, 0, 2, 500),
              type: DisplayFeatureType.fold,
              state: DisplayFeatureState.postureHalfOpened,
            ),
          ],
        ),
        child: Builder(
          builder: (context) {
            observed = context.windowEnvironment;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(observed?.posture, WindowPosture.book);
    expect(observed?.displayFeatures.single.state, WindowPosture.book);
  });

  testWidgets('merges host posture with the live Flutter view size', (
    tester,
  ) async {
    WindowEnvironment? observed;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(700, 500)),
        child: WindowEnvironmentScope(
          readHostEnvironment: () async => const WindowEnvironment(
            width: 1200,
            height: 800,
            windowId: 'stage-7',
            mode: WindowMode.split,
            posture: WindowPosture.book,
            displayFeatures: [
              WindowDisplayFeature(
                left: 349,
                top: 0,
                width: 2,
                height: 500,
                type: WindowDisplayFeatureType.hinge,
              ),
            ],
          ),
          child: Builder(
            builder: (context) {
              observed = context.windowEnvironment;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(observed?.width, 700);
    expect(observed?.height, 500);
    expect(observed?.windowId, 'stage-7');
    expect(observed?.mode, WindowMode.split);
    expect(observed?.posture, WindowPosture.book);
    expect(observed?.verticalPaneDivider, isNotNull);
  });

  testWidgets('refreshes host posture when the window metrics change', (
    tester,
  ) async {
    var posture = WindowPosture.normal;
    var reads = 0;
    WindowEnvironment? observed;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(700, 500)),
        child: WindowEnvironmentScope(
          readHostEnvironment: () async {
            reads++;
            return WindowEnvironment(
              width: 1200,
              height: 800,
              posture: posture,
              postureProvided: true,
              windowId: 'stage-7',
            );
          },
          child: Builder(
            builder: (context) {
              observed = context.windowEnvironment;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(observed?.posture, WindowPosture.normal);
    expect(reads, 1);

    posture = WindowPosture.tabletop;
    tester.binding.handleMetricsChanged();
    await tester.pump();
    await tester.pump();

    expect(reads, 2);
    expect(observed?.posture, WindowPosture.tabletop);
  });

  testWidgets(
    'keeps a live fold posture when the host only identifies a window',
    (tester) async {
      WindowEnvironment? observed;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: const Size(700, 500),
            displayFeatures: const [
              DisplayFeature(
                bounds: Rect.fromLTWH(349, 0, 2, 500),
                type: DisplayFeatureType.fold,
                state: DisplayFeatureState.postureHalfOpened,
              ),
            ],
          ),
          child: WindowEnvironmentScope(
            readHostEnvironment: () async => const WindowEnvironment(
              width: 700,
              height: 500,
              windowId: 'stage-7',
            ),
            child: Builder(
              builder: (context) {
                expect(
                  MediaQuery.of(context).displayFeatures.single.state,
                  DisplayFeatureState.postureHalfOpened,
                );
                observed = context.windowEnvironment;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.pump();

      expect(observed?.posture, WindowPosture.book);
      expect(observed?.displayFeatures, hasLength(1));
    },
  );

  testWidgets('clears a live fold when the host explicitly closes it', (
    tester,
  ) async {
    WindowEnvironment? observed;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: const Size(700, 500),
          displayFeatures: const [
            DisplayFeature(
              bounds: Rect.fromLTWH(349, 0, 2, 500),
              type: DisplayFeatureType.fold,
              state: DisplayFeatureState.postureHalfOpened,
            ),
          ],
        ),
        child: WindowEnvironmentScope(
          readHostEnvironment: () async => const WindowEnvironment(
            width: 700,
            height: 500,
            windowId: 'stage-7',
            postureProvided: true,
            displayFeaturesProvided: true,
          ),
          child: Builder(
            builder: (context) {
              observed = context.windowEnvironment;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(observed?.posture, WindowPosture.normal);
    expect(observed?.displayFeatures, isEmpty);
  });
}
