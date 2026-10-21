/// Open screen ownership, including phone and independent application windows.
/// Existing method names remain compatible with controller callers.
class DeviceScreenPolicy {
  final _phonePages = <Object, ({String device, String? sessionId})>{};

  Object claimPhonePage(String device, {String? sessionId}) {
    if (sessionId != null && sessionId.isNotEmpty) {
      // Reattaching the same window transfers ownership. An obsolete route
      // cannot keep a closed window counted or release its newer owner.
      _phonePages.removeWhere(
        (_, page) => page.device == device && page.sessionId == sessionId,
      );
    }
    final token = Object();
    _phonePages[token] = (device: device, sessionId: sessionId);
    return token;
  }

  bool releasePhonePage(Object token) {
    final page = _phonePages.remove(token);
    return page != null && !hasPhonePages(page.device);
  }

  bool hasPhonePages(String device) =>
      _phonePages.values.any((page) => page.device == device);
}
