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
        mode: WindowMode.fullScreen,
        windowId: 'macos:42',
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

  test('only separating folds and hinges split panes', () {
    WindowDisplayFeature feature(
      WindowDisplayFeatureType type, {
      bool separating = false,
      bool horizontal = false,
    }) => WindowDisplayFeature(
      left: horizontal ? 0 : 420,
      top: horizontal ? 599 : 0,
      width: horizontal ? 840 : (type == .cutout ? 40 : 2),
      height: horizontal ? 2 : (type == .cutout ? 24 : 1200),
      type: type,
      separating: separating,
    );
    final cases = [
      (
        feature(.hinge, separating: true),
        reserved: true,
        vertical: true,
        horizontal: false,
      ),
      (
        feature(.fold, separating: true),
        reserved: true,
        vertical: true,
        horizontal: false,
      ),
      (feature(.fold), reserved: true, vertical: false, horizontal: false),
      (
        feature(.hinge, separating: true, horizontal: true),
        reserved: true,
        vertical: false,
        horizontal: true,
      ),
      (feature(.cutout), reserved: true, vertical: false, horizontal: false),
    ];
    for (final c in cases) {
      final environment = WindowEnvironment(
        width: 840,
        height: 1200,
        displayFeatures: [c.$1],
      );
      final label = '${c.$1.type} separating=${c.$1.separating}';
      expect(environment.hasReservedDisplayFeature, c.reserved, reason: label);
      expect(
        environment.verticalPaneDivider != null,
        c.vertical,
        reason: label,
      );
      expect(
        environment.horizontalPaneDivider != null,
        c.horizontal,
        reason: label,
      );
    }
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
          'separating': true,
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

  test('a host feature splits panes only when it says separating', () {
    for (final separating in [false, null]) {
      final environment = WindowEnvironmentCodec.decode({
        'width': 840,
        'height': 700,
        'displayFeatures': [
          {
            'left': 420,
            'top': 0,
            'width': 2,
            'height': 700,
            'type': 'fold',
            'separating': ?separating,
          },
        ],
      });

      expect(environment!.displayFeatures.single.separating, isFalse);
      expect(environment.verticalPaneDivider, isNull);
    }
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
            separating: false,
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

  testWidgets(
    'an optional host event channel never escapes as a plugin error',
    (tester) async {
      await tester.pumpWidget(
        const WindowEnvironmentScope(child: SizedBox.shrink()),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );

  test('accepts HarmonyOS WindowStatusType names and enum values', () {
    final cases = <Object, WindowMode>{
      'SPLIT_SCREEN': .split,
      4: .floating,
      // 最大化窗口仍按工作区窗口处理。
      'MAXIMIZE': .freeform,
      2: .freeform,
    };
    for (final MapEntry(key: status, value: mode) in cases.entries) {
      final environment = WindowEnvironmentCodec.decode({
        'width': 1200,
        'height': 800,
        'windowStatusType': status,
      });
      expect(environment?.mode, mode, reason: '$status');
    }
    expect(
      WindowEnvironmentCodec.decode({
        'width': 1200,
        'height': 800,
        'windowStatusType': 'MAXIMIZE',
      })?.usesWorkspaceToolbar,
      isTrue,
    );
  });

  test('normalizes ArkTS enum casing at the host boundary', () {
    final environment = WindowEnvironmentCodec.decode({
      'width': 1200,
      'height': 800,
      'windowStatusType': 'WINDOWED',
      'posture': 'EXPANDED',
      'displayFeatures': [
        {
          'left': 598,
          'top': 0,
          'width': 4,
          'height': 800,
          'type': 'HINGE',
          'state': 'BOOK',
          'separating': true,
        },
        {'left': 0, 'top': 0, 'width': 24, 'height': 42, 'type': 'OCCLUSION'},
      ],
    });

    expect(environment?.mode, WindowMode.freeform);
    expect(environment?.posture, WindowPosture.flat);
    expect(environment?.displayFeatures, hasLength(2));
    expect(
      environment?.displayFeatures.first.type,
      WindowDisplayFeatureType.hinge,
    );
    expect(
      environment?.displayFeatures.last.type,
      WindowDisplayFeatureType.cutout,
    );
    expect(environment?.verticalPaneDivider, isNotNull);
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
