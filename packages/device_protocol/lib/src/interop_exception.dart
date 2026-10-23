class InteropException implements Exception {
  const InteropException(this.code, this.message, [this.details]);
  final String code;
  final String message;
  final Object? details;

  @override
  String toString() => message;
}
