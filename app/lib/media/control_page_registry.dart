/// 拥有已打开画面的计数，包含整机远控与独立应用窗口。
class ControlPageRegistry {
  final _pages = <Object, ({String device, String? sessionId})>{};

  Object claim(String device, {String? sessionId}) {
    if (sessionId != null && sessionId.isNotEmpty) {
      // 重新附着同一窗口时转移所有权，旧路由不能继续计数或释放新所有者。
      _pages.removeWhere(
        (_, page) => page.device == device && page.sessionId == sessionId,
      );
    }
    final token = Object();
    _pages[token] = (device: device, sessionId: sessionId);
    return token;
  }

  bool release(Object token) {
    final page = _pages.remove(token);
    return page != null && !hasPages(page.device);
  }

  bool hasPages(String device) =>
      _pages.values.any((page) => page.device == device);
}
