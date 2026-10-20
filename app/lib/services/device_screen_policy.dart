/// Local phone-page ownership. Connection wake policy belongs to the bridge.
class DeviceScreenPolicy {
  final _phonePages = <Object, String>{};

  Object claimPhonePage(String device) {
    final token = Object();
    _phonePages[token] = device;
    return token;
  }

  bool releasePhonePage(Object token) {
    final device = _phonePages.remove(token);
    return device != null && !_phonePages.containsValue(device);
  }

  bool hasPhonePages(String device) => _phonePages.containsValue(device);
}
