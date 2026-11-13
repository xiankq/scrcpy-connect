import 'dart:ui';
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/platform/window_environment.dart';
import 'package:scrcpy_connect/widgets/adaptive_window.dart';

void main() {
  testWidgets('applies a host posture event without a metrics change', (
    tester,
  ) async {
    final events = StreamController<WindowEnvironment?>();
    addTearDown(events.close);
    WindowEnvironment? observed;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(700, 500)),
        child: WindowEnvironmentScope(
          readHostEnvironment: () async => const WindowEnvironment(
            width: 700,
            height: 500,
            windowId: 'stage-7',
          ),
          watchHostEnvironment: () => events.stream,
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
    await tester.pump();
    expect(observed?.posture, WindowPosture.normal);

    events.add(
      const WindowEnvironment(
        width: 700,
        height: 500,
        windowId: 'stage-7',
        posture: WindowPosture.book,
        postureProvided: true,
        displayFeaturesProvided: true,
        displayFeatures: [
          WindowDisplayFeature(
            left: 349,
            top: 0,
            width: 2,
            height: 500,
            type: WindowDisplayFeatureType.fold,
            state: WindowPosture.book,
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(observed?.posture, WindowPosture.book);
    expect(observed?.verticalPaneDivider, isNotNull);
  });

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

  testWidgets('keeps tabletop content inside the top pane', (tester) async {
    Size? size;
    List<DisplayFeature>? features;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: const Size(840, 1200),
          displayFeatures: const [
            DisplayFeature(
              bounds: Rect.fromLTWH(0, 599, 840, 2),
              type: DisplayFeatureType.hinge,
              state: DisplayFeatureState.postureHalfOpened,
            ),
          ],
        ),
        child: WindowEnvironmentScope(
          readHostEnvironment: () async => const WindowEnvironment(
            width: 840,
            height: 1200,
            posture: WindowPosture.tabletop,
            postureProvided: true,
            displayFeaturesProvided: true,
            displayFeatures: [
              WindowDisplayFeature(
                left: 0,
                top: 599,
                width: 840,
                height: 2,
                type: WindowDisplayFeatureType.hinge,
                state: WindowPosture.tabletop,
              ),
            ],
          ),
          child: WindowPaneHost(
            child: Builder(
              builder: (context) {
                size = MediaQuery.sizeOf(context);
                features = MediaQuery.of(context).displayFeatures;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(size, const Size(840, 599));
    expect(features, isEmpty);
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

  testWidgets(
    'uses desktop engine identity when the host projection is absent',
    (tester) async {
      WindowEnvironment? observed;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1200, 800)),
          child: WindowEnvironmentScope(
            readHostEnvironment: () async => null,
            readDesktopWindowIdentity: () async => const WindowEnvironment(
              width: 1,
              height: 1,
              windowId: 'desktop:window-7',
              mode: WindowMode.freeform,
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

      expect(observed?.windowId, 'desktop:window-7');
      expect(observed?.mode, WindowMode.freeform);
      expect(observed?.width, 1200);
      expect(observed?.height, 800);
    },
  );

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
