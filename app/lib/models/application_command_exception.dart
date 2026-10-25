/// 应用命令执行失败；能力包的协议异常由应用责任所有者转换后上报。
class ApplicationCommandException implements Exception {
  const ApplicationCommandException(this.code, this.message, [this.details]);
  final String code;
  final String message;
  final Object? details;

  @override
  String toString() => message;
}
