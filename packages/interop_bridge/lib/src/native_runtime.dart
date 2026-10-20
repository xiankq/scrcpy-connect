import 'dart:io';
import 'dart:convert';

import 'connection_policy.dart';
import 'application_settings.dart';

import 'bundled_servers.dart';
import 'rust/api.dart' as core;

/// Prepares Flutter package assets before attaching the native runtime.
Future<void> initializeNativeRuntime({
  required String dataDirectory,
  ConnectionPolicy connectionPolicy = const ConnectionPolicy(),
}) async {
  if (Platform.isAndroid) {
    await BundledServers().prepare(Directory(dataDirectory));
  }
  await core.initialize(
    dataDirectory: dataDirectory,
    connectionPolicyJson: jsonEncode(connectionPolicy.toNativeJson()),
    settingsDefaultsJson: jsonEncode(applicationSettings),
  );
}
