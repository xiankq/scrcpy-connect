/// Route payload used when a host starts a second Flutter engine.
///
/// The route is intentionally opaque to the application router. The entrypoint
/// decodes it before constructing the normal typed remote route.
String independentWindowLaunchRoute({
  required String deviceId,
  required String packageName,
  required String sessionId,
}) {
  return Uri(
    path: '/__independent_remote',
    queryParameters: {
      'deviceId': deviceId,
      'packageName': packageName,
      'sessionId': sessionId,
    },
  ).toString();
}

Map<String, String>? decodeIndependentWindowLaunchRoute(String route) {
  final uri = Uri.tryParse(route);
  if (uri?.path != '/__independent_remote') return null;
  final deviceId = uri?.queryParameters['deviceId'];
  final packageName = uri?.queryParameters['packageName'];
  final sessionId = uri?.queryParameters['sessionId'];
  if (deviceId == null || packageName == null || sessionId == null) return null;
  if (deviceId.isEmpty || packageName.isEmpty || sessionId.isEmpty) return null;
  return {
    'deviceId': deviceId,
    'packageName': packageName,
    'sessionId': sessionId,
  };
}
