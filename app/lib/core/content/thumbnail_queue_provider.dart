import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/application/application_session_provider.dart';

import 'thumbnail_queue.dart';

export 'thumbnail_queue.dart';

part 'thumbnail_queue_provider.g.dart';

@riverpod
ThumbnailQueue thumbnailQueue(Ref ref, String deviceId) {
  final session = ref.watch(applicationSessionProvider);
  final content = session.dependencies.content;
  final queue = ThumbnailQueue(
    load: (path, operationId) => content.thumbnail(
      deviceId: deviceId,
      path: path,
      operationId: operationId,
    ),
    cancel: (operationId) =>
        content.cancelThumbnail(deviceId: deviceId, operationId: operationId),
    releaseLease: content.releaseLease,
    keepAlive: () {
      final link = ref.keepAlive();
      return link.close;
    },
  );
  ref.onDispose(queue.dispose);
  return queue;
}
