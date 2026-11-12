import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart';
import 'package:scrcpy_connect/core/gallery/gallery_history_notifier.dart';
import 'package:scrcpy_connect/core/gallery/gallery_scan_notifier.dart';
import 'package:scrcpy_connect/core/gallery/gallery_scanner.dart';
import 'package:scrcpy_connect/core/gallery/gallery_scanner_provider.dart';

void main() {
  const device = DeviceSnapshot(id: 'device', guid: 'guid');
  late _Scanner scanner;
  late ProviderContainer container;
  setUp(() {
    scanner = _Scanner();
    container = ProviderContainer(
      overrides: [galleryScannerProvider.overrideWithValue(scanner)],
    );
  });
  tearDown(() => container.dispose());

  test('相册独立装配，离页后的迟到创建只由原扫描能力回收', () async {
    final provider = galleryScanProvider(device, scope: Object());
    final listener = container.listen(provider, (_, _) {});
    final start = container.read(provider.notifier).start();
    listener.close();
    await container.pump();
    scanner.starts.single.complete(_snapshot('retired', ['/old']));
    await start;
    await _flush(container);
    expect(scanner.cancelled, [(deviceId: 'device', scanId: 'retired')]);
  });

  test('换源时清空旧相册历史，旧结果不写入新来源也不交给新能力取消', () async {
    final history = container.read(galleryHistoryProvider.notifier);
    history.save(
      device,
      _snapshot('history', ['/saved']),
      [_file('/saved')],
      20,
      source: scanner,
    );
    final provider = galleryScanProvider(device, scope: Object());
    container.listen(provider, (_, _) {});
    expect(container.read(provider).showingPrevious, isTrue);
    final start = container.read(provider.notifier).start();
    final replacement = _Scanner();
    container.updateOverrides([
      galleryScannerProvider.overrideWithValue(replacement),
    ]);
    await _flush(container);
    expect(container.read(provider).items, isEmpty);
    expect(history.read(device), isNull);
    scanner.starts.single.complete(_snapshot('retired', ['/old']));
    await start;
    await _flush(container);
    expect(scanner.cancelled, [(deviceId: 'device', scanId: 'retired')]);
    expect(replacement.cancelled, isEmpty);
    history.save(
      device,
      _snapshot('history', ['/saved']),
      [_file('/saved')],
      20,
      source: scanner,
    );
    expect(history.read(device), isNull);
    expect(container.read(provider).items, isEmpty);
  });

  test('分页拒绝重复路径，保留已确认集合并允许重新核验', () async {
    final provider = galleryScanProvider(device, scope: Object());
    container.listen(provider, (_, _) {});
    final actions = container.read(provider.notifier);
    final start = actions.start();
    scanner.starts.single.complete(
      _snapshot('scan', ['/first'], nextOffset: 1),
    );
    await start;
    final more = actions.loadMore();
    expect(scanner.reads.single.offset, 1);
    scanner.reads.single.result.complete(
      _snapshot('scan', ['/first'], offset: 1),
    );
    await more;
    expect(container.read(provider).items.single.path, '/first');
    expect(container.read(provider).error, contains('重复'));
    expect(container.read(provider).paging, isFalse);
  });

  test('后台检查不替换正在浏览的旧集合，用户采用后才更新', () async {
    final history = container.read(galleryHistoryProvider.notifier);
    history.save(
      device,
      _snapshot('history', ['/saved']),
      [_file('/saved')],
      10,
      source: scanner,
    );
    final provider = galleryScanProvider(device, scope: Object());
    container.listen(provider, (_, _) {});
    final actions = container.read(provider.notifier);
    final start = actions.start();
    scanner.starts.single.complete(_snapshot('new', ['/new']));
    await start;
    expect(container.read(provider).items.single.path, '/saved');
    expect(container.read(provider).pendingItems.single.path, '/new');
    actions.applyUpdate();
    expect(container.read(provider).items.single.path, '/new');
    expect(container.read(provider).pendingResult, isNull);
  });
}

FileCatalogEntry _file(String path) => FileCatalogEntry(path: path, name: path);
GalleryScanSnapshot _snapshot(
  String id,
  List<String> paths, {
  int offset = 0,
  int? nextOffset,
}) => GalleryScanSnapshot(
  deviceId: 'device',
  scanId: id,
  status: GalleryScanStatus.completed,
  items: paths.map(_file).toList(),
  offset: offset,
  nextOffset: nextOffset,
);

class _Scanner implements GalleryScanner {
  final starts = <Completer<GalleryScanSnapshot>>[];
  final reads = <({int offset, Completer<GalleryScanSnapshot> result})>[];
  final cancelled = <GalleryScanTarget>[];
  @override
  Future<GalleryScanSnapshot> startScan(String deviceId, {int limit = 100}) {
    final result = Completer<GalleryScanSnapshot>();
    starts.add(result);
    return result.future;
  }

  @override
  Future<GalleryScanSnapshot> readScan(
    GalleryScanTarget target, {
    int offset = 0,
    int limit = 100,
  }) {
    final result = Completer<GalleryScanSnapshot>();
    reads.add((offset: offset, result: result));
    return result.future;
  }

  @override
  Future<GalleryScanSnapshot> cancelScan(GalleryScanTarget target) async {
    cancelled.add(target);
    return _snapshot(target.scanId, []);
  }
}

Future<void> _flush(ProviderContainer container) async {
  await Future<void>.delayed(Duration.zero);
  await container.pump();
}
