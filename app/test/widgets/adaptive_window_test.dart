import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/platform/window_environment.dart';
import 'package:scrcpy_connect/widgets/adaptive_window.dart';

void main() {
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
}
