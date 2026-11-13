import 'package:freezed_annotation/freezed_annotation.dart';

part 'thumbnail_job.freezed.dart';

enum ThumbnailKind { image, video }

@freezed
class ThumbnailJob with _$ThumbnailJob {
  const ThumbnailJob({
    required this.deviceId,
    required this.operationId,
    required this.ownerOperationId,
    required this.path,
    required this.kind,
    required this.maxSize,
    this.allowStart = true,
  });
  final String deviceId, operationId, ownerOperationId, path;
  final ThumbnailKind kind;
  final int maxSize;
  final bool allowStart;
}
