import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/gallery/models/gallery_scan.dart';

final class GalleryScanChanged extends AppEvent {
  const GalleryScanChanged(this.target);
  final GalleryScanTarget target;

  @override
  String get type => 'media.scan.changed';

  @override
  String get deviceId => target.deviceId;
}
