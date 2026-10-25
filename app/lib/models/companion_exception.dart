/// RPC 的可判断错误；副作用已发出而没有确定回执时使用 result_unknown。
final class CompanionException implements Exception {
  const CompanionException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'CompanionException($code: $message)';
}
