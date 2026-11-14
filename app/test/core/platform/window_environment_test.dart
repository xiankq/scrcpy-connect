import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:scrcpy_connect/core/platform/window_environment.dart';
import 'package:scrcpy_connect/widgets/adaptive_window.dart';

void main() {
  test('classifies the available window, not the physical device', () {
    expect(WindowEnvironment.sizeClassFor(599), WindowSizeClass.compact);
    expect(WindowEnvironment.sizeClassFor(600), WindowSizeClass.medium);
    expect(WindowEnvironment.sizeClassFor(839), WindowSizeClass.medium);
    expect(WindowEnvironment.sizeClassFor(840), WindowSizeClass.expanded);
  });

  test(
    'window projections use value semantics for stable inherited updates',
    () {
      const first = WindowEnvironment(
        width: 840,
        height: 700,
        insets: WindowInsets(top: 24),
        displayFeatures: [
          WindowDisplayFeature(
            left: 420,
            top: 0,
            width: 2,
            height: 700,
            type: WindowDisplayFeatureType.fold,
            state: WindowPosture.book,
          ),
        ],
        input: WindowInputCapabilities(pointer: true),
      );
      const second = WindowEnvironment(
        width: 840,
        height: 700,
        insets: WindowInsets(top: 24),
        displayFeatures: [
          WindowDisplayFeature(
            left: 420,
            top: 0,
            width: 2,
            height: 700,
            type: WindowDisplayFeatureType.fold,
            state: WindowPosture.book,
          ),
        ],
        input: WindowInputCapabilities(pointer: true),
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    },
  );

  test('workspace toolbar follows the expanded width breakpoint', () {
    expect(
      const WindowEnvironment(width: 1200, height: 479).usesWorkspaceToolbar,
      isTrue,
    );
    expect(
      const WindowEnvironment(width: 839, height: 900).usesWorkspaceToolbar,
      isFalse,
    );
    expect(
      const WindowEnvironment(
        width: 720,
        height: 900,
        mode: WindowMode.freeform,
      ).usesWorkspaceToolbar,
      isTrue,
    );
    expect(
      const WindowEnvironment(
        width: 720,
        height: 900,
        mode: WindowMode.floating,
      ).usesWorkspaceToolbar,
      isTrue,
    );
    expect(
      const WindowEnvironment(
        width: 720,
        height: 900,
        mode: WindowMode.split,
      ).usesWorkspaceToolbar,
      isFalse,
    );
  });

  test('folds, hinges and cutouts are reserved regions', () {
    const hinge = WindowDisplayFeature(
      left: 500,
      top: 0,
      width: 20,
      height: 800,
      type: WindowDisplayFeatureType.hinge,
      state: WindowPosture.book,
    );
    const environment = WindowEnvironment(
      width: 1020,
      height: 800,
      displayFeatures: [hinge],
    );
    expect(environment.hasReservedDisplayFeature, isTrue);
    expect(hinge.contains(510, 400), isTrue);
    expect(hinge.contains(100, 400), isFalse);
  });

  test('a fold feature is also reserved for pane layout', () {
    const environment = WindowEnvironment(
      width: 840,
      height: 700,
      displayFeatures: [
        WindowDisplayFeature(
          left: 420,
          top: 0,
          width: 2,
          height: 700,
          type: WindowDisplayFeatureType.fold,
        ),
      ],
    );

    expect(environment.hasReservedDisplayFeature, isTrue);
    expect(environment.verticalPaneDivider, isNotNull);
  });

  test('a horizontal hinge exposes a safe tabletop pane', () {
    const environment = WindowEnvironment(
      width: 840,
      height: 1200,
      displayFeatures: [
        WindowDisplayFeature(
          left: 0,
          top: 599,
          width: 840,
          height: 2,
          type: WindowDisplayFeatureType.hinge,
        ),
      ],
    );

    expect(environment.horizontalPaneDivider, isNotNull);
    expect(environment.verticalPaneDivider, isNull);
  });

  test('a camera cutout does not split the workspace into panes', () {
    const environment = WindowEnvironment(
      width: 840,
      height: 700,
      displayFeatures: [
        WindowDisplayFeature(
          left: 400,
          top: 0,
          width: 40,
          height: 24,
          type: WindowDisplayFeatureType.cutout,
        ),
      ],
    );

    expect(environment.verticalPaneDivider, isNull);
  });

  test('decodes a HarmonyOS window projection without vendor types', () {
    final environment = WindowEnvironmentCodec.decode({
      'width': 1200,
      'height': 800,
      'mode': 'split',
      'windowId': 'stage-7',
      'insets': {'left': 12, 'top': 24, 'right': 12, 'bottom': 16},
      'input': {'touch': true, 'keyboard': true, 'pointer': true},
      'displayFeatures': [
        {
          'left': 598,
          'top': 0,
          'width': 4,
          'height': 800,
          'type': 'hinge',
          'state': 'book',
        },
      ],
    });

    expect(environment, isNotNull);
    expect(environment!.windowId, 'stage-7');
    expect(environment.insetsProvided, isTrue);
    expect(environment.mode, WindowMode.split);
    expect(environment.posture, WindowPosture.book);
    expect(environment.insets.top, 24);
    expect(environment.input.pointer, isTrue);
    expect(environment.displayFeaturesProvided, isTrue);
    expect(environment.postureProvided, isFalse);
    expect(environment.verticalPaneDivider, isNotNull);
  });

  test(
    'keeps iPhone Duo camera occlusion in the reserved feature contract',
    () {
      final environment = WindowEnvironmentCodec.decode({
        'width': 402,
        'height': 874,
        'windowId': 'ios:duo-occlusion',
        'displayFeatures': [
          {'left': 188, 'top': 0, 'width': 26, 'height': 42, 'type': 'cutout'},
          {
            'left': 199,
            'top': 0,
            'width': 4,
            'height': 874,
            'type': 'fold',
            'state': 'book',
          },
        ],
      });

      expect(environment, isNotNull);
      expect(environment!.displayFeaturesProvided, isTrue);
      expect(
        environment.displayFeatures,
        contains(
          const WindowDisplayFeature(
            left: 188,
            top: 0,
            width: 26,
            height: 42,
            type: WindowDisplayFeatureType.cutout,
          ),
        ),
      );
      expect(environment.posture, WindowPosture.book);
    },
  );

  testWidgets('an explicit zero host inset clears stale view padding', (
    tester,
  ) async {
    WindowEnvironment? observed;
    EdgeInsets? observedPadding;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(700, 500),
          padding: EdgeInsets.only(top: 24),
        ),
        child: WindowEnvironmentScope(
          readHostEnvironment: () async => const WindowEnvironment(
            width: 700,
            height: 500,
            insetsProvided: true,
            windowId: 'stage-7',
          ),
          child: Builder(
            builder: (context) {
              observed = context.windowEnvironment;
              observedPadding = MediaQuery.paddingOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(observed?.insets, const WindowInsets());
    expect(observedPadding, EdgeInsets.zero);
  });

  test('accepts HarmonyOS WindowStatusType names and enum values', () {
    final splitByName = WindowEnvironmentCodec.decode({
      'width': 700,
      'height': 500,
      'windowStatusType': 'SPLIT_SCREEN',
    });
    final floatingByValue = WindowEnvironmentCodec.decode({
      'width': 700,
      'height': 500,
      'windowStatusType': 4,
    });

    expect(splitByName?.mode, WindowMode.split);
    expect(floatingByValue?.mode, WindowMode.floating);
  });

  test('records explicit empty host projections so a closed fold clears', () {
    final environment = WindowEnvironmentCodec.decode({
      'width': 700,
      'height': 500,
      'posture': 'normal',
      'displayFeatures': const <Object?>[],
    });

    expect(environment, isNotNull);
    expect(environment!.postureProvided, isTrue);
    expect(environment.displayFeaturesProvided, isTrue);
    expect(environment.displayFeatures, isEmpty);
  });

  test('rejects an incomplete host projection', () {
    expect(WindowEnvironmentCodec.decode({'width': 1200}), isNull);
  });
}
