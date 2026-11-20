import 'dart:async';

import 'package:foldable/foldable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:scrcpy_connect/widgets/adaptive_window.dart';

void main() {
  testWidgets('foldable snapshots drive the shared Duo window contract', (
    tester,
  ) async {
    final events = StreamController<FoldableData>.broadcast();
    addTearDown(events.close);
    WindowEnvironment? observed;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(951, 669)),
        child: FoldableProvider(
          debugData: events.stream,
          child: WindowEnvironmentScope(
            child: Builder(
              builder: (context) {
                observed = context.windowEnvironment;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );

    events.add(_snapshot(HingeStatus.partiallyOpen));
    await tester.pump();
    await tester.pump();

    expect(observed?.posture, WindowPosture.book);
    expect(observed?.verticalPaneDivider, isNotNull);
    expect(observed?.verticalPaneDivider?.separating, isTrue);

    events.add(_snapshot(HingeStatus.fullyOpen));
    await tester.pump();
    await tester.pump();

    expect(observed?.posture, WindowPosture.flat);
    expect(observed?.displayFeatures, isEmpty);
    expect(observed?.verticalPaneDivider, isNull);

    events.add(
      _snapshot(
        HingeStatus.partiallyOpen,
        bounds: const Rect.fromLTWH(0, 314, 951, 40),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(observed?.posture, WindowPosture.tabletop);
    expect(observed?.horizontalPaneDivider, isNotNull);
  });
}

FoldableData _snapshot(
  HingeStatus status, {
  Rect bounds = const Rect.fromLTWH(455, 0, 40, 669),
}) => FoldableData(
  capabilities: const FoldableCapabilities(
    supportLevel: FoldableSupportLevel.available,
    isFoldable: true,
    hingeApiPresent: true,
    regionApiPresent: true,
    angleUnitVerified: true,
    strategy: 'test',
  ),
  status: status,
  angleDegrees: switch (status) {
    HingeStatus.partiallyOpen => 90,
    HingeStatus.fullyOpen => 180,
    HingeStatus.closed => 0,
    HingeStatus.unknown => null,
  },
  regions: [
    ReservedRegion(
      kind: ReservedRegionKind.division,
      bounds: bounds,
      isActive: true,
    ),
  ],
  displayFeatures: const [],
  horizontalSizeClass: SizeClass.regular,
  verticalSizeClass: SizeClass.regular,
);
