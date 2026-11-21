import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_filex/open_filex.dart';
import 'package:scrcpy_connect/core/content/content_capabilities_provider.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/platform/platform_channels.dart';

Future<void> openPreparedFile(
  BuildContext context,
  WidgetRef ref,
  String path,
) async {
  final cache = ref.read(contentCacheControlProvider);
  await cache.retain(path, ifManaged: true);
  if (!context.mounted ||
      !identical(ref.read(contentCacheControlProvider), cache)) {
    return;
  }
  if (Platform.isAndroid) {
    await const PlatformChannels().request(
      'documents.platform.openPreparedFile',
      {'path': path},
    );
    return;
  }
  final result = await OpenFilex.open(path);
  if (result.type != ResultType.done) {
    throw RequestFailure('open_failed', result.message);
  }
}
