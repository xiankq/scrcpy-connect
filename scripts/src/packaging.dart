String? updateFeedDefine(String? address) {
  if (address == null || address.isEmpty) return null;
  final uri = Uri.tryParse(address);
  if (uri == null ||
      !uri.isScheme('https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw ArgumentError('The update feed must be a public HTTPS URL.');
  }
  return '--dart-define=APP_UPDATE_FEED=$address';
}
