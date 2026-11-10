final class MediaCacheFailure implements Exception {
  const MediaCacheFailure(this.code, this.message);
  final String code, message;
  @override
  String toString() => '$code: $message';
}
