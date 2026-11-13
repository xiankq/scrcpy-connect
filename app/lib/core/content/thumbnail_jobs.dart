import 'package:scrcpy_connect/core/content/models/thumbnail_job.dart';
import 'package:scrcpy_connect/core/content/models/thumbnail_image.dart';
import 'package:scrcpy_connect/core/content/models/thumbnail_source.dart';

export 'package:scrcpy_connect/core/content/models/thumbnail_job.dart';
export 'package:scrcpy_connect/core/content/models/thumbnail_image.dart';
export 'package:scrcpy_connect/core/content/models/thumbnail_source.dart';

abstract interface class ThumbnailJobs {
  Future<ThumbnailSource> readSource(ThumbnailJob job);
  Future<ThumbnailImage> render(ThumbnailJob job);
  Future<void> cancel(String deviceId, String operationId);
}
