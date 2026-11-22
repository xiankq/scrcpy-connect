import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart';
import 'package:scrcpy_connect/core/gallery/gallery_scanner.dart';
import 'package:scrcpy_connect/core/gallery/models/gallery_history_entry.dart';

import 'gallery_scanner_provider.dart';

part 'gallery_history_notifier.g.dart';

/// 同一应用 scope 的已核验相册历史，最多保留八台设备。
@Riverpod(keepAlive: true)
class GalleryHistoryNotifier extends _$GalleryHistoryNotifier {
  @override
  Map<String, GalleryHistoryEntry> build() {
    ref.watch(galleryScannerProvider);
    return const {};
  }

  GalleryHistoryEntry? read(DeviceSnapshot device) {
    if (!ref.mounted) return null;
    final entry = state[device.id];
    return entry != null && entry.matches(device) ? entry : null;
  }

  void save(
    DeviceSnapshot device,
    GalleryScanSnapshot result,
    List<FileCatalogEntry> items,
    double offset, {
    required GalleryScanner source,
    GalleryScanSnapshot? pendingResult,
  }) {
    if (!ref.mounted || !identical(ref.read(galleryScannerProvider), source)) {
      return;
    }
    final id = device.id;
    if (id.isEmpty || result.deviceId != id) return;
    final next = {...state}..remove(id);
    while (next.length >= 8) {
      next.remove(next.keys.first);
    }
    next[id] = GalleryHistoryEntry(
      device: device,
      result: result.status == .scanning
          ? result.copyWith(status: .cancelled)
          : result,
      items: List.unmodifiable(items),
      scrollOffset: offset,
      pendingResult: pendingResult,
    );
    state = Map.unmodifiable(next);
  }
}
