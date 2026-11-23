import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart';
import 'package:scrcpy_connect/core/gallery/gallery_scanner.dart';
import 'package:scrcpy_connect/core/gallery/models/gallery_scan_state.dart';
import 'package:scrcpy_connect/core/gallery/gallery_scanner_provider.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_state.dart';
import 'package:scrcpy_connect/core/recovery/recovery_state_notifier.dart';
import 'package:scrcpy_connect/pages/gallery/gallery_page.dart';
import 'package:scrcpy_connect/pages/gallery/widgets/gallery_media_tile.dart';
import 'package:scrcpy_connect/pages/gallery/widgets/gallery_scan_summary.dart';
import 'package:scrcpy_connect/styles/theme.dart';

const _device = DeviceSnapshot(id: 'phone', guid: 'guid');

void main() {
  testWidgets('继续浏览已找到的照片时显示本轮检查的终态', (tester) async {
    const previous = GalleryScanSnapshot(
      deviceId: 'phone',
      scanId: 'scan',
      status: .scanning,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GalleryScanSummary(
            scan: GalleryScanState(
              result: previous,
              pendingResult: previous.copyWith(status: .partial, limited: true),
              showingPrevious: true,
            ),
            reading: false,
            onRestart: () {},
            onCancel: () {},
            onRefresh: () {},
            onUpdate: () {},
          ),
        ),
      ),
    );
    expect(find.text('只检查了部分文件夹'), findsOneWidget);
    expect(find.text('更新照片'), findsOneWidget);
    expect(find.text('暂时无法读取相册'), findsNothing);
  });

  for (final initialStatus in [
    GalleryScanStatus.completed,
    GalleryScanStatus.scanning,
  ]) {
    testWidgets('重进相册复用 ${initialStatus.name} 结果，主动刷新才检查', (tester) async {
      final scanner = _Scanner(initialStatus);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            galleryScannerProvider.overrideWithValue(scanner),
            recoveryStateProvider.overrideWith(_Recovery.new),
          ],
          child: MaterialApp(
            theme: ConnectTokens.theme(Brightness.light),
            navigatorKey: navigator,
            home: const Scaffold(),
          ),
        ),
      );
      Future<void> openGallery() async {
        navigator.currentState!.push<void>(
          MaterialPageRoute(builder: (_) => const GalleryPage(device: _device)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump();
      }

      await openGallery();
      expect(scanner.starts, 1);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();

      await openGallery();
      expect(scanner.starts, 1);
      expect(find.textContaining('上次检查结果'), findsOneWidget);
      final discoveredPhoto = find.byWidgetPredicate(
        (widget) =>
            widget is GalleryMediaTile && widget.file.name == 'discovered.jpg',
      );
      final expectedPhoto = initialStatus == .scanning
          ? findsOneWidget
          : findsNothing;
      expect(discoveredPhoto, expectedPhoto);
      expect(find.textContaining('11 月 19 日'), expectedPhoto);
      expect(find.text('检查范围'), findsOneWidget);
      final statusText = initialStatus == .completed
          ? '已检查共享存储中的照片与视频'
          : '已停止检查';
      expect(find.text(statusText), findsOneWidget);

      await tester.tap(find.text('刷新'));
      await tester.pumpAndSettle();
      expect(scanner.starts, 2);
      expect(find.text('更新照片'), findsOneWidget);
      expect(find.text(statusText), findsOneWidget);
      expect(discoveredPhoto, expectedPhoto);

      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await openGallery();
      expect(scanner.starts, 2);
      expect(discoveredPhoto, expectedPhoto);
      expect(find.text('更新照片'), findsOneWidget);

      await tester.tap(find.text('更新照片'));
      await tester.pumpAndSettle();
      expect(find.textContaining('上次检查结果'), findsNothing);
      expect(discoveredPhoto, findsNothing);
    });
  }
}

class _Scanner implements GalleryScanner {
  _Scanner(this.initialStatus);

  final GalleryScanStatus initialStatus;
  int starts = 0;
  late GalleryScanSnapshot _latest;

  @override
  Future<GalleryScanSnapshot> startScan(
    String deviceId, {
    int limit = 100,
  }) async {
    starts++;
    final status = starts == 1 ? initialStatus : GalleryScanStatus.completed;
    final items = [
      if (status == .scanning)
        FileCatalogEntry(
          name: 'discovered.jpg',
          path: '/sdcard/Pictures/discovered.jpg',
          canOpen: false,
          mime: 'image/jpeg',
          modified: DateTime(2026, 11, 19, 12).millisecondsSinceEpoch ~/ 1000,
        ),
    ];
    return _latest = GalleryScanSnapshot(
      deviceId: deviceId,
      scanId: 'scan-$starts',
      status: status,
      items: items,
      total: items.length,
      visitedDirectories: 3,
    );
  }

  @override
  Future<GalleryScanSnapshot> readScan(
    GalleryScanTarget target, {
    int offset = 0,
    int limit = 100,
  }) async => _latest;

  @override
  Future<GalleryScanSnapshot> cancelScan(GalleryScanTarget target) async =>
      GalleryScanSnapshot(
        deviceId: target.deviceId,
        scanId: target.scanId,
        status: .cancelled,
      );
}

class _Recovery extends RecoveryStateNotifier {
  @override
  RecoveryState build() => RecoveryState();
}
