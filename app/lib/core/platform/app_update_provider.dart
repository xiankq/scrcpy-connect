import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/platform/app_release.dart';

final appUpdateReaderProvider = Provider<Future<List<AppRelease>> Function()?>((
  ref,
) {
  const feed = String.fromEnvironment('APP_UPDATE_FEED');
  if (feed.isEmpty) return null;
  return () => readAppReleases(Uri.parse(feed));
});
