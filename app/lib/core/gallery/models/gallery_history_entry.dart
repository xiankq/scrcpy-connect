import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart';
import 'package:scrcpy_connect/core/gallery/models/gallery_scan.dart';

part 'gallery_history_entry.freezed.dart';

@freezed
abstract class GalleryHistoryEntry with _$GalleryHistoryEntry {
  const GalleryHistoryEntry._();
  const factory GalleryHistoryEntry({
    required DeviceSnapshot device,
    required GalleryScanSnapshot result,
    required List<FileCatalogEntry> items,
    required double scrollOffset,
    GalleryScanSnapshot? pendingResult,
  }) = _GalleryHistoryEntry;

  bool matches(DeviceSnapshot record) =>
      device.id == record.id &&
      device.guid == record.guid &&
      device.serial == record.serial;
}
