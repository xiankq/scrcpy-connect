import 'dart:io';

import 'bundled_servers.dart';
import 'rust/api.dart' as core;

/// Prepares Flutter package assets before attaching the native runtime.
Future<void> initializeNativeRuntime({required String dataDirectory}) async {
  if (Platform.isAndroid) {
    await BundledServers().prepare(Directory(dataDirectory));
  }
  await core.initialize(dataDirectory: dataDirectory);
}
