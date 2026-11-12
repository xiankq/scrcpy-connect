import 'package:scrcpy_connect/core/gallery/models/gallery_scan.dart';

export 'package:scrcpy_connect/core/gallery/models/gallery_scan.dart';

abstract interface class GalleryScanner {
  Future<GalleryScanSnapshot> startScan(String deviceId, {int limit = 100});
  Future<GalleryScanSnapshot> readScan(
    GalleryScanTarget target, {
    int offset = 0,
    int limit = 100,
  });
  Future<GalleryScanSnapshot> cancelScan(GalleryScanTarget target);
}
