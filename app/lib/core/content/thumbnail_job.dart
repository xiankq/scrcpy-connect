import 'package:freezed_annotation/freezed_annotation.dart';

part 'thumbnail_job.freezed.dart';

enum ThumbnailKind { image, video }

enum ThumbnailPhase { stat, thumbnail }

@freezed
class ThumbnailJob with _$ThumbnailJob {
  const ThumbnailJob({
    required this.deviceId,
    required this.operationId,
    required this.ownerOperationId,
    required this.path,
    required this.kind,
    required this.maxSize,
    required this.phase,
    this.allowStart = true,
  });
  final String deviceId, operationId, ownerOperationId, path;
  final ThumbnailKind kind;
  final int maxSize;
  final ThumbnailPhase phase;
  final bool allowStart;
}

abstract interface class ThumbnailJobs {
  Future<Map<String, dynamic>> run(ThumbnailJob job);
  Future<void> cancel(String deviceId, String operationId);
}
