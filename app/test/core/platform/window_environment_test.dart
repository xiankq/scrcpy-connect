import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/platform/window_environment_codec.dart';
import 'package:scrcpy_connect/core/platform/window_environment.dart';

void main() {
  test('classifies the available window, not the physical device', () {
    expect(WindowEnvironment.sizeClassFor(599), WindowSizeClass.compact);
    expect(WindowEnvironment.sizeClassFor(600), WindowSizeClass.medium);
    expect(WindowEnvironment.sizeClassFor(839), WindowSizeClass.medium);
    expect(WindowEnvironment.sizeClassFor(840), WindowSizeClass.expanded);
  });

  test('workspace toolbar only applies to a usable expanded window', () {
    expect(
      const WindowEnvironment(width: 1200, height: 479).usesWorkspaceToolbar,
      isFalse,
    );
    expect(
      const WindowEnvironment(width: 1200, height: 480).usesWorkspaceToolbar,
      isTrue,
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
      'posture': 'book',
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
    expect(environment.mode, WindowMode.split);
    expect(environment.posture, WindowPosture.book);
    expect(environment.insets.top, 24);
    expect(environment.input.pointer, isTrue);
    expect(environment.verticalPaneDivider, isNotNull);
  });

  test('rejects an incomplete host projection', () {
    expect(WindowEnvironmentCodec.decode({'width': 1200}), isNull);
  });
}
