class FileFailure implements Exception {
  const FileFailure(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => '$code: $message';
}
