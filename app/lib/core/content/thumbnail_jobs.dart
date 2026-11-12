import 'package:scrcpy_connect/core/content/models/thumbnail_job.dart';

export 'package:scrcpy_connect/core/content/models/thumbnail_job.dart';

abstract interface class ThumbnailJobs {
  Future<Map<String, dynamic>> run(ThumbnailJob job);
  Future<void> cancel(String deviceId, String operationId);
}
