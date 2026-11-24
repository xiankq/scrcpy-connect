const independentWindowPath = '/__independent_remote';

String independentWindowLaunchRoute(String windowId) => Uri(
  path: independentWindowPath,
  queryParameters: {'windowId': windowId},
).toString();

String? decodeIndependentWindowLaunchRoute(String route) {
  final uri = Uri.tryParse(route);
  if (uri?.path != independentWindowPath) return null;
  final id = uri?.queryParameters['windowId'];
  return id == null || id.isEmpty ? null : id;
}
