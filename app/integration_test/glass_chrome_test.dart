import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
// Public diagnostics only: the rendered controls all come from design_system.
// ignore: depend_on_referenced_packages
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:scrcpy_connect/services/app_state.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart' show glassSnackBar;
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';

import '../test/support/test_controller.dart';

const _photoPath = String.fromEnvironment(
  'CONNECT_GLASS_CHROME_PHOTO',
  defaultValue:
      '/data/user/0/dev.scrcpyconnect.scrcpy_connect/cache/glass-lake.jpg',
);
const _press = ValueKey('chrome-press');
const _glyph = ValueKey('chrome-press-glyph');
const _photo = ValueKey('chrome-photo');
const _stamp = ValueKey('chrome-stamp');
const _dialog = ValueKey('chrome-dialog');
const _sheet = ValueKey('chrome-sheet');
const _menu = ValueKey('chrome-menu');

/// Finite functional/optical capture, deliberately without a performance loop.
void main() {
  final binding = _ChromeBinding()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('production chrome scrolls over real content and opens glass', (
    tester,
  ) async {
    final report = <String, dynamic>{
      'schemaVersion': 1,
      'scope': 'production-glass-chrome',
      'platform': Platform.operatingSystem,
      'backend': GlassMaterial.backend,
      'backendVersion': GlassMaterial.backendVersion,
      'buildMode': kProfileMode
          ? 'profile'
          : kReleaseMode
          ? 'release'
          : 'debug',
      'shaderSupported': ui.ImageFilter.isShaderFilterSupported,
      'visualReviewRequired': true,
      'visualAcceptanceComplete': false,
      'performanceMeasured': false,
      'captureSurface': 'android-image-reader-after-native-warmup',
      'scenes': <Map<String, dynamic>>[],
      'motionSamples': <Map<String, dynamic>>[],
      'overlaySamples': <Map<String, dynamic>>[],
    };
    binding.reportData = report;
    final controller = createTestController(
      (command, [params = const {}]) async => <String, dynamic>{},
      initialState: AppState(loading: false),
    );
    final previousFatal = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    try {
      expect(Platform.isAndroid, isTrue);
      expect(ui.ImageFilter.isShaderFilterSupported, isTrue);
      await tester.runAsync(GlassMaterial.initialize);
      report['shaderLoaded'] = GlassMaterial.isInitialized;
      expect(GlassMaterial.isInitialized, isTrue);
      final photo = await tester.runAsync(() async {
        final bytes = await File(_photoPath).readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final receipt = <String, dynamic>{
          'path': _photoPath,
          'sha256': sha256.convert(bytes).toString(),
          'bytes': bytes.length,
          'width': frame.image.width,
          'height': frame.image.height,
        };
        frame.image.dispose();
        codec.dispose();
        return receipt;
      });
      report['photo'] = photo;
      final harnessKey = GlobalKey<_ChromeHarnessState>();
      await tester.pumpWidget(
        TestProviderScope(
          controller: controller,
          child: _ChromeHarness(key: harnessKey),
        ),
      );
      await _settle(tester);
      final harness = harnessKey.currentState!;
      await tester.runAsync(
        () => precacheImage(
          FileImage(File(_photoPath)),
          harness.navigator.currentContext!,
        ),
      );
      await _settle(tester);
      // Require a real production shader before Android screenshot conversion.
      report['nativeWarmup'] = _rendererReceipt();
      expect(find.byType(liquid.AdaptiveGlass), findsWidgets);
      expect(find.byType(liquid.LightweightLiquidGlass), findsNothing);
      await binding.convertFlutterSurfaceToImage();
      await _settle(tester);
      final scenes = report['scenes'] as List<Map<String, dynamic>>;
      final samples = report['motionSamples'] as List<Map<String, dynamic>>;

      Map<String, dynamic> presentation(String phase) {
        final box = tester.renderObject<RenderBox>(find.byKey(_glyph));
        final matrix = box.getTransformTo(null);
        final rect = MatrixUtils.transformRect(matrix, Offset.zero & box.size);
        return {
          'phase': phase,
          'wallUs': DateTime.now().microsecondsSinceEpoch,
          'matrix': matrix.storage.toList(),
          'bounds': _rect(rect),
          'scrollOffset': harness.scroll.offset,
          'activationCount': harness.activations,
        };
      }

      Future<void> sample(String phase) async {
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          samples.add(presentation(phase));
        }
      }

      Future<void> capture(String name) async {
        final code = 0xc300 | (scenes.length + 1);
        harness.mark(code);
        await _raster(tester);
        // Drain ImageReader's previous image before publishing this identity.
        await binding.callbackManager.takeScreenshot('$name-drain');
        await _raster(tester);
        final renderer = _rendererReceipt();
        expect(renderer['liteCount'], 0);
        expect(renderer['blurCount'], 0);
        if (harness.opaque) {
          expect(renderer['lensCount'], 0);
          expect(renderer['layerCount'], 0);
        } else {
          expect(renderer['lensCount'], greaterThan(0));
          expect(renderer['layerCount'], greaterThan(0));
        }
        expect(tester.takeException(), isNull);
        final bytes = await binding.takeScreenshot(name);
        scenes.add({
          'name': name,
          'markerCode': code,
          'markerBounds': _rect(tester.getRect(find.byKey(_stamp))),
          'sha256': sha256.convert(bytes).toString(),
          'bytes': bytes.length,
          'physicalWidth': tester.view.physicalSize.width,
          'physicalHeight': tester.view.physicalSize.height,
          'dpr': tester.view.devicePixelRatio,
          'brightness': harness.brightness.name,
          'reduceTransparency': harness.opaque,
          'reduceMotion': harness.reducedMotion,
          'scrollOffset': harness.scroll.offset,
          'headerBounds': _rect(tester.getRect(find.byType(AppBar))),
          'photoBounds': _rect(tester.getRect(find.byKey(_photo))),
          'presentation': presentation(name),
          'renderer': renderer,
        });
      }

      Future<void> overlays(String suffix) async {
        Future<void> sampleOverlay(Finder target, String kind) async {
          await tester.pump();
          // A native menu first morphs its source; its item subtree mounts
          // after that phase. Sample content once it actually exists.
          var appearanceFrames = 0;
          while (target.evaluate().isEmpty && appearanceFrames < 75) {
            await tester.pump(const Duration(milliseconds: 16));
            appearanceFrames++;
          }
          expect(target, findsOneWidget);
          final frames = <List<double>>[];
          for (var i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 16));
            final box = tester.renderObject<RenderBox>(target);
            final matrix = box.getTransformTo(null).storage.toList();
            frames.add(matrix);
            (report['overlaySamples'] as List<Map<String, dynamic>>).add({
              'phase': '$kind-$suffix',
              'appearanceFrames': appearanceFrames,
              'wallUs': DateTime.now().microsecondsSinceEpoch,
              'matrix': matrix,
            });
          }
          if (harness.reducedMotion) {
            for (final frame in frames) {
              expect(
                _distance(frames.first, frame),
                lessThan(.001),
                reason: 'Reduced motion must suppress $kind displacement.',
              );
            }
          }
        }

        await tester.tap(find.byKey(_dialog));
        await sampleOverlay(find.text('修改设备名称'), 'dialog');
        await _settle(tester);
        expect(find.byType(GlassAlertDialog), findsOneWidget);
        await capture('dialog-$suffix');
        await tester.tap(find.text('关闭对话框'));
        await _settle(tester);
        expect(find.byType(GlassAlertDialog), findsNothing);
        await tester.tap(find.byKey(_sheet));
        await sampleOverlay(find.text('截图与操作面板'), 'sheet');
        await _settle(tester);
        expect(find.text('截图与操作面板'), findsOneWidget);
        if (!harness.opaque) {
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is liquid.AdaptiveGlass &&
                  widget.shape is liquid.LiquidVerticalRoundedSuperellipse,
            ),
            findsOneWidget,
            reason: 'The modal sheet must mount its native vertical lens.',
          );
        }
        await capture('sheet-$suffix');
        await tester.tap(find.text('关闭面板'));
        await _settle(tester);
        expect(find.text('截图与操作面板'), findsNothing);
        await tester.tap(
          find.descendant(
            of: find.byKey(_menu),
            matching: find.byType(IconButton),
          ),
        );
        await sampleOverlay(find.text('查看原文件'), 'menu');
        await _settle(tester);
        expect(find.text('查看原文件'), findsOneWidget);
        await capture('menu-$suffix');
        // Cancel the real route/anchor, then reopen and activate an action.
        await tester.tapAt(
          Offset(
            4,
            tester.view.physicalSize.height / tester.view.devicePixelRatio - 4,
          ),
        );
        await _settle(tester);
        expect(find.text('查看原文件'), findsNothing);
        await tester.tap(
          find.descendant(
            of: find.byKey(_menu),
            matching: find.byType(IconButton),
          ),
        );
        await _settle(tester);
        await tester.tap(find.text('查看原文件'));
        await _settle(tester);
        expect(find.text('查看原文件'), findsNothing);

        harness.showTooltips(true);
        await tester.pump();
        final tooltip = tester.state<TooltipState>(
          find.descendant(
            of: find.byKey(_press),
            matching: find.byType(Tooltip),
          ),
        );
        expect(tooltip.ensureTooltipVisible(), isTrue);
        await _settle(tester);
        expect(find.text('按压测试', findRichText: true), findsWidgets);
        await capture('tooltip-$suffix');
        Tooltip.dismissAllToolTips();
        await _settle(tester);
        harness.showTooltips(false);
        await tester.pump();

        final messenger = ScaffoldMessenger.of(
          harness.navigator.currentContext!,
        );
        messenger.showSnackBar(glassSnackBar('操作已完成'));
        await _settle(tester);
        expect(find.text('操作已完成'), findsOneWidget);
        await capture('feedback-$suffix');
        messenger.clearSnackBars();
        await _settle(tester);
        expect(find.text('操作已完成'), findsNothing);
      }

      await capture('light-rest');
      final header = tester.getRect(find.byType(AppBar));
      final initialPhoto = tester.getRect(find.byKey(_photo));
      final drag = initialPhoto.top - header.top + 24;
      await tester.timedDragFrom(
        Offset(
          8,
          tester.view.physicalSize.height / tester.view.devicePixelRatio * .7,
        ),
        Offset(0, -drag),
        const Duration(milliseconds: 400),
      );
      await _settle(tester);
      final movedPhoto = tester.getRect(find.byKey(_photo));
      expect(harness.scroll.offset, greaterThan(40));
      expect(
        movedPhoto.overlaps(header),
        isTrue,
        reason: 'A real decoded photograph must cross behind the toolbar.',
      );
      expect(movedPhoto.top, lessThan(header.bottom));
      report['scrollGeometry'] = {
        'header': _rect(header),
        'before': _rect(initialPhoto),
        'after': _rect(movedPhoto),
        'offset': harness.scroll.offset,
      };
      await capture('light-scroll');
      final rest = presentation('rest');
      samples.add(rest);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_press)),
      );
      await sample('press');
      await capture('motion-held');
      await gesture.moveBy(const Offset(8, -5));
      await sample('drag');
      await capture('motion-drag');
      await gesture.cancel();
      await sample('cancel');
      await capture('motion-cancel');
      expect(harness.activations, 0);
      final repress = await tester.startGesture(
        tester.getCenter(find.byKey(_press)),
      );
      await sample('repress');
      await capture('motion-repress');
      await repress.cancel();
      await sample('recovery');
      await _settle(tester);
      await capture('motion-recovered');
      expect(harness.activations, 0);
      expect(
        _distance(
          rest['bounds'] as List<double>,
          presentation('recovered')['bounds'] as List<double>,
        ),
        lessThan(.5),
      );
      expect(
        samples
            .where((s) => s['phase'] == 'press')
            .any(
              (s) =>
                  _distance(
                    rest['matrix'] as List<double>,
                    s['matrix'] as List<double>,
                  ) >
                  .001,
            ),
        isTrue,
      );
      await tester.tap(find.byKey(_press));
      await _settle(tester);
      expect(harness.activations, 1);
      await overlays('light');
      harness.configure(brightness: Brightness.dark);
      await _settle(tester);
      await capture('dark-scroll');
      await overlays('dark');
      harness.configure(brightness: Brightness.light, opaque: true);
      await _settle(tester);
      await capture('opaque-light');
      await overlays('opaque');
      harness.configure(brightness: Brightness.dark, opaque: true);
      await _settle(tester);
      await capture('opaque-dark');
      harness.configure(brightness: Brightness.light, reducedMotion: true);
      await _settle(tester);
      final reducedRest = presentation('reduced-rest');
      samples.add(reducedRest);
      await capture('reduced-motion-rest');
      final reducedPress = await tester.startGesture(
        tester.getCenter(find.byKey(_press)),
      );
      await sample('reduced-press');
      await capture('reduced-motion-held');
      await reducedPress.cancel();
      await sample('reduced-cancel');
      for (final item in samples.where(
        (s) => (s['phase'] as String).startsWith('reduced-'),
      )) {
        expect(
          _distance(
            reducedRest['matrix'] as List<double>,
            item['matrix'] as List<double>,
          ),
          lessThan(.001),
        );
      }
      await overlays('reduced-motion');
      report['activationCount'] = harness.activations;
      report['menuActivationCount'] = harness.menuActivations;
      expect(harness.menuActivations, 4);
      report['harnessComplete'] = true;
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      WidgetController.hitTestWarningShouldBeFatal = previousFatal;
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

Map<String, int> _rendererReceipt() => {
  'lensCount': find.byType(liquid.AdaptiveGlass).evaluate().length,
  'layerCount': find.byType(liquid.LiquidGlassLayer).evaluate().length,
  'liteCount': find.byType(liquid.LightweightLiquidGlass).evaluate().length,
  'blurCount': find.byType(BackdropFilter).evaluate().length,
};

List<double> _rect(Rect rect) => [rect.left, rect.top, rect.width, rect.height];
double _distance(List<double> a, List<double> b) => List.generate(
  a.length,
  (i) => (a[i] - b[i]).abs(),
).reduce((a, b) => a > b ? a : b);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

Future<void> _raster(WidgetTester tester) async {
  final completed = Completer<void>();
  final start = DateTime.now().microsecondsSinceEpoch;
  void timing(List<ui.FrameTiming> frames) {
    if (!completed.isCompleted &&
        frames.any(
          (f) =>
              f.timestampInMicroseconds(ui.FramePhase.rasterFinishWallTime) >=
              start,
        )) {
      completed.complete();
    }
  }

  tester.binding.addTimingsCallback(timing);
  try {
    tester.binding.scheduleFrame();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    await tester.runAsync(() async {
      await completed.future.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
  } finally {
    tester.binding.removeTimingsCallback(timing);
  }
}

class _ChromeBinding extends IntegrationTestWidgetsFlutterBinding {
  @override
  void handlePointerEvent(PointerEvent event) {
    final previous = shouldPropagateDevicePointerEvents;
    shouldPropagateDevicePointerEvents = true;
    try {
      withPointerEventSource(
        TestBindingEventSource.device,
        () => super.handlePointerEvent(event),
      );
    } finally {
      shouldPropagateDevicePointerEvents = previous;
    }
  }
}

class _ChromeHarness extends StatefulWidget {
  const _ChromeHarness({super.key});
  @override
  State<_ChromeHarness> createState() => _ChromeHarnessState();
}

class _ChromeHarnessState extends State<_ChromeHarness> {
  final navigator = GlobalKey<NavigatorState>();
  final scroll = ScrollController();
  Brightness brightness = Brightness.light;
  bool opaque = false;
  bool reducedMotion = false;
  bool tooltipsVisible = false;
  int marker = 0;
  int activations = 0;
  int menuActivations = 0;
  void mark(int code) => setState(() => marker = code);
  void showTooltips(bool visible) => setState(() => tooltipsVisible = visible);
  void configure({
    required Brightness brightness,
    bool opaque = false,
    bool reducedMotion = false,
  }) => setState(() {
    this.brightness = brightness;
    this.opaque = opaque;
    this.reducedMotion = reducedMotion;
  });
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GlassMaterial.wrap(
    child: TooltipVisibility(
      visible: tooltipsVisible,
      child: MaterialApp(
        navigatorKey: navigator,
        debugShowCheckedModeBanner: false,
        themeAnimationDuration: Duration.zero,
        theme: ConnectTokens.theme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reducedMotion),
          child: GlassPreferences(
            reduceTransparency: opaque,
            child: Stack(
              children: [
                child!,
                Positioned(
                  left: 8,
                  bottom: MediaQuery.viewPaddingOf(context).bottom + 4,
                  child: IgnorePointer(
                    child: SizedBox(
                      key: _stamp,
                      width: 128,
                      height: 8,
                      child: CustomPaint(painter: _StampPainter(marker)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        home: Builder(
          builder: (context) => PageFrame(
            title: '玻璃验收',
            root: true,
            actions: [
              GlassActionIcon(
                key: _dialog,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => unawaited(
                  showGlassDialog<void>(
                    context: context,
                    builder: (context) => GlassAlertDialog(
                      title: const Text('修改设备名称'),
                      content: const Text('真实内容仍在面板后方。取消后保留原状态。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('关闭对话框'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              GlassActionIcon(
                key: _sheet,
                icon: const Icon(Icons.tune),
                onPressed: () => unawaited(
                  showGlassModalSheet<void>(
                    context: context,
                    builder: (context) => Padding(
                      padding: const EdgeInsets.all(DesignTokens.spacingLg),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('截图与操作面板'),
                          const SizedBox(height: 16),
                          const Text('普通文字内容与当前照片共同验证大面板的可读性。'),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('关闭面板'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              GlassMenuButton(
                key: _menu,
                icon: const Icon(Icons.more_horiz),
                tooltip: '更多操作',
                actions: [
                  GlassMenuAction(
                    label: '查看原文件',
                    icon: const Icon(Icons.description_outlined),
                    onPressed: () => menuActivations++,
                  ),
                ],
              ),
            ],
            trailingAction: GlassIconButton(
              key: _press,
              icon: const Icon(Icons.add, key: _glyph),
              tooltip: '按压测试',
              onPressed: () => setState(() => activations++),
            ),
            child: GroupedListView(
              controller: scroll,
              children: [
                SizedBox(
                  key: _photo,
                  height: 280,
                  child: Image.file(
                    File(_photoPath),
                    fit: BoxFit.cover,
                    width: double.infinity,
                  ),
                ),
                for (var i = 0; i < 22; i++)
                  ListTile(
                    leading: Icon(
                      [
                        Icons.folder,
                        Icons.photo,
                        Icons.phone,
                        Icons.article,
                      ][i % 4],
                      color: [
                        Colors.orange,
                        Colors.blue,
                        Colors.green,
                        Colors.red,
                      ][i % 4],
                    ),
                    title: Text('真实滚动内容 $i · 文件与设备'),
                    subtitle: Text('Aa 0123456789 · 第 $i 行状态正文'),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _StampPainter extends CustomPainter {
  const _StampPainter(this.code);
  final int code;
  @override
  void paint(Canvas canvas, Size size) {
    for (var bit = 0; bit < 16; bit++) {
      canvas.drawRect(
        Rect.fromLTWH(bit * size.width / 16, 0, size.width / 16, size.height),
        Paint()
          ..color = code & (1 << (15 - bit)) != 0 ? Colors.white : Colors.black,
      );
    }
  }

  @override
  bool shouldRepaint(_StampPainter oldDelegate) => oldDelegate.code != code;
}
