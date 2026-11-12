typedef Json = Map<String, dynamic>;

class RequestFailure implements Exception {
  const RequestFailure(this.code, this.message, [this.details]);
  final String code;
  final String message;
  final Object? details;
  @override
  String toString() => message;
}
