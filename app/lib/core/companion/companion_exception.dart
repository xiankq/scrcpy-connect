/// RPC 的可判断错误；副作用已发出而没有确定回执时使用 result_unknown。
final class CompanionException implements Exception {
  const CompanionException(this.code, this.message, {this.mediaReaped = false});
  final String code;
  final String message;
  final bool mediaReaped;
  @override
  String toString() => 'CompanionException($code: $message)';
}
