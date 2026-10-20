import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/widgets/media_controls_protection.dart';

void main() {
  testWidgets(
    'media protection passes gestures through its fade and keeps controls usable',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 54, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 54, bottom: 34);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
        tester.view.resetViewPadding();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      for (final edge in MediaControlsEdge.values) {
        for (final layout in [
          (const Size(402, 874), 1.0),
          (const Size(280, 620), 2.0),
        ]) {
          tester.view.physicalSize = layout.$1;
          tester.platformDispatcher.textScaleFactorTestValue = layout.$2;
          var mediaTaps = 0;
          var controlTaps = 0;
          const bandKey = ValueKey('actual-control-band');
          await tester.pumpWidget(
            MaterialApp(
              theme: ConnectTokens.theme(Brightness.dark),
              home: Scaffold(
                body: Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => mediaTaps++,
                        child: const ColoredBox(color: Colors.white),
                      ),
                    ),
                    Align(
                      alignment: edge == MediaControlsEdge.top
                          ? Alignment.topCenter
                          : Alignment.bottomCenter,
                      child: MediaControlsProtection(
                        edge: edge,
                        child: SafeArea(
                          key: bandKey,
                          top: edge == MediaControlsEdge.top,
                          bottom: edge == MediaControlsEdge.bottom,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                const Expanded(child: Text('媒体控制与保留名称')),
                                IconButton(
                                  onPressed: () => controlTaps++,
                                  tooltip: '播放',
                                  icon: const Icon(Icons.play_arrow),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final band = tester.getRect(find.byKey(bandKey));
          final top = edge == MediaControlsEdge.top;
          expect(top ? band.top : band.bottom, top ? 0 : layout.$1.height);
          final fadeCenter = Offset(1, top ? band.bottom + 32 : band.top - 32);
          await tester.tapAt(fadeCenter);
          expect(
            mediaTaps,
            1,
            reason: 'The decorative fade must not consume media gestures',
          );
          await tester.tap(find.byTooltip('播放'));
          expect(controlTaps, 1);
          expect(mediaTaps, 1);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
      }
    },
  );
}
