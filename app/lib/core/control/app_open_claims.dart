/// 同一设备应用一次只允许一个交互流程；关闭后旧流程不能接管新请求。
final class AppOpenClaims {
  final _tokens = <(String, String), Object>{};
  bool _closed = false;
  bool get closed => _closed;

  void Function()? claim(String deviceId, String packageName) {
    if (_closed) return null;
    final key = (deviceId, packageName);
    if (_tokens.containsKey(key)) return null;
    final token = Object();
    _tokens[key] = token;
    return () {
      if (identical(_tokens[key], token)) _tokens.remove(key);
    };
  }

  void close() {
    _closed = true;
    _tokens.clear();
  }
}
