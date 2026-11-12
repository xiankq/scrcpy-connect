import 'package:scrcpy_connect/core/events/models/app_event.dart';

final class ContentCacheChanged extends AppEvent {
  const ContentCacheChanged();

  @override
  String get type => 'media.cache.changed';
}
