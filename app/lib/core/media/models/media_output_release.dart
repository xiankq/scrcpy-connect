/// 原输出的实际回收证据；等待期限结束不能代替原生释放确认。
final class MediaOutputRelease {
  const MediaOutputRelease({
    required this.nativeDeleteConfirmed,
    this.cleanupUnconfirmed = false,
    this.disposeRequested,
    this.disposeDeferred,
    this.resourceAllocated,
  });
  const MediaOutputRelease.unknown({this.disposeRequested = false})
    : nativeDeleteConfirmed = false,
      cleanupUnconfirmed = true,
      disposeDeferred = null,
      resourceAllocated = null;

  factory MediaOutputRelease.fromProtocol(Map<String, dynamic> value) =>
      MediaOutputRelease(
        nativeDeleteConfirmed: value['nativeDeleteConfirmed'] == true,
        cleanupUnconfirmed: value['cleanupUnconfirmed'] == true,
        disposeRequested: value['disposeRequested'] as bool?,
        disposeDeferred: value['disposeDeferred'] as bool?,
        resourceAllocated: value['resourceAllocated'] as bool?,
      );
  final bool nativeDeleteConfirmed, cleanupUnconfirmed;
  final bool? disposeRequested, disposeDeferred, resourceAllocated;
  bool get confirmed => nativeDeleteConfirmed && !cleanupUnconfirmed;

  MediaOutputRelease markUnconfirmed() => MediaOutputRelease(
    nativeDeleteConfirmed: nativeDeleteConfirmed,
    cleanupUnconfirmed: true,
    disposeRequested: disposeRequested,
    disposeDeferred: disposeDeferred,
    resourceAllocated: resourceAllocated,
  );

  Map<String, dynamic> toDiagnosticFields() => {
    'nativeDeleteConfirmed': nativeDeleteConfirmed,
    'cleanupUnconfirmed': cleanupUnconfirmed,
    'disposeRequested': ?disposeRequested,
    'disposeDeferred': ?disposeDeferred,
    'resourceAllocated': ?resourceAllocated,
  };
}

/// 停止意图已经提交，outputs 保留每个实际输出的释放结果。
final class MediaOutputStop {
  MediaOutputStop(this.id, Iterable<MediaOutputRelease> outputs)
    : outputs = List.unmodifiable(outputs);
  final String id;
  final List<MediaOutputRelease> outputs;
  bool get confirmed => outputs.every((output) => output.confirmed);
}
