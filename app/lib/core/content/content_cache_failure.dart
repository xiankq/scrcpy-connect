final class ContentCacheFailure implements Exception {
  const ContentCacheFailure(this.code, this.message);
  final String code, message;
  @override
  String toString() => '$code: $message';
}
